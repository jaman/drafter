defmodule Drafter.WidgetHierarchy.Mouse do
  @moduledoc false

  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetHierarchy.EventRouter
  alias Drafter.WidgetHierarchy.Focus
  alias Drafter.WidgetHierarchy.HitTest
  alias Drafter.WidgetHierarchy.Scroll

  def handle_mouse_event(hierarchy, mouse_event) do
    case {mouse_event.type, hierarchy.drag_capture_widget} do
      {:drag, capture_id} when capture_id != nil ->
        relative_event = make_relative_mouse_event(hierarchy, capture_id, mouse_event)
        EventRouter.handle_event_with_phases(hierarchy, capture_id, {:mouse, relative_event})

      {type, capture_id} when type == :mouse_up and capture_id != nil ->
        relative_event = make_relative_mouse_event(hierarchy, capture_id, mouse_event)

        {new_hierarchy, actions} =
          EventRouter.handle_event_with_phases(hierarchy, capture_id, {:mouse, relative_event})

        {%{new_hierarchy | drag_capture_widget: nil}, actions}

      _ ->
        handle_mouse_event_normal(hierarchy, mouse_event)
    end
  end

  def handle_mouse_event_normal(hierarchy, mouse_event) do
    target_widget = HitTest.find_widget_at(hierarchy, mouse_event.x, mouse_event.y)

    hierarchy = update_hover_state(hierarchy, target_widget)

    case {mouse_event.type, target_widget} do
      {:scroll, nil} ->
        dispatch_to_scroll_container(hierarchy, mouse_event)

      {_, nil} ->
        {hierarchy, []}

      {:move, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        EventRouter.handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_up, widget_id} ->
        handle_mouse_up(hierarchy, widget_id, mouse_event)

      {:drag, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)

        {new_hierarchy, actions} =
          EventRouter.handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

        widget_state = WidgetHierarchy.get_widget_state(new_hierarchy, widget_id)
        {maybe_start_drag_capture(new_hierarchy, widget_id, widget_state), actions}

      {:scroll, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        EventRouter.handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_down, widget_id} ->
        handle_mouse_down(hierarchy, widget_id, mouse_event)

      {_, _widget_id} ->
        {hierarchy, []}
    end
  end

  def dispatch_to_scroll_container(hierarchy, mouse_event) do
    case Scroll.find_scroll_container_at(hierarchy, mouse_event.x, mouse_event.y) do
      nil ->
        {hierarchy, []}

      scroll_id ->
        EventRouter.handle_event_with_phases(hierarchy, scroll_id, {:mouse, mouse_event})
    end
  end

  def handle_mouse_up(hierarchy, widget_id, mouse_event) do
    if :ctrl in Map.get(mouse_event, :mods, []) do
      {Scroll.toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y), []}
    else
      hierarchy = Scroll.clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
      hierarchy = Focus.focus_widget(hierarchy, widget_id)
      relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
      EventRouter.handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
    end
  end

  def handle_mouse_down(hierarchy, widget_id, mouse_event) do
    if :ctrl in Map.get(mouse_event, :mods, []) do
      {Scroll.toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y), []}
    else
      hierarchy = Scroll.clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
      hierarchy = Focus.focus_widget(hierarchy, widget_id)
      relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)

      {new_hierarchy, actions} =
        EventRouter.handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      widget_state = WidgetHierarchy.get_widget_state(new_hierarchy, widget_id)
      {maybe_start_drag_capture(new_hierarchy, widget_id, widget_state), actions}
    end
  end

  @doc """
  Route later drag events to the widget that started the gesture, if it started one.

  Capture is set when `widget_state` reports a gesture in progress, and cleared
  otherwise. The gesture flags are read both as flat fields and from a `:drag`
  map, whichever shape the widget uses.
  """
  def maybe_start_drag_capture(hierarchy, widget_id, widget_state) do
    if gesture_in_progress?(widget_state) do
      %{hierarchy | drag_capture_widget: widget_id}
    else
      %{hierarchy | drag_capture_widget: nil}
    end
  end

  defp gesture_in_progress?(widget_state) when is_map(widget_state) do
    dragging_fields?(widget_state) or dragging_fields?(Map.get(widget_state, :drag))
  end

  defp gesture_in_progress?(_widget_state), do: false

  defp dragging_fields?(fields) when is_map(fields) do
    Map.get(fields, :dragging_scrollbar, false) ||
      Map.get(fields, :dragging, false) ||
      Map.get(fields, :_resize_col) != nil ||
      Map.get(fields, :resize_col) != nil ||
      Map.get(fields, :_reorder_col) != nil ||
      Map.get(fields, :reorder_col) != nil
  end

  defp dragging_fields?(_fields), do: false

  def make_relative_mouse_event(hierarchy, widget_id, mouse_event) do
    case Map.get(hierarchy.widget_rects, widget_id) do
      nil ->
        mouse_event

      virtual_rect ->
        {screen_x, screen_y} = widget_screen_position(hierarchy, widget_id, virtual_rect)

        %{
          mouse_event
          | x: mouse_event.x - screen_x,
            y: mouse_event.y - screen_y
        }
    end
  end

  def widget_screen_position(hierarchy, widget_id, virtual_rect) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil ->
        {virtual_rect.x, virtual_rect.y}

      scroll_parent_id ->
        scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)
        scroll_y = if scroll_state, do: Map.get(scroll_state, :scroll_offset_y, 0), else: 0
        {virtual_rect.x, virtual_rect.y - scroll_y}
    end
  end

  def update_hover_state(hierarchy, target_widget) do
    prev_hover = hierarchy.hover_widget

    cond do
      prev_hover == target_widget ->
        hierarchy

      prev_hover != nil and target_widget != prev_hover ->
        {h1, _} = EventRouter.handle_widget_event(hierarchy, prev_hover, :unhover)
        send_hover_if_target(%{h1 | hover_widget: target_widget}, target_widget)

      prev_hover == nil and target_widget != nil ->
        {h1, _} = EventRouter.handle_widget_event(hierarchy, target_widget, :hover)
        %{h1 | hover_widget: target_widget}

      true ->
        hierarchy
    end
  end

  def send_hover_if_target(hierarchy, nil), do: hierarchy

  def send_hover_if_target(hierarchy, target_widget) do
    {h, _} = EventRouter.handle_widget_event(hierarchy, target_widget, :hover)
    h
  end
end
