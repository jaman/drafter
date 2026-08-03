defmodule Drafter.WidgetHierarchy.Focus do
  @moduledoc false

  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetHierarchy.EventRouter

  @type hierarchy :: WidgetHierarchy.t()
  @type widget_id :: WidgetHierarchy.widget_id()
  @type arrow :: :up | :down | :left | :right
  @type candidate :: {widget_id(), map(), %{x: integer(), y: integer()}}
  @type result :: {hierarchy(), list()}

  @spec focus_widget(WidgetHierarchy.t(), WidgetHierarchy.widget_id()) :: WidgetHierarchy.t()
  def focus_widget(hierarchy, widget_id) do
    focus_widget(hierarchy, widget_id, :down)
  end

  @spec focus_widget(WidgetHierarchy.t(), WidgetHierarchy.widget_id(), :up | :down) ::
          WidgetHierarchy.t()
  def focus_widget(hierarchy, widget_id, direction) do
    if Map.has_key?(hierarchy.widgets, widget_id) and hierarchy.focused_widget != widget_id do
      updated_hierarchy =
        if hierarchy.focused_widget do
          {h, _} = EventRouter.handle_widget_event(hierarchy, hierarchy.focused_widget, {:blur})
          h
        else
          hierarchy
        end

      {final_hierarchy, _} =
        EventRouter.handle_widget_event(updated_hierarchy, widget_id, {:focus})

      final_hierarchy = scroll_widget_into_view(final_hierarchy, widget_id, direction)

      %{final_hierarchy | focused_widget: widget_id}
    else
      hierarchy
    end
  end

  @doc """
  Scroll a widget's container so the widget is visible.

  Returns the hierarchy unchanged when the widget has no scroll parent. The
  `direction` argument is accepted and ignored; the scroll amount is derived from
  where the widget sits relative to the viewport.
  """
  @spec scroll_widget_into_view(hierarchy(), widget_id(), arrow()) :: hierarchy()
  def scroll_widget_into_view(hierarchy, widget_id, _direction) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil -> hierarchy
      scroll_parent_id -> maybe_scroll_to_widget(hierarchy, widget_id, scroll_parent_id)
    end
  end

  @doc """
  Adjust a scroll container's offset so `widget_id` is inside its viewport.

  Returns the hierarchy unchanged when the container's scroll info, the widget's rect
  or the container's widget state is missing, or when no scrolling is needed.
  """
  @spec maybe_scroll_to_widget(hierarchy(), widget_id(), widget_id()) :: hierarchy()
  def maybe_scroll_to_widget(hierarchy, widget_id, scroll_parent_id) do
    scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
    widget_rect = Map.get(hierarchy.widget_rects, widget_id)
    scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    with true <- not is_nil(scroll_info),
         true <- not is_nil(widget_rect),
         true <- not is_nil(scroll_state) do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

      new_scroll_y =
        calculate_visible_scroll_y(widget_rect, viewport, scroll_y, scroll_info.content_height)

      apply_scroll_y(hierarchy, scroll_parent_id, scroll_y, new_scroll_y)
    else
      _ -> hierarchy
    end
  end

  @doc """
  The vertical scroll offset that brings `widget_rect` into `viewport`.

  Scrolls the minimum distance: aligns the widget's top with the viewport's when it
  is above, its bottom with the viewport's when it is below, and returns `scroll_y`
  unchanged when it is already visible. The result is clamped to
  `0..max(0, content_height - viewport.height)`.
  """
  @spec calculate_visible_scroll_y(map(), map(), integer(), integer()) :: non_neg_integer()
  def calculate_visible_scroll_y(widget_rect, viewport, scroll_y, content_height) do
    widget_top = widget_rect.y
    widget_bottom = widget_rect.y + widget_rect.height
    viewport_top = viewport.y + scroll_y
    viewport_bottom = viewport_top + viewport.height

    raw =
      cond do
        widget_top < viewport_top -> widget_top - viewport.y
        widget_bottom > viewport_bottom -> widget_bottom - viewport.y - viewport.height
        true -> scroll_y
      end

    max_scroll = max(0, content_height - viewport.height)
    raw |> max(0) |> min(max_scroll)
  end

  @doc """
  Write a new `:scroll_offset_y` to a container, or do nothing if it has not changed.
  """
  @spec apply_scroll_y(hierarchy(), widget_id(), integer(), integer()) :: hierarchy()
  def apply_scroll_y(hierarchy, scroll_parent_id, scroll_y, new_scroll_y) do
    if new_scroll_y != scroll_y do
      WidgetHierarchy.update_widget(hierarchy, scroll_parent_id, %{scroll_offset_y: new_scroll_y})
    else
      hierarchy
    end
  end

  @spec cycle_focus(WidgetHierarchy.t()) :: WidgetHierarchy.t()
  def cycle_focus(hierarchy) do
    focusable_widgets = get_focusable_widgets(hierarchy)

    case focusable_widgets do
      [] ->
        hierarchy

      [single_widget] ->
        focus_widget(hierarchy, single_widget, :down)

      widgets ->
        current_index =
          case hierarchy.focused_widget do
            nil -> -1
            focused -> Enum.find_index(widgets, &(&1 == focused)) || -1
          end

        next_index = rem(current_index + 1, length(widgets))
        next_widget = Enum.at(widgets, next_index)
        focus_widget(hierarchy, next_widget, :down)
    end
  end

  @spec cycle_focus_reverse(WidgetHierarchy.t()) :: WidgetHierarchy.t()
  def cycle_focus_reverse(hierarchy) do
    focusable_widgets = get_focusable_widgets(hierarchy)

    case focusable_widgets do
      [] ->
        hierarchy

      [single_widget] ->
        focus_widget(hierarchy, single_widget, :up)

      widgets ->
        current_index =
          case hierarchy.focused_widget do
            nil -> 0
            focused -> Enum.find_index(widgets, &(&1 == focused)) || 0
          end

        prev_index =
          if current_index == 0 do
            length(widgets) - 1
          else
            current_index - 1
          end

        prev_widget = Enum.at(widgets, prev_index)
        focus_widget(hierarchy, prev_widget, :up)
    end
  end

  @doc """
  Route an arrow key, offering it to the focused widget before moving focus.

  The focused widget sees it first. A widget that traps arrows keeps it; otherwise it
  counts as handled only if it consumed the event or changed its own state. When it
  goes unhandled and more than one widget is focusable, focus moves spatially in
  `direction`; with one or none, the event goes to the focused widget anyway.
  """
  @spec try_arrow_navigation(hierarchy(), term(), arrow()) :: result()
  def try_arrow_navigation(hierarchy, event, direction) do
    case try_dispatch_arrow_to_widget(hierarchy, event) do
      {:handled, result} ->
        result

      :not_handled ->
        focusable_widgets = get_focusable_widgets(hierarchy)

        if length(focusable_widgets) <= 1 do
          EventRouter.dispatch_to_focused(hierarchy, event)
        else
          arrow_navigate_with_focus(hierarchy, event, direction, focusable_widgets)
        end
    end
  end

  @doc """
  Offer an arrow event to the focused widget.

  Returns `{:handled, {hierarchy, actions}}` when the widget claimed it, or
  `:not_handled` — including when nothing is focused.
  """
  @spec try_dispatch_arrow_to_widget(hierarchy(), term()) :: {:handled, result()} | :not_handled
  def try_dispatch_arrow_to_widget(hierarchy, event) do
    with widget_id when not is_nil(widget_id) <- hierarchy.focused_widget,
         %{} = widget_info <- Map.get(hierarchy.widgets, widget_id) do
      result = EventRouter.dispatch_widget_event(hierarchy, widget_id, widget_info, event)
      classify_arrow_result(result, hierarchy, widget_info)
    else
      _ -> :not_handled
    end
  end

  defp classify_arrow_result(result, hierarchy, widget_info) do
    if widget_traps_arrows?(widget_info),
      do: {:handled, result},
      else: classify_untrapped(result, hierarchy)
  end

  defp classify_untrapped({new_hierarchy, []} = result, hierarchy) do
    if new_hierarchy.event_consumed or new_hierarchy.widgets != hierarchy.widgets do
      {:handled, result}
    else
      :not_handled
    end
  end

  defp classify_untrapped(result, _hierarchy), do: {:handled, result}

  defp widget_traps_arrows?(%{state: state}) when is_map(state) do
    Map.get(state, :focused, false) and Map.get(state, :trap_focus, false) in [true, :arrows]
  end

  defp widget_traps_arrows?(_), do: false

  @doc """
  Move focus in `direction`, falling back to dispatching the event.

  With nothing focused, focuses the first focusable widget. With something focused
  but no widget in that direction, the event is dispatched to the focused widget
  instead.
  """
  @spec arrow_navigate_with_focus(hierarchy(), term(), arrow(), [widget_id()]) :: result()
  def arrow_navigate_with_focus(hierarchy, event, direction, focusable_widgets) do
    case hierarchy.focused_widget do
      nil ->
        {focus_widget(hierarchy, hd(focusable_widgets), :down), []}

      focused_id ->
        case navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction) do
          {^hierarchy, []} -> EventRouter.dispatch_to_focused(hierarchy, event)
          result -> result
        end
    end
  end

  @doc """
  Move focus from `focused_id` to the nearest widget in `direction`.

  Returns `{hierarchy, []}` unchanged when the focused widget has no rect or nothing
  lies that way.
  """
  @spec navigate_by_arrow(hierarchy(), widget_id(), [widget_id()], arrow()) :: result()
  def navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction) do
    case Map.get(hierarchy.widget_rects, focused_id) do
      nil ->
        {hierarchy, []}

      focused_rect ->
        navigate_by_arrow_from_rect(
          hierarchy,
          focused_id,
          focusable_widgets,
          direction,
          focused_rect
        )
    end
  end

  @doc """
  As `navigate_by_arrow/4`, with the focused widget's rect already resolved.

  Focusable widgets that have no rect are skipped.
  """
  @spec navigate_by_arrow_from_rect(
          hierarchy(),
          widget_id(),
          [widget_id()],
          arrow(),
          map()
        ) :: result()
  def navigate_by_arrow_from_rect(
        hierarchy,
        focused_id,
        focusable_widgets,
        direction,
        focused_rect
      ) do
    focused_point = %{x: focused_rect.x, y: focused_rect.y}

    candidates =
      focusable_widgets
      |> Enum.reject(&(&1 == focused_id))
      |> Enum.map(fn widget_id ->
        rect = Map.get(hierarchy.widget_rects, widget_id)
        if rect, do: {widget_id, rect, %{x: rect.x, y: rect.y}}, else: nil
      end)
      |> Enum.reject(&is_nil/1)

    target = find_arrow_target(candidates, focused_point, direction)
    focus_arrow_target(hierarchy, target)
  end

  @doc """
  The nearest candidate strictly in `direction` from `focused_point`, or `nil`.

  Candidates are compared by their top-left corners: first by distance along the
  axis of travel, then by distance across it. Anything level with the focused point
  on that axis is excluded, so a purely horizontal neighbour is never an `:up` or
  `:down` target.
  """
  @spec find_arrow_target([candidate()], %{x: integer(), y: integer()}, arrow()) ::
          candidate() | nil
  def find_arrow_target(candidates, focused_point, :up) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.y < focused_point.y end)
    |> Enum.min_by(
      fn {_, _, pt} -> {focused_point.y - pt.y, abs(pt.x - focused_point.x)} end,
      fn -> nil end
    )
  end

  def find_arrow_target(candidates, focused_point, :down) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.y > focused_point.y end)
    |> Enum.min_by(
      fn {_, _, pt} -> {pt.y - focused_point.y, abs(pt.x - focused_point.x)} end,
      fn -> nil end
    )
  end

  def find_arrow_target(candidates, focused_point, :left) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.x < focused_point.x end)
    |> Enum.min_by(
      fn {_, _, pt} -> {focused_point.x - pt.x, abs(pt.y - focused_point.y)} end,
      fn -> nil end
    )
  end

  def find_arrow_target(candidates, focused_point, :right) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.x > focused_point.x end)
    |> Enum.min_by(
      fn {_, _, pt} -> {pt.x - focused_point.x, abs(pt.y - focused_point.y)} end,
      fn -> nil end
    )
  end

  @doc "Focus an arrow-navigation target, or leave the hierarchy alone when there is none."
  @spec focus_arrow_target(hierarchy(), candidate() | nil) :: result()
  def focus_arrow_target(hierarchy, nil), do: {hierarchy, []}

  def focus_arrow_target(hierarchy, {widget_id, _rect, _pt}),
    do: {focus_widget(hierarchy, widget_id, :down), []}

  @doc """
  Every focusable widget id, ordered top-to-bottom then left-to-right.

  A widget qualifies when its module declares the `:focusable` capability and its
  live state is neither `:disabled` nor explicitly `focusable: false`, it is not
  hidden, and no collapsed ancestor encloses it. This is the order `cycle_focus/1`
  walks.
  """
  @spec get_focusable_widgets(hierarchy()) :: [widget_id()]
  def get_focusable_widgets(hierarchy) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      live_state = WidgetHierarchy.live_widget_state(widget_info)

      focusable_widget?(widget_info.module) and
        not disabled?(live_state) and
        not instance_unfocusable?(live_state) and
        not MapSet.member?(hidden, widget_id) and
        ancestors_expanded?(hierarchy, widget_info.parent)
    end)
    |> Enum.sort_by(fn {widget_id, _widget_info} ->
      rect = Map.get(hierarchy.widget_rects, widget_id, %{y: 0, x: 0})
      {Map.get(rect, :y, 0), Map.get(rect, :x, 0)}
    end)
    |> Enum.map(fn {widget_id, _widget_info} -> widget_id end)
  end

  @doc """
  Whether every ancestor from `ancestor_id` upwards is expanded.

  An ancestor is collapsed only when its live state carries `expanded: false`; a
  missing ancestor or a state with no `:expanded` key counts as expanded.
  """
  @spec ancestors_expanded?(hierarchy(), widget_id() | nil) :: boolean()
  def ancestors_expanded?(_hierarchy, nil), do: true

  def ancestors_expanded?(hierarchy, ancestor_id) do
    case Map.get(hierarchy.widgets, ancestor_id) do
      nil ->
        true

      ancestor ->
        ancestor_state = WidgetHierarchy.live_widget_state(ancestor)

        if Map.get(ancestor_state, :expanded) == false do
          false
        else
          ancestors_expanded?(hierarchy, ancestor.parent)
        end
    end
  end

  defp disabled?(state) do
    Map.get(state, :disabled, false)
  end

  defp instance_unfocusable?(state) do
    Map.get(state, :focusable) == false
  end

  defp focusable_widget?(module) do
    function_exported?(module, :__widget_capabilities__, 0) and
      Map.get(module.__widget_capabilities__(), :focusable, false)
  end
end
