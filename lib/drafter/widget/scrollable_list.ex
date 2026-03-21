defmodule Drafter.Widget.ScrollableList do
  @moduledoc """
  Shared scrollable list behavior for widgets that display selectable lists of data.

  This module provides common functionality for:
  - Navigation (up/down/home/end/page up/page down)
  - Selection (single/multiple)
  - Scrolling and viewport management
  - Mouse interaction
  - Keyboard interaction

  Widgets using this behavior need to implement:
  - get_item_count/1 - returns total number of items
  - get_item_at/2 - returns item at index
  - is_item_enabled/2 - returns if item can be selected
  - render_item/4 - renders individual item
  """

  @type selection_mode :: :none | :single | :multiple

  @type scroll_state :: %{
          highlighted_index: integer() | nil,
          selected_indices: MapSet.t(),
          scroll_offset: integer(),
          visible_height: integer(),
          selection_mode: selection_mode(),
          last_scroll_time: integer(),
          scroll_throttle_ms: integer()
        }

  @doc "Initialize scroll state"
  def init_scroll_state(opts \\ []) do
    %{
      highlighted_index: nil,
      selected_indices: MapSet.new(),
      scroll_offset: 0,
      visible_height: Keyword.get(opts, :visible_height, 10),
      selection_mode: Keyword.get(opts, :selection_mode, :single),
      last_scroll_time: 0,
      scroll_throttle_ms: Keyword.get(opts, :scroll_throttle_ms, 150)
    }
  end

  @doc "Handle navigation and selection events"
  def handle_scroll_event(widget_state, event, callbacks \\ %{}) do
    case event do
      {:key, :up} ->
        action_cursor_up(widget_state, callbacks)

      {:key, :down} ->
        action_cursor_down(widget_state, callbacks)

      {:key, :home} ->
        action_cursor_first(widget_state, callbacks)

      {:key, :end} ->
        action_cursor_last(widget_state, callbacks)

      {:key, :page_up} ->
        action_page_up(widget_state, callbacks)

      {:key, :page_down} ->
        action_page_down(widget_state, callbacks)

      {:key, :enter} ->
        action_select_highlighted(widget_state, callbacks)

      {:key, :space} ->
        action_toggle_selection(widget_state, callbacks)

      {:mouse, %{type: :mouse_up, y: y}} ->
        clicked_index = widget_state.scroll_offset + y
        action_click_item(widget_state, clicked_index, callbacks)

      {:mouse, %{type: :scroll, direction: direction}} ->
        handle_mouse_scroll(widget_state, direction, callbacks)

      {:focus} ->
        # When receiving focus, ensure we have a highlighted item
        new_state =
          if widget_state.highlighted_index == nil do
            case find_first_enabled(widget_state, callbacks) do
              nil -> widget_state
              index -> %{widget_state | highlighted_index: index}
            end
          else
            widget_state
          end

        {:noreply, new_state}

      {:blur} ->
        # Keep highlighted_index when losing focus
        {:noreply, widget_state}

      _ ->
        {:noreply, widget_state}
    end
  end

  # Navigation actions

  defp action_cursor_up(state, callbacks) do
    case find_previous_enabled(state, callbacks) do
      nil -> {:noreply, state}
      new_index -> change_selection(state, new_index, false, callbacks)
    end
  end

  defp action_cursor_down(state, callbacks) do
    case find_next_enabled(state, callbacks) do
      nil -> {:noreply, state}
      new_index -> change_selection(state, new_index, false, callbacks)
    end
  end

  defp action_cursor_first(state, callbacks) do
    case find_first_enabled(state, callbacks) do
      nil -> {:noreply, state}
      new_index -> change_selection(state, new_index, false, callbacks)
    end
  end

  defp action_cursor_last(state, callbacks) do
    case find_last_enabled(state, callbacks) do
      nil -> {:noreply, state}
      new_index -> change_selection(state, new_index, false, callbacks)
    end
  end

  defp action_page_up(state, callbacks) do
    current = state.highlighted_index || 0
    target_index = max(0, current - state.visible_height)

    new_index =
      case find_previous_enabled_from(state, target_index, callbacks) do
        nil ->
          find_next_enabled_from(state, target_index, callbacks) ||
            find_first_enabled(state, callbacks)

        index ->
          index
      end

    if new_index do
      change_selection(state, new_index, false, callbacks)
    else
      {:noreply, state}
    end
  end

  defp action_page_down(state, callbacks) do
    item_count = callbacks.get_item_count.(state)
    current = state.highlighted_index || 0
    target_index = min(item_count - 1, current + state.visible_height)

    new_index =
      case find_next_enabled_from(state, target_index, callbacks) do
        nil ->
          find_previous_enabled_from(state, target_index, callbacks) ||
            find_last_enabled(state, callbacks)

        index ->
          index
      end

    if new_index do
      change_selection(state, new_index, false, callbacks)
    else
      {:noreply, state}
    end
  end

  defp action_select_highlighted(state, callbacks) do
    if state.highlighted_index do
      change_selection(state, state.highlighted_index, true, callbacks)
    else
      {:noreply, state}
    end
  end

  defp action_toggle_selection(state, callbacks) do
    if state.highlighted_index && state.selection_mode == :multiple do
      new_selected =
        if MapSet.member?(state.selected_indices, state.highlighted_index) do
          MapSet.delete(state.selected_indices, state.highlighted_index)
        else
          MapSet.put(state.selected_indices, state.highlighted_index)
        end

      new_state = %{state | selected_indices: new_selected}
      trigger_selection_callback(new_state, callbacks)
      {:ok, new_state}
    else
      action_select_highlighted(state, callbacks)
    end
  end

  defp action_click_item(state, clicked_index, callbacks) do
    item_count = callbacks.get_item_count.(state)

    if clicked_index >= 0 and clicked_index < item_count do
      if callbacks.is_item_enabled.(state, clicked_index) do
        change_selection(state, clicked_index, true, callbacks)
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Scroll management

  defp handle_mouse_scroll(state, direction, callbacks) do
    current_time = System.system_time(:millisecond)
    time_since_last = current_time - state.last_scroll_time

    if state.last_scroll_time == 0 or time_since_last >= state.scroll_throttle_ms do
      scroll_action =
        case direction do
          :up -> action_cursor_up(state, callbacks)
          :down -> action_cursor_down(state, callbacks)
        end

      case scroll_action do
        {:ok, new_state} ->
          {:ok, %{new_state | last_scroll_time: current_time}}

        {:ok, new_state, actions} ->
          {:ok, %{new_state | last_scroll_time: current_time}, actions}

        {:noreply, new_state} ->
          {:noreply, %{new_state | last_scroll_time: current_time}}

        other ->
          other
      end
    else
      {:noreply, state}
    end
  end

  def ensure_visible(state, target_index) do
    cond do
      target_index < state.scroll_offset ->
        %{state | scroll_offset: target_index}

      target_index >= state.scroll_offset + state.visible_height ->
        new_offset = target_index - state.visible_height + 1
        %{state | scroll_offset: max(0, new_offset)}

      true ->
        state
    end
  end

  # Selection management

  defp change_selection(state, target_index, trigger_select, callbacks) do
    item_count = callbacks.get_item_count.(state)

    if target_index >= 0 and target_index < item_count do
      if callbacks.is_item_enabled.(state, target_index) do
        new_state =
          %{state | highlighted_index: target_index}
          |> ensure_visible(target_index)

        new_state =
          if trigger_select do
            case state.selection_mode do
              :none ->
                new_state

              :single ->
                %{new_state | selected_indices: MapSet.new([target_index])}

              :multiple ->
                # In multiple mode, clicking adds to selection
                new_selected = MapSet.put(state.selected_indices, target_index)
                %{new_state | selected_indices: new_selected}
            end
          else
            new_state
          end

        # Trigger callbacks if highlight changed
        actions = []

        actions =
          if callbacks[:on_highlight] && target_index != state.highlighted_index do
            item = callbacks.get_item_at.(new_state, target_index)
            [callbacks.on_highlight.(item) | actions]
          else
            actions
          end

        actions =
          if trigger_select && callbacks[:on_select] do
            selected_items = get_selected_items(new_state, callbacks)
            [callbacks.on_select.(selected_items) | actions]
          else
            actions
          end

        if length(actions) > 0 do
          {:ok, new_state, actions}
        else
          {:ok, new_state}
        end
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp trigger_selection_callback(state, callbacks) do
    if callbacks[:on_select] do
      selected_items = get_selected_items(state, callbacks)
      callbacks.on_select.(selected_items)
    end
  end

  defp get_selected_items(state, callbacks) do
    state.selected_indices
    |> MapSet.to_list()
    |> Enum.map(fn index -> callbacks.get_item_at.(state, index) end)
    |> Enum.filter(& &1)
  end

  # Item finding helpers

  defp find_first_enabled(state, callbacks) do
    _item_count = callbacks.get_item_count.(state)
    find_next_enabled_from(state, -1, callbacks)
  end

  defp find_last_enabled(state, callbacks) do
    item_count = callbacks.get_item_count.(state)
    find_previous_enabled_from(state, item_count, callbacks)
  end

  defp find_next_enabled(state, callbacks) do
    current_index = state.highlighted_index
    find_next_enabled_from(state, current_index, callbacks)
  end

  defp find_previous_enabled(state, callbacks) do
    current_index = state.highlighted_index
    find_previous_enabled_from(state, current_index, callbacks)
  end

  defp find_next_enabled_from(state, start_index, callbacks) do
    item_count = callbacks.get_item_count.(state)
    search_start = if start_index, do: start_index + 1, else: 0

    search_start..(item_count - 1)
    |> Enum.find(fn index ->
      callbacks.is_item_enabled.(state, index)
    end)
  end

  defp find_previous_enabled_from(state, end_index, callbacks) do
    search_end = if end_index && end_index > 0, do: end_index - 1, else: -1

    if search_end >= 0 do
      search_end..0//-1
      |> Enum.find(fn index ->
        callbacks.is_item_enabled.(state, index)
      end)
    else
      nil
    end
  end

  @doc "Get visible items for rendering"
  def get_visible_items(state, callbacks) do
    item_count = callbacks.get_item_count.(state)
    visible_count = min(state.visible_height, item_count - state.scroll_offset)

    if visible_count > 0 do
      state.scroll_offset..(state.scroll_offset + visible_count - 1)
      |> Enum.map(fn index ->
        {index, callbacks.get_item_at.(state, index)}
      end)
      |> Enum.filter(fn {_, item} -> item != nil end)
    else
      []
    end
  end

  @doc "Check if an index is highlighted"
  def is_highlighted?(state, index), do: state.highlighted_index == index

  @doc "Check if an index is selected"
  def is_selected?(state, index), do: MapSet.member?(state.selected_indices, index)
end
