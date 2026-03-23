defmodule Drafter.WidgetHierarchy do
  @moduledoc false

  alias Drafter.WidgetServer

  defstruct [
    :root,
    :widgets,
    :focused_widget,
    :widget_rects,
    :hover_widget,
    :widget_counter,
    :scroll_containers,
    :widget_scroll_parents,
    :drag_capture_widget,
    :preferred_sizes,
    hidden_widgets: MapSet.new()
  ]

  @type widget_id :: atom() | String.t()
  @type rect :: %{x: integer(), y: integer(), width: integer(), height: integer()}

  @type scroll_info :: %{
          viewport_rect: rect(),
          content_height: integer(),
          content_width: integer(),
          click_to_scroll: boolean(),
          scroll_exceptions: MapSet.t()
        }

  @type t :: %__MODULE__{
          root: widget_id() | nil,
          widgets: %{
            widget_id() => %{
              module: module(),
              state: map(),
              parent: widget_id() | nil,
              children: [widget_id()],
              pid: pid() | nil,
              order: integer()
            }
          },
          focused_widget: widget_id() | nil,
          widget_rects: %{widget_id() => rect()},
          hover_widget: widget_id() | nil,
          widget_counter: integer(),
          scroll_containers: %{widget_id() => scroll_info()},
          widget_scroll_parents: %{widget_id() => widget_id()}
        }

  @doc "Create a new widget hierarchy"
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %__MODULE__{
      root: nil,
      widgets: %{},
      focused_widget: nil,
      widget_rects: %{},
      hover_widget: nil,
      widget_counter: 0,
      scroll_containers: %{},
      widget_scroll_parents: %{},
      drag_capture_widget: nil,
      preferred_sizes: %{}
    }
  end

  @doc "Update widget preferred size"
  @spec update_preferred_size(t(), widget_id(), integer()) :: t()
  def update_preferred_size(hierarchy, widget_id, size) do
    new_sizes = Map.put(hierarchy.preferred_sizes, widget_id, size)
    %{hierarchy | preferred_sizes: new_sizes}
  end

  @doc "Get widget preferred size"
  @spec get_preferred_size(t(), widget_id()) :: integer() | nil
  def get_preferred_size(hierarchy, widget_id) do
    Map.get(hierarchy.preferred_sizes, widget_id)
  end

  defp mark_widget_rendered(widget_id) do
    rendered = Process.get(:rendered_widget_ids, MapSet.new())
    Process.put(:rendered_widget_ids, MapSet.put(rendered, widget_id))
  end

  @doc "Add a widget to the hierarchy"
  @spec add_widget(t(), widget_id(), module(), map(), widget_id() | nil, rect()) :: t()
  def add_widget(
        hierarchy,
        widget_id,
        widget_module,
        mount_props,
        parent_id \\ nil,
        rect \\ %{x: 0, y: 0, width: 0, height: 0}
      ) do
    mark_widget_rendered(widget_id)
    Code.ensure_loaded(widget_module)

    {:ok, pid} =
      WidgetServer.start_link(
        id: widget_id,
        module: widget_module,
        props: mount_props,
        rect: rect
      )

    widget_state = WidgetServer.get_state(pid)
    order = hierarchy.widget_counter

    widget_info = %{
      module: widget_module,
      state: widget_state,
      parent: parent_id,
      children: [],
      pid: pid,
      order: order
    }

    new_widgets = Map.put(hierarchy.widgets, widget_id, widget_info)

    new_rects = Map.put(hierarchy.widget_rects, widget_id, rect)

    new_widgets =
      if parent_id do
        case Map.get(new_widgets, parent_id) do
          nil ->
            new_widgets

          parent_info ->
            updated_parent = %{parent_info | children: [widget_id | parent_info.children]}
            Map.put(new_widgets, parent_id, updated_parent)
        end
      else
        new_widgets
      end

    new_root = if parent_id == nil, do: widget_id, else: hierarchy.root

    %{
      hierarchy
      | widgets: new_widgets,
        root: new_root,
        widget_rects: new_rects,
        widget_counter: order + 1
    }
  end

  @spec stop_all_servers(t() | nil) :: :ok
  def stop_all_servers(nil), do: :ok

  def stop_all_servers(hierarchy) do
    hierarchy.widgets
    |> Map.values()
    |> Enum.each(fn
      %{pid: pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          try do
            WidgetServer.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      _ -> :ok
    end)

    :ok
  end

  @doc "Remove a widget from the hierarchy"
  @spec remove_widget(t(), widget_id()) :: t()
  def remove_widget(hierarchy, widget_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      widget_info ->
        if widget_info.pid do
          WidgetServer.stop(widget_info.pid)
        end

        Drafter.WidgetStripCache.delete(widget_id)

        new_widgets = detach_from_parent(hierarchy.widgets, widget_id, widget_info.parent)

        new_widgets =
          Enum.reduce(widget_info.children, new_widgets, fn child_id, acc_widgets ->
            child_hierarchy = %{hierarchy | widgets: acc_widgets}
            updated_hierarchy = remove_widget(child_hierarchy, child_id)
            updated_hierarchy.widgets
          end)

        new_widgets = Map.delete(new_widgets, widget_id)
        new_rects = Map.delete(hierarchy.widget_rects, widget_id)

        new_root = if hierarchy.root == widget_id, do: nil, else: hierarchy.root

        new_focused =
          if hierarchy.focused_widget == widget_id, do: nil, else: hierarchy.focused_widget

        %{
          hierarchy
          | widgets: new_widgets,
            root: new_root,
            widget_rects: new_rects,
            focused_widget: new_focused
        }
    end
  end

  defp detach_from_parent(widgets, _widget_id, nil), do: widgets

  defp detach_from_parent(widgets, widget_id, parent_id) do
    case Map.get(widgets, parent_id) do
      nil -> widgets
      parent_info ->
        updated_children = List.delete(parent_info.children, widget_id)
        Map.put(widgets, parent_id, %{parent_info | children: updated_children})
    end
  end

  @doc "Update widget with new props"
  @spec update_widget(t(), widget_id(), map()) :: t()
  @spec update_widget_parent(t(), widget_id(), widget_id() | nil) :: t()
  def update_widget_parent(hierarchy, widget_id, parent_id) do
    update_widget_info(hierarchy, widget_id, &%{&1 | parent: parent_id})
  end

  def update_widget(hierarchy, widget_id, new_props) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      widget_info ->
        apply_widget_update(hierarchy, widget_id, widget_info, new_props)
    end
  end

  defp apply_widget_update(hierarchy, _widget_id, %{pid: pid} = _widget_info, new_props) when is_pid(pid) do
    WidgetServer.update_props(pid, new_props)
    hierarchy
  end

  defp apply_widget_update(hierarchy, widget_id, widget_info, new_props) do
    new_state =
      if function_exported?(widget_info.module, :update, 2) do
        widget_info.module.update(new_props, widget_info.state)
      else
        Map.merge(widget_info.state, new_props)
      end

    updated_widget = %{widget_info | state: new_state}
    %{hierarchy | widgets: Map.put(hierarchy.widgets, widget_id, updated_widget)}
  end

  @doc "Get widget info by ID"
  @spec get_widget_info(t(), widget_id()) :: map() | nil
  def get_widget_info(hierarchy, widget_id) do
    Map.get(hierarchy.widgets, widget_id)
  end

  @doc "Get parent widget ID"
  @spec get_parent(t(), widget_id()) :: widget_id() | nil
  def get_parent(hierarchy, widget_id) do
    case get_widget_info(hierarchy, widget_id) do
      nil -> nil
      widget_info -> widget_info.parent_id
    end
  end

  @doc "Get children widget IDs"
  @spec get_children(t(), widget_id()) :: [widget_id()]
  def get_children(hierarchy, parent_id) do
    hierarchy.widgets
    |> Enum.filter(fn {_id, widget_info} ->
      widget_info.parent_id == parent_id
    end)
    |> Enum.map(fn {id, _widget_info} -> id end)
  end

  @doc "Update widget state directly"
  @spec update_widget_state(t(), widget_id(), map()) :: t()
  def update_widget_state(hierarchy, widget_id, new_state) do
    update_widget_info(hierarchy, widget_id, &%{&1 | state: new_state})
  end

  @doc "Update widget rectangle"
  @spec update_widget_rect(t(), widget_id(), rect()) :: t()
  def update_widget_rect(hierarchy, widget_id, rect) do
    mark_widget_rendered(widget_id)

    case Map.get(hierarchy.widgets, widget_id) do
      %{pid: pid} when is_pid(pid) ->
        WidgetServer.update_rect(pid, rect)

      _ ->
        :ok
    end

    new_rects = Map.put(hierarchy.widget_rects, widget_id, rect)
    %{hierarchy | widget_rects: new_rects}
  end

  @doc "Set focus to a widget"
  @spec focus_widget(t(), widget_id()) :: t()
  def focus_widget(hierarchy, widget_id) do
    focus_widget(hierarchy, widget_id, :down)
  end

  @spec focus_widget(t(), widget_id(), :up | :down) :: t()
  def focus_widget(hierarchy, widget_id, direction) do
    if Map.has_key?(hierarchy.widgets, widget_id) and hierarchy.focused_widget != widget_id do
      updated_hierarchy =
        if hierarchy.focused_widget do
          {h, _} = handle_widget_event(hierarchy, hierarchy.focused_widget, {:blur})
          h
        else
          hierarchy
        end

      {final_hierarchy, _} = handle_widget_event(updated_hierarchy, widget_id, {:focus})

      final_hierarchy = scroll_widget_into_view(final_hierarchy, widget_id, direction)

      %{final_hierarchy | focused_widget: widget_id}
    else
      hierarchy
    end
  end

  defp scroll_widget_into_view(hierarchy, widget_id, _direction) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil -> hierarchy
      scroll_parent_id -> maybe_scroll_to_widget(hierarchy, widget_id, scroll_parent_id)
    end
  end

  defp maybe_scroll_to_widget(hierarchy, widget_id, scroll_parent_id) do
    scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
    widget_rect = Map.get(hierarchy.widget_rects, widget_id)
    scroll_state = get_widget_state(hierarchy, scroll_parent_id)

    with true <- not is_nil(scroll_info),
         true <- not is_nil(widget_rect),
         true <- not is_nil(scroll_state) do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)
      new_scroll_y = calculate_visible_scroll_y(widget_rect, viewport, scroll_y, scroll_info.content_height)
      apply_scroll_y(hierarchy, scroll_parent_id, scroll_y, new_scroll_y)
    else
      _ -> hierarchy
    end
  end

  defp calculate_visible_scroll_y(widget_rect, viewport, scroll_y, content_height) do
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

  defp apply_scroll_y(hierarchy, scroll_parent_id, scroll_y, new_scroll_y) do
    if new_scroll_y != scroll_y do
      update_widget(hierarchy, scroll_parent_id, %{scroll_offset_y: new_scroll_y})
    else
      hierarchy
    end
  end

  @doc "Cycle focus to next focusable widget"
  @spec cycle_focus(t()) :: t()
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

  @doc "Cycle focus to previous focusable widget"
  @spec cycle_focus_reverse(t()) :: t()
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

  @doc "Find widget at coordinates (hit testing)"
  @spec find_widget_at(t(), integer(), integer()) :: widget_id() | nil
  def find_widget_at(hierarchy, x, y) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    candidates =
      hierarchy.widget_rects
      |> Enum.reject(fn {id, _rect} -> MapSet.member?(hidden, id) end)
      |> Enum.map(fn {id, rect} ->
        {id, translate_rect_to_screen(hierarchy, id, rect)}
      end)
      |> Enum.filter(fn {_id, screen_rect} ->
        case screen_rect do
          nil ->
            false

          rect ->
            x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height
        end
      end)
      |> Enum.map(fn {id, rect} ->
        depth = widget_depth(hierarchy, id)
        area = rect.width * rect.height
        {id, rect, depth, area}
      end)

    case candidates do
      [] ->
        nil

      _ ->
        {widget_id, _rect, _depth, _area} =
          candidates
          |> Enum.sort_by(fn {_id, _rect, depth, area} -> {-depth, area} end)
          |> hd()

        widget_id
    end
  end

  defp translate_rect_to_screen(hierarchy, widget_id, virtual_rect) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil -> virtual_rect
      scroll_parent_id -> clip_rect_to_scroll_viewport(hierarchy, scroll_parent_id, virtual_rect)
    end
  end

  defp clip_rect_to_scroll_viewport(hierarchy, scroll_parent_id, virtual_rect) do
    scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
    scroll_state = get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)
      compute_visible_rect(virtual_rect, viewport, scroll_y)
    else
      virtual_rect
    end
  end

  defp compute_visible_rect(virtual_rect, viewport, scroll_y) do
    screen_y = virtual_rect.y - scroll_y
    screen_bottom = screen_y + virtual_rect.height

    if screen_bottom <= viewport.y or screen_y >= viewport.y + viewport.height do
      nil
    else
      visible_top = max(screen_y, viewport.y)
      visible_bottom = min(screen_bottom, viewport.y + viewport.height)
      %{x: virtual_rect.x, y: visible_top, width: virtual_rect.width, height: visible_bottom - visible_top}
    end
  end

  defp widget_depth(hierarchy, id) do
    do_depth(hierarchy, id, 0)
  end

  defp do_depth(_hierarchy, nil, acc), do: acc

  defp do_depth(hierarchy, id, acc) do
    case Map.get(hierarchy.widgets, id) do
      nil -> acc
      %{parent: parent} -> do_depth(hierarchy, parent, acc + 1)
    end
  end

  @doc "Handle event with proper bubbling"
  @spec handle_event(t(), term()) :: {t(), [term()]}
  def handle_event(hierarchy, {:mouse, mouse_event}), do: handle_mouse_event(hierarchy, mouse_event)
  def handle_event(hierarchy, event), do: handle_key_event(hierarchy, event)

  defp handle_key_event(hierarchy, {:key, :tab}), do: {cycle_focus(hierarchy), []}
  defp handle_key_event(hierarchy, {:key, :tab, _}), do: {cycle_focus_reverse(hierarchy), []}
  defp handle_key_event(hierarchy, {:key, ?\t}), do: {cycle_focus(hierarchy), []}

  defp handle_key_event(hierarchy, {:key, ?\t, mods}) when is_list(mods) do
    if :shift in mods, do: {cycle_focus_reverse(hierarchy), []}, else: {cycle_focus(hierarchy), []}
  end

  defp handle_key_event(hierarchy, {:key, dir} = event) when dir in [:left, :right, :up, :down] do
    try_arrow_navigation(hierarchy, event, dir)
  end

  defp handle_key_event(hierarchy, {:key, dir, _} = event) when dir in [:left, :right, :up, :down] do
    try_arrow_navigation(hierarchy, event, dir)
  end

  defp handle_key_event(hierarchy, event), do: dispatch_to_focused_or_ignore(hierarchy, event)

  defp dispatch_to_focused_or_ignore(hierarchy, {:key, _} = event), do: dispatch_to_focused(hierarchy, event)
  defp dispatch_to_focused_or_ignore(hierarchy, {:key, _, _} = event), do: dispatch_to_focused(hierarchy, event)
  defp dispatch_to_focused_or_ignore(hierarchy, {:char, _} = event), do: dispatch_to_focused(hierarchy, event)
  defp dispatch_to_focused_or_ignore(hierarchy, _), do: {hierarchy, []}

  def handle_event_consumed(hierarchy, event) do
    hierarchy = sync_focused_pid_state(hierarchy)
    {new_hierarchy, actions} = handle_event(hierarchy, event)
    consumed = actions != [] or
               new_hierarchy.focused_widget != hierarchy.focused_widget or
               :erlang.phash2(new_hierarchy.widgets) != :erlang.phash2(hierarchy.widgets)
    {new_hierarchy, actions, consumed}
  end

  defp sync_focused_pid_state(hierarchy) do
    case hierarchy.focused_widget && Map.get(hierarchy.widgets, hierarchy.focused_widget) do
      %{pid: pid} = info when not is_nil(pid) ->
        put_widget(hierarchy, hierarchy.focused_widget, %{info | state: WidgetServer.get_state(pid)})

      _ ->
        hierarchy
    end
  end

  defp put_widget(hierarchy, widget_id, widget_info) do
    %{hierarchy | widgets: Map.put(hierarchy.widgets, widget_id, widget_info)}
  end

  defp update_widget_info(hierarchy, widget_id, fun) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> hierarchy
      info -> put_widget(hierarchy, widget_id, fun.(info))
    end
  end

  defp dispatch_to_focused(hierarchy, semantic_event) do
    case hierarchy.focused_widget do
      nil ->
        {hierarchy, []}

      widget_id ->
        handle_event_with_phases(hierarchy, widget_id, semantic_event)
    end
  end

  defp handle_event_with_phases(hierarchy, target_id, tuple_event) do
    event_object = Drafter.Event.from_tuple(tuple_event)

    event_object = %{
      event_object
      | target: target_id,
        timestamp: System.monotonic_time(:millisecond)
    }

    path = build_ancestor_path(hierarchy, target_id)

    {hierarchy_after_capture, event_after_capture, capture_actions} =
      dispatch_capture_phase(hierarchy, event_object, path)

    if event_after_capture.propagation_stopped do
      {hierarchy_after_capture, capture_actions}
    else
      event_after_capture = %{event_after_capture | phase: :target, current_target: target_id}

      {hierarchy_after_target, target_actions} =
        handle_widget_event(
          hierarchy_after_capture,
          target_id,
          Drafter.Event.to_tuple(event_after_capture)
        )

      {hierarchy_after_target, capture_actions ++ target_actions}
    end
  end

  defp try_arrow_navigation(hierarchy, event, direction) do
    focusable_widgets = get_focusable_widgets(hierarchy)

    if length(focusable_widgets) <= 1 do
      dispatch_to_focused(hierarchy, event)
    else
      arrow_navigate_with_focus(hierarchy, event, direction, focusable_widgets)
    end
  end

  defp arrow_navigate_with_focus(hierarchy, event, direction, focusable_widgets) do
    case hierarchy.focused_widget do
      nil ->
        {focus_widget(hierarchy, hd(focusable_widgets), :down), []}

      focused_id ->
        case dispatch_to_focused(hierarchy, event) do
          {^hierarchy, []} -> navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction)
          result -> result
        end
    end
  end

  defp navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction) do
    case Map.get(hierarchy.widget_rects, focused_id) do
      nil -> {hierarchy, []}
      focused_rect -> navigate_by_arrow_from_rect(hierarchy, focused_id, focusable_widgets, direction, focused_rect)
    end
  end

  defp navigate_by_arrow_from_rect(hierarchy, focused_id, focusable_widgets, direction, focused_rect) do
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

  defp find_arrow_target(candidates, focused_point, :up) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.y < focused_point.y end)
    |> Enum.min_by(fn {_, _, pt} -> {focused_point.y - pt.y, abs(pt.x - focused_point.x)} end, fn -> nil end)
  end

  defp find_arrow_target(candidates, focused_point, :down) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.y > focused_point.y end)
    |> Enum.min_by(fn {_, _, pt} -> {pt.y - focused_point.y, abs(pt.x - focused_point.x)} end, fn -> nil end)
  end

  defp find_arrow_target(candidates, focused_point, :left) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.x < focused_point.x end)
    |> Enum.min_by(fn {_, _, pt} -> {focused_point.x - pt.x, abs(pt.y - focused_point.y)} end, fn -> nil end)
  end

  defp find_arrow_target(candidates, focused_point, :right) do
    candidates
    |> Enum.filter(fn {_, _, pt} -> pt.x > focused_point.x end)
    |> Enum.min_by(fn {_, _, pt} -> {pt.x - focused_point.x, abs(pt.y - focused_point.y)} end, fn -> nil end)
  end

  defp focus_arrow_target(hierarchy, nil), do: {hierarchy, []}
  defp focus_arrow_target(hierarchy, {widget_id, _rect, _pt}), do: {focus_widget(hierarchy, widget_id, :down), []}

  defp handle_mouse_event(hierarchy, mouse_event) do
    case {mouse_event.type, hierarchy.drag_capture_widget} do
      {:drag, capture_id} when capture_id != nil ->
        relative_event = make_relative_mouse_event(hierarchy, capture_id, mouse_event)
        handle_event_with_phases(hierarchy, capture_id, {:mouse, relative_event})

      {type, capture_id} when type == :mouse_up and capture_id != nil ->
        relative_event = make_relative_mouse_event(hierarchy, capture_id, mouse_event)

        {new_hierarchy, actions} =
          handle_event_with_phases(hierarchy, capture_id, {:mouse, relative_event})

        {%{new_hierarchy | drag_capture_widget: nil}, actions}

      _ ->
        handle_mouse_event_normal(hierarchy, mouse_event)
    end
  end

  defp handle_mouse_event_normal(hierarchy, mouse_event) do
    target_widget = find_widget_at(hierarchy, mouse_event.x, mouse_event.y)

    hierarchy = update_hover_state(hierarchy, target_widget)

    case {mouse_event.type, target_widget} do
      {:scroll, nil} ->
        dispatch_to_scroll_container(hierarchy, mouse_event)

      {_, nil} ->
        {hierarchy, []}

      {:move, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_up, widget_id} ->
        handle_mouse_up(hierarchy, widget_id, mouse_event)

      {:drag, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        {new_hierarchy, actions} = handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
        widget_state = get_widget_state(new_hierarchy, widget_id)
        {maybe_start_drag_capture(new_hierarchy, widget_id, widget_state), actions}

      {:scroll, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_down, widget_id} ->
        handle_mouse_down(hierarchy, widget_id, mouse_event)

      {_, _widget_id} ->
        {hierarchy, []}
    end
  end

  defp dispatch_to_scroll_container(hierarchy, mouse_event) do
    case find_scroll_container_at(hierarchy, mouse_event.x, mouse_event.y) do
      nil -> {hierarchy, []}
      scroll_id -> handle_event_with_phases(hierarchy, scroll_id, {:mouse, mouse_event})
    end
  end

  defp handle_mouse_up(hierarchy, widget_id, mouse_event) do
    if :ctrl in Map.get(mouse_event, :mods, []) do
      {toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y), []}
    else
      hierarchy = clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
      hierarchy = focus_widget(hierarchy, widget_id)
      relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
      handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
    end
  end

  defp handle_mouse_down(hierarchy, widget_id, mouse_event) do
    if :ctrl in Map.get(mouse_event, :mods, []) do
      {toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y), []}
    else
      hierarchy = clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
      hierarchy = focus_widget(hierarchy, widget_id)
      relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
      {new_hierarchy, actions} = handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
      widget_state = get_widget_state(new_hierarchy, widget_id)
      {maybe_start_drag_capture(new_hierarchy, widget_id, widget_state), actions}
    end
  end

  defp toggle_scroll_lock_at(hierarchy, x, y) do
    click_to_scroll_containers =
      Enum.filter(hierarchy.scroll_containers, fn {_id, info} ->
        info.click_to_scroll
      end)

    innermost =
      click_to_scroll_containers
      |> Enum.filter(fn {_id, info} ->
        v = info.viewport_rect
        x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height
      end)
      |> Enum.min_by(fn {_id, info} ->
        info.viewport_rect.width * info.viewport_rect.height
      end, fn -> nil end)

    case innermost do
      nil -> hierarchy
      {scroll_id, _info} -> toggle_scroll_lock(hierarchy, scroll_id)
    end
  end

  defp toggle_scroll_lock(hierarchy, scroll_id) do
    case get_widget_state(hierarchy, scroll_id) do
      nil -> hierarchy
      state -> update_widget_state_in_hierarchy(hierarchy, scroll_id, %{state | scroll_locked: not state.scroll_locked})
    end
  end

  defp clear_scroll_locks_outside(hierarchy, x, y) do
    Enum.reduce(hierarchy.scroll_containers, hierarchy, fn {scroll_id, info}, h ->
      maybe_clear_scroll_lock(h, scroll_id, info, x, y)
    end)
  end

  defp maybe_clear_scroll_lock(h, _scroll_id, %{click_to_scroll: false}, _x, _y), do: h

  defp maybe_clear_scroll_lock(h, scroll_id, info, x, y) do
    v = info.viewport_rect
    outside = not (x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height)
    clear_lock_if_outside(h, scroll_id, outside)
  end

  defp clear_lock_if_outside(h, _scroll_id, false), do: h

  defp clear_lock_if_outside(h, scroll_id, true) do
    case get_widget_state(h, scroll_id) do
      %{scroll_locked: true} = state -> update_widget_state_in_hierarchy(h, scroll_id, %{state | scroll_locked: false})
      _ -> h
    end
  end

  defp update_widget_state_in_hierarchy(hierarchy, widget_id, new_state) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      %{pid: pid} when is_pid(pid) ->
        WidgetServer.set_state(pid, new_state)
        hierarchy

      widget_info ->
        updated = %{widget_info | state: new_state}
        %{hierarchy | widgets: Map.put(hierarchy.widgets, widget_id, updated)}
    end
  end

  defp maybe_start_drag_capture(hierarchy, widget_id, widget_state) do
    if widget_state &&
         (Map.get(widget_state, :dragging_scrollbar, false) ||
            Map.get(widget_state, :dragging, false) ||
            Map.get(widget_state, :_resize_col) != nil ||
            Map.get(widget_state, :_reorder_col) != nil) do
      %{hierarchy | drag_capture_widget: widget_id}
    else
      %{hierarchy | drag_capture_widget: nil}
    end
  end

  defp find_scroll_container_at(hierarchy, x, y) do
    candidates =
      Enum.filter(hierarchy.scroll_containers, fn {_id, info} ->
        v = info.viewport_rect
        x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height
      end)

    resolve_scroll_candidate(hierarchy, candidates)
  end

  defp resolve_scroll_candidate(_hierarchy, []), do: nil
  defp resolve_scroll_candidate(_hierarchy, [{id, %{click_to_scroll: false}}]), do: id

  defp resolve_scroll_candidate(hierarchy, candidates) do
    sorted = Enum.sort_by(candidates, fn {_id, info} -> info.viewport_rect.width * info.viewport_rect.height end)
    Enum.find_value(sorted, &pick_scroll_candidate(hierarchy, candidates, &1))
  end

  defp pick_scroll_candidate(hierarchy, candidates, {id, %{click_to_scroll: false}}) do
    if claimed_by_outer_click_to_scroll?(hierarchy, candidates, id), do: nil, else: id
  end

  defp pick_scroll_candidate(hierarchy, _candidates, {id, _info}) do
    state = get_widget_state(hierarchy, id)
    if state && Map.get(state, :scroll_locked, false), do: id, else: nil
  end

  defp claimed_by_outer_click_to_scroll?(hierarchy, candidates, inner_id) do
    Enum.any?(candidates, fn {outer_id, outer_info} ->
      outer_id != inner_id and
        outer_info.click_to_scroll and
        MapSet.member?(outer_info.scroll_exceptions, inner_id) and
        not scroll_locked?(hierarchy, outer_id)
    end)
  end

  defp scroll_locked?(hierarchy, scroll_id) do
    state = get_widget_state(hierarchy, scroll_id)
    state != nil and Map.get(state, :scroll_locked, false)
  end

  defp make_relative_mouse_event(hierarchy, widget_id, mouse_event) do
    case Map.get(hierarchy.widget_rects, widget_id) do
      nil ->
        mouse_event

      virtual_rect ->
        screen_rect = translate_rect_to_screen(hierarchy, widget_id, virtual_rect)
        rect = screen_rect || virtual_rect

        %{
          mouse_event
          | x: mouse_event.x - rect.x,
            y: mouse_event.y - rect.y
        }
    end
  end

  defp update_hover_state(hierarchy, target_widget) do
    prev_hover = hierarchy.hover_widget

    cond do
      prev_hover == target_widget ->
        hierarchy

      prev_hover != nil and target_widget != prev_hover ->
        {h1, _} = handle_widget_event(hierarchy, prev_hover, :unhover)
        send_hover_if_target(%{h1 | hover_widget: target_widget}, target_widget)

      prev_hover == nil and target_widget != nil ->
        {h1, _} = handle_widget_event(hierarchy, target_widget, :hover)
        %{h1 | hover_widget: target_widget}

      true ->
        hierarchy
    end
  end

  defp send_hover_if_target(hierarchy, nil), do: hierarchy

  defp send_hover_if_target(hierarchy, target_widget) do
    {h, _} = handle_widget_event(hierarchy, target_widget, :hover)
    h
  end

  @doc "Get widget state"
  @spec get_widget_state(t(), widget_id()) :: map() | nil
  def get_widget_state(hierarchy, widget_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> nil
      %{pid: pid} when is_pid(pid) -> WidgetServer.get_state(pid)
      widget_info -> widget_info.state
    end
  end

  @doc "Set widget state"
  @spec set_widget_state(t(), widget_id(), map()) :: t()
  def set_widget_state(hierarchy, widget_id, new_state) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      widget_info ->
        updated_widget = %{widget_info | state: new_state}
        new_widgets = Map.put(hierarchy.widgets, widget_id, updated_widget)
        %{hierarchy | widgets: new_widgets}
    end
  end

  defp handle_widget_event(hierarchy, widget_id, event) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        {hierarchy, []}

      widget_info ->
        dispatch_widget_event(hierarchy, widget_id, widget_info, event)
    end
  end

  defp dispatch_widget_event(hierarchy, widget_id, widget_info, event) do
    case try_handle_event(widget_info, event) do
      {new_state, actions, :stop} ->
        {set_widget_state(hierarchy, widget_id, new_state), actions}

      {new_state, actions, :bubble} ->
        new_hierarchy = set_widget_state(hierarchy, widget_id, new_state)
        bubble_to_parent(new_hierarchy, widget_info.parent, event, actions)

      :not_handled ->
        bubble_to_parent(hierarchy, widget_info.parent, event, [])
    end
  end

  defp bubble_to_parent(hierarchy, nil, _event, actions), do: {hierarchy, actions}

  defp bubble_to_parent(hierarchy, parent_id, event, actions) do
    {final_hierarchy, parent_actions} = handle_widget_event(hierarchy, parent_id, event)
    {final_hierarchy, actions ++ parent_actions}
  end

  defp try_handle_event(%{pid: pid} = widget_info, event) when is_pid(pid) do
    WidgetServer.send_event_sync(pid, event)
    |> Drafter.EventResult.parse(widget_info.state)
  end

  defp try_handle_event(widget_info, event) do
    if function_exported?(widget_info.module, :handle_event, 2) do
      widget_info.module.handle_event(event, widget_info.state)
      |> Drafter.EventResult.parse(widget_info.state)
    else
      :not_handled
    end
  end

  defp get_focusable_widgets(hierarchy) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      focusable_widget?(widget_info.module) and
        not disabled?(widget_info.state) and
        not MapSet.member?(hidden, widget_id) and
        ancestors_expanded?(hierarchy, widget_info.parent)
    end)
    |> Enum.sort_by(fn {widget_id, _widget_info} ->
      rect = Map.get(hierarchy.widget_rects, widget_id, %{y: 0, x: 0})
      {Map.get(rect, :y, 0), Map.get(rect, :x, 0)}
    end)
    |> Enum.map(fn {widget_id, _widget_info} -> widget_id end)
  end

  defp ancestors_expanded?(_hierarchy, nil), do: true

  defp ancestors_expanded?(hierarchy, ancestor_id) do
    case Map.get(hierarchy.widgets, ancestor_id) do
      nil ->
        true

      ancestor ->
        if Map.get(ancestor.state, :expanded) == false do
          false
        else
          ancestors_expanded?(hierarchy, ancestor.parent)
        end
    end
  end

  defp disabled?(state) do
    Map.get(state, :disabled, false)
  end

  defp focusable_widget?(module) do
    function_exported?(module, :__widget_capabilities__, 0) and
      Map.get(module.__widget_capabilities__(), :focusable, false)
  end

  @doc "Query widgets by selector string"
  @spec query_all(t(), String.t()) :: [widget_id()]
  def query_all(hierarchy, selector) do
    parsed = Drafter.Style.Selector.parse(selector)

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      matches_selector?(widget_id, widget_info, parsed)
    end)
    |> Enum.map(fn {widget_id, _} -> widget_id end)
  end

  @doc "Query a single widget by selector string"
  @spec query_one(t(), String.t()) :: widget_id() | nil
  def query_one(hierarchy, selector) do
    case query_all(hierarchy, selector) do
      [widget_id | _] -> widget_id
      [] -> nil
    end
  end

  defp matches_selector?(widget_id, widget_info, selectors) when is_list(selectors) do
    Enum.any?(selectors, &matches_single_selector?(widget_id, widget_info, &1))
  end

  defp matches_single_selector?(widget_id, widget_info, %Drafter.Style.Selector{} = selector) do
    matches_type?(widget_info.module, selector.widget_type) and
      matches_id?(widget_id, selector.id) and
      matches_classes?(widget_info.state, selector.classes)
  end

  defp matches_type?(_module, nil), do: true

  defp matches_type?(module, type) when is_atom(type) do
    type_name = module_to_type_name(module)
    type_name == type
  end

  defp matches_id?(_widget_id, nil), do: true

  defp matches_id?(widget_id, id) when is_atom(id) do
    widget_id == id
  end

  defp matches_classes?(_state, []), do: true

  defp matches_classes?(state, classes) do
    widget_classes = Map.get(state, :classes, [])
    Enum.all?(classes, &(&1 in widget_classes))
  end

  defp module_to_type_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  def broadcast_event(hierarchy, event) do
    Enum.reduce(hierarchy.widgets, {hierarchy, []}, fn {widget_id, _widget_info}, {h, actions} ->
      {new_h, new_actions} = send_event_to_widget(h, widget_id, event)
      {new_h, actions ++ new_actions}
    end)
  end

  def send_event_to_widget(hierarchy, widget_id, event) do
    handle_widget_event(hierarchy, widget_id, event)
  end

  @doc "Register a scroll container with its viewport info"
  @spec register_scroll_container(t(), widget_id(), rect(), integer(), integer(), boolean()) :: t()
  def register_scroll_container(
        hierarchy,
        scroll_id,
        viewport_rect,
        content_height,
        content_width,
        click_to_scroll \\ false
      ) do
    scroll_info = %{
      viewport_rect: viewport_rect,
      content_height: content_height,
      content_width: content_width,
      click_to_scroll: click_to_scroll,
      scroll_exceptions: MapSet.new()
    }

    updated_containers = Map.put(hierarchy.scroll_containers, scroll_id, scroll_info)

    updated_containers =
      Enum.reduce(updated_containers, updated_containers, fn {existing_id, existing_info}, acc ->
        update_scroll_exceptions(acc, scroll_id, viewport_rect, click_to_scroll, existing_id, existing_info)
      end)

    %{hierarchy | scroll_containers: updated_containers}
  end

  defp update_scroll_exceptions(acc, scroll_id, _viewport_rect, _click_to_scroll, scroll_id, _existing_info), do: acc

  defp update_scroll_exceptions(acc, scroll_id, viewport_rect, _click_to_scroll, existing_id, %{click_to_scroll: true} = existing_info) do
    if viewport_rect_contains?(existing_info.viewport_rect, viewport_rect) do
      add_scroll_exception(acc, existing_id, scroll_id)
    else
      acc
    end
  end

  defp update_scroll_exceptions(acc, scroll_id, viewport_rect, true, existing_id, existing_info) do
    if viewport_rect_contains?(viewport_rect, existing_info.viewport_rect) do
      add_scroll_exception(acc, scroll_id, existing_id)
    else
      acc
    end
  end

  defp update_scroll_exceptions(acc, _scroll_id, _viewport_rect, _click_to_scroll, _existing_id, _existing_info), do: acc

  defp add_scroll_exception(containers, container_id, exception_id) do
    Map.update!(containers, container_id, fn info ->
      %{info | scroll_exceptions: MapSet.put(info.scroll_exceptions, exception_id)}
    end)
  end

  defp viewport_rect_contains?(outer, inner) do
    inner.x >= outer.x and
      inner.y >= outer.y and
      inner.x + inner.width <= outer.x + outer.width and
      inner.y + inner.height <= outer.y + outer.height
  end

  @doc "Set the scroll parent for a widget"
  @spec set_widget_scroll_parent(t(), widget_id(), widget_id()) :: t()
  def set_widget_scroll_parent(hierarchy, widget_id, scroll_parent_id) do
    new_parents = Map.put(hierarchy.widget_scroll_parents, widget_id, scroll_parent_id)
    %{hierarchy | widget_scroll_parents: new_parents}
  end

  @doc "Get the scroll parent for a widget"
  @spec get_widget_scroll_parent(t(), widget_id()) :: widget_id() | nil
  def get_widget_scroll_parent(hierarchy, widget_id) do
    Map.get(hierarchy.widget_scroll_parents, widget_id)
  end

  @doc "Get scroll container info"
  @spec get_scroll_container_info(t(), widget_id()) :: scroll_info() | nil
  def get_scroll_container_info(hierarchy, scroll_id) do
    Map.get(hierarchy.scroll_containers, scroll_id)
  end

  @doc "Update scroll container content dimensions"
  @spec update_scroll_container_content(t(), widget_id(), integer(), integer()) :: t()
  def update_scroll_container_content(hierarchy, scroll_id, content_height, content_width) do
    case Map.get(hierarchy.scroll_containers, scroll_id) do
      nil ->
        hierarchy

      info ->
        updated_info = %{info | content_height: content_height, content_width: content_width}
        new_scroll_containers = Map.put(hierarchy.scroll_containers, scroll_id, updated_info)
        %{hierarchy | scroll_containers: new_scroll_containers}
    end
  end

  defp build_ancestor_path(hierarchy, widget_id, acc \\ []) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> Enum.reverse(acc)
      %{parent: nil} -> Enum.reverse([widget_id | acc])
      %{parent: parent_id} -> build_ancestor_path(hierarchy, parent_id, [widget_id | acc])
    end
  end

  defp try_handle_event_capture(%{pid: pid} = widget_info, event) when is_pid(pid) do
    if function_exported?(widget_info.module, :handle_event_capture, 2) do
      WidgetServer.call_capture_handler(pid, event)
      |> classify_capture_result(event, widget_info.state)
    else
      {:continue, event, widget_info.state}
    end
  end

  defp try_handle_event_capture(widget_info, event) do
    if function_exported?(widget_info.module, :handle_event_capture, 2) do
      widget_info.module.handle_event_capture(event, widget_info.state)
      |> classify_capture_result(event, widget_info.state)
    else
      {:continue, event, widget_info.state}
    end
  end

  defp classify_capture_result({:continue, updated_event, new_state}, _event, _fallback_state) do
    {:continue, updated_event, new_state}
  end

  defp classify_capture_result({:stop, updated_event, new_state, actions}, _event, _fallback_state) do
    {:stop, Drafter.Event.Object.stop_propagation(updated_event), new_state, actions}
  end

  defp classify_capture_result({:prevent, updated_event, new_state}, _event, _fallback_state) do
    stopped = updated_event |> Drafter.Event.Object.prevent_default() |> Drafter.Event.Object.stop_propagation()
    {:stop, stopped, new_state, []}
  end

  defp classify_capture_result(_, event, fallback_state) do
    {:continue, event, fallback_state}
  end

  defp dispatch_capture_phase(hierarchy, event, path) do
    Enum.reduce_while(path, {hierarchy, event, []}, fn widget_id, {h, evt, actions} ->
      if evt.immediate_propagation_stopped do
        {:halt, {h, evt, actions}}
      else
        process_capture_widget(h, widget_id, evt, actions)
      end
    end)
  end

  defp process_capture_widget(h, widget_id, evt, actions) do
    case Map.get(h.widgets, widget_id) do
      nil ->
        {:cont, {h, evt, actions}}

      widget_info ->
        evt = %{evt | current_target: widget_id, phase: :capture}

        case try_handle_event_capture(widget_info, evt) do
          {:continue, updated_event, new_state} ->
            {:cont, {set_widget_state(h, widget_id, new_state), updated_event, actions}}

          {:stop, updated_event, new_state, new_actions} ->
            {:halt, {set_widget_state(h, widget_id, new_state), updated_event, actions ++ new_actions}}
        end
    end
  end
end
