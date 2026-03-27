defmodule Drafter.Widget.DataTable.Selection do
  @moduledoc false

  alias Drafter.Widget.DataTable
  alias Drafter.Widget.DataTable.{Columns, Sorting}

  def action_scroll_up(state) do
    if state.scroll.offset > 0 do
      new_state = put_in(state.scroll.offset, state.scroll.offset - 1)
      {:ok, new_state, [:render_update]}
    else
      {:ok, state, []}
    end
  end

  def action_scroll_down(state, data_height) do
    max_scroll = max(0, length(state.data) - data_height)

    if state.scroll.offset < max_scroll do
      new_state = put_in(state.scroll.offset, state.scroll.offset + 1)
      {:ok, new_state, [:render_update]}
    else
      {:ok, state, []}
    end
  end

  def action_cursor_up(state) do
    case find_previous_enabled(state.data, get_highlighted_index(state)) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  def action_cursor_down(state) do
    case find_next_enabled(state.data, get_highlighted_index(state)) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  def action_cursor_first(state) do
    case find_first_enabled(state.data) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  def action_cursor_last(state) do
    new_index = find_last_enabled(state.data)
    change_selection(state, new_index, false)
  end

  def action_page_up(state, data_height) do
    current = get_highlighted_index(state) || 0
    target_index = max(0, current - data_height)

    new_index =
      case find_previous_enabled_from(state.data, target_index) do
        nil -> find_next_enabled_from(state.data, target_index) || find_first_enabled(state.data)
        index -> index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:ok, state, []}
    end
  end

  def action_page_down(state, data_height) do
    current = get_highlighted_index(state) || 0
    target_index = min(length(state.data) - 1, current + data_height)

    new_index =
      case find_next_enabled_from(state.data, target_index) do
        nil ->
          find_previous_enabled_from(state.data, target_index) || find_last_enabled(state.data)

        index ->
          index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:ok, state, []}
    end
  end

  def action_select_highlighted(state) do
    if highlighted_index = get_highlighted_index(state) do
      change_selection(state, highlighted_index, true)
    else
      {:ok, state, []}
    end
  end

  def toggle_multiple_selection(state, highlighted_index) do
    new_selected =
      if selected?(state, highlighted_index),
        do: MapSet.delete(state.selected_indices, highlighted_index),
        else: MapSet.put(state.selected_indices, highlighted_index)

    new_state = %{state | selected_indices: new_selected}
    actions = fire_on_select(state.callbacks.on_select, new_state, state.data)

    if actions != [] do
      {:ok, new_state, actions}
    else
      {:ok, new_state}
    end
  end

  def action_toggle_selection(state) do
    case get_highlighted_index(state) do
      nil ->
        {:ok, state}

      highlighted_index when state.selection_mode == :multiple ->
        toggle_multiple_selection(state, highlighted_index)

      highlighted_index ->
        change_selection(state, highlighted_index, true)
    end
  end

  def move_cursor_horizontal(%{cursor_col: col} = state, :left) when col > 0 do
    new_state = %{state | cursor_col: col - 1} |> Columns.adjust_scroll_horizontal()
    {:ok, new_state, [:render_update]}
  end

  def move_cursor_horizontal(state, :left), do: {:noreply, state}

  def move_cursor_horizontal(%{cursor_col: col, columns: columns} = state, :right)
      when col < length(columns) - 1 do
    new_state = %{state | cursor_col: col + 1} |> Columns.adjust_scroll_horizontal()
    {:ok, new_state, [:render_update]}
  end

  def move_cursor_horizontal(state, :right), do: {:noreply, state}

  def get_highlighted_index(state), do: state.highlighted_index

  def selected?(state, index), do: MapSet.member?(state.selected_indices, index)

  def apply_selection_update(state, _target_index, :none), do: state

  def apply_selection_update(state, target_index, :single) do
    new_selected =
      if selected?(state, target_index),
        do: MapSet.new(),
        else: MapSet.new([target_index])

    %{state | selected_indices: new_selected}
  end

  def apply_selection_update(state, target_index, :multiple) do
    new_selected =
      if selected?(state, target_index),
        do: MapSet.delete(state.selected_indices, target_index),
        else: MapSet.put(state.selected_indices, target_index)

    %{state | selected_indices: new_selected}
  end

  def fire_on_select(nil, _new_state, _data), do: []

  def fire_on_select(on_select, new_state, data) do
    selected_items =
      new_state.selected_indices
      |> MapSet.to_list()
      |> Enum.map(fn index -> Enum.at(data, index) end)
      |> Enum.filter(& &1)

    [on_select.(selected_items)]
  end

  def change_selection(state, target_index, trigger_select) do
    data_height = DataTable.get_data_height(state)

    if target_index >= 0 and target_index < length(state.data) do
      new_state =
        %{state | highlighted_index: target_index}
        |> ensure_visible_index(target_index, data_height)

      if state.callbacks.on_row_highlight && target_index != state.highlighted_index do
        row = Enum.at(state.data, target_index)
        state.callbacks.on_row_highlight.(row)
      end

      new_state =
        if trigger_select do
          apply_selection_update(new_state, target_index, state.selection_mode)
        else
          new_state
        end

      select_actions =
        if trigger_select do
          fire_on_select(state.callbacks.on_select, new_state, state.data)
        else
          []
        end

      {:ok, new_state, [:render_update | select_actions]}
    else
      {:ok, state, []}
    end
  end

  def ensure_visible_index(state, target_index, visible_height) do
    cond do
      target_index < state.scroll.offset ->
        put_in(state.scroll.offset, target_index)

      target_index >= state.scroll.offset + visible_height ->
        new_offset = target_index - visible_height + 1
        put_in(state.scroll.offset, max(0, new_offset))

      true ->
        state
    end
  end

  def find_first_enabled(data) do
    Enum.find_index(data, fn _row -> true end)
  end

  def find_last_enabled(data) do
    length(data) - 1
  end

  def find_next_enabled(data, current_index) do
    start_index = if current_index, do: current_index + 1, else: 0
    if start_index < length(data), do: start_index, else: nil
  end

  def find_previous_enabled(_data, current_index) do
    if current_index && current_index > 0, do: current_index - 1, else: nil
  end

  def find_next_enabled_from(data, start_index) do
    if start_index && start_index < length(data) - 1, do: start_index, else: nil
  end

  def find_previous_enabled_from(_data, end_index) do
    if end_index && end_index > 0, do: end_index, else: nil
  end

  def handle_mouse_click(%{show_header: true} = state, x, 0) do
    handle_header_click(state, x)
  end

  def handle_mouse_click(state, x, y) do
    click_region = determine_click_region(state, x, y)
    handle_click_by_region(state, x, y, click_region)
  end

  def determine_click_region(state, x, y) do
    data_start_y = DataTable.get_data_start_y(state)
    data_height = DataTable.get_data_height(state)
    scrollbar_x = state.width - 1

    classify_click_region(state, x, y, scrollbar_x, data_start_y, data_height)
  end

  defp classify_click_region(
         %{show_scrollbars: true} = state,
         x,
         y,
         scrollbar_x,
         data_start_y,
         data_height
       )
       when x == scrollbar_x and y >= data_start_y and length(state.data) > data_height do
    :scrollbar
  end

  defp classify_click_region(_state, _x, y, _scrollbar_x, data_start_y, _data_height)
       when y >= data_start_y, do: :data_row

  defp classify_click_region(_state, _x, _y, _scrollbar_x, _data_start_y, _data_height),
    do: :other

  defp handle_click_by_region(state, _x, y, :scrollbar) do
    data_start_y = DataTable.get_data_start_y(state)
    data_height = DataTable.get_data_height(state)
    handle_scrollbar_click(state, y - data_start_y, data_height)
  end

  defp handle_click_by_region(state, x, y, :data_row) do
    data_start_y = DataTable.get_data_start_y(state)
    data_y = y - data_start_y
    clicked_index = state.scroll.offset + data_y

    if clicked_index >= 0 and clicked_index < length(state.data) do
      {:ok, updated_state, actions} = change_selection(state, clicked_index, true)
      final_state = update_cursor_column(updated_state, x)
      {:ok, final_state, actions}
    else
      {:noreply, state}
    end
  end

  defp handle_click_by_region(state, _x, _y, :other) do
    {:noreply, state}
  end

  def update_cursor_column(state, x) do
    col_index = Columns.calculate_column_from_x(state, x)
    update_cursor_column_if_valid(state, col_index)
  end

  def update_cursor_column_if_valid(state, col_index)
      when col_index >= 0 and col_index < length(state.columns) do
    %{state | cursor_col: col_index}
  end

  def update_cursor_column_if_valid(state, _col_index), do: state

  def handle_scrollbar_click(state, relative_y, data_height) do
    total_rows = length(state.data)

    if total_rows > data_height do
      scroll_range = max(1, data_height - 1)
      click_ratio = relative_y / scroll_range
      target_scroll = Drafter.ScrollMath.from_ratio(click_ratio, total_rows, data_height)

      new_state = %{
        state
        | scroll: %{state.scroll | offset: target_scroll},
          drag: %{state.drag | dragging_scrollbar: true, hovering_scrollbar: true}
      }

      {:ok, new_state, [:render_update]}
    else
      {:noreply, state}
    end
  end

  def drag_scrollbar_to(state, _x, y) do
    data_start_y = DataTable.get_data_start_y(state)
    data_height = DataTable.get_data_height(state)
    relative_y = y - data_start_y |> max(0) |> min(data_height - 1)
    total_rows = length(state.data)

    if total_rows > data_height do
      scroll_range = max(1, data_height - 1)
      drag_ratio = relative_y / scroll_range
      target_scroll = Drafter.ScrollMath.from_ratio(drag_ratio, total_rows, data_height)
      {:ok, put_in(state.scroll.offset, target_scroll), [:render_update]}
    else
      {:ok, state}
    end
  end

  def handle_mouse_drag(state, _x, _y) when state.drag.dragging_scrollbar == false, do: {:noreply, state}

  def handle_mouse_drag(state, x, y) do
    case determine_click_region(state, x, y) do
      :scrollbar -> drag_scrollbar_to(state, x, y)
      _ -> {:ok, put_in(state.drag.dragging_scrollbar, false), [:render_update]}
    end
  end

  def handle_mouse_release(state, _x, _y) do
    {:ok, put_in(state.drag.dragging_scrollbar, false), [:render_update]}
  end

  def handle_mouse_move(state, x, y) do
    region = determine_click_region(state, x, y)
    hovering_scrollbar = region == :scrollbar

    if hovering_scrollbar != state.drag.hovering_scrollbar do
      {:ok, put_in(state.drag.hovering_scrollbar, hovering_scrollbar), [:render_update]}
    else
      {:noreply, state}
    end
  end

  def handle_header_click(state, x) do
    col_index = Columns.calculate_column_from_x(state, x)

    if col_index < length(state.columns) do
      column = Enum.at(Columns.get_ordered_columns(state), col_index)

      if state.callbacks.on_header_select, do: state.callbacks.on_header_select.(column.key)

      if state.sortable && column.sortable do
        Sorting.apply_sort(
          state,
          column,
          col_index,
          &Sorting.trigger_sort/1
        )
      else
        {:ok, %{state | cursor_col: col_index}}
      end
    else
      {:noreply, state}
    end
  end

  def trigger_layout_change(state) do
    if state.callbacks.on_layout_change do
      col_widths = Columns.get_column_widths(state, state.width)
      col_order = Columns.get_col_order_list(state)
      state.callbacks.on_layout_change.(%{col_widths: col_widths, col_order: col_order})
    end
  end
end
