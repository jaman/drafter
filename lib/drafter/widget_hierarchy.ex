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

        new_widgets =
          if widget_info.parent do
            case Map.get(hierarchy.widgets, widget_info.parent) do
              nil ->
                hierarchy.widgets

              parent_info ->
                updated_children = List.delete(parent_info.children, widget_id)
                updated_parent = %{parent_info | children: updated_children}
                Map.put(hierarchy.widgets, widget_info.parent, updated_parent)
            end
          else
            hierarchy.widgets
          end

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

  @doc "Update widget with new props"
  @spec update_widget(t(), widget_id(), map()) :: t()
  @spec update_widget_parent(t(), widget_id(), widget_id() | nil) :: t()
  def update_widget_parent(hierarchy, widget_id, parent_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> hierarchy
      widget_info ->
        updated = %{widget_info | parent: parent_id}
        %{hierarchy | widgets: Map.put(hierarchy.widgets, widget_id, updated)}
    end
  end

  def update_widget(hierarchy, widget_id, new_props) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      widget_info ->
        if widget_info.pid do
          WidgetServer.update_props(widget_info.pid, new_props)
          hierarchy
        else
          new_state =
            if function_exported?(widget_info.module, :update, 2) do
              apply(widget_info.module, :update, [new_props, widget_info.state])
            else
              Map.merge(widget_info.state, new_props)
            end

          updated_widget = %{widget_info | state: new_state}
          new_widgets = Map.put(hierarchy.widgets, widget_id, updated_widget)
          %{hierarchy | widgets: new_widgets}
        end
    end
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
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        hierarchy

      widget_info ->
        updated_widget = %{widget_info | state: new_state}
        new_widgets = Map.put(hierarchy.widgets, widget_id, updated_widget)
        %{hierarchy | widgets: new_widgets}
    end
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
      nil ->
        hierarchy

      scroll_parent_id ->
        scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
        widget_rect = Map.get(hierarchy.widget_rects, widget_id)
        scroll_state = get_widget_state(hierarchy, scroll_parent_id)

        if scroll_info && widget_rect && scroll_state do
          viewport = scroll_info.viewport_rect
          scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

          widget_top = widget_rect.y
          widget_bottom = widget_rect.y + widget_rect.height
          viewport_top = viewport.y + scroll_y
          viewport_bottom = viewport_top + viewport.height

          new_scroll_y =
            cond do
              widget_top < viewport_top ->
                widget_top - viewport.y

              widget_bottom > viewport_bottom ->
                widget_bottom - viewport.y - viewport.height

              true ->
                scroll_y
            end

          new_scroll_y = max(0, new_scroll_y)
          max_scroll = max(0, scroll_info.content_height - viewport.height)
          new_scroll_y = min(new_scroll_y, max_scroll)

          if new_scroll_y != scroll_y do
            update_widget(hierarchy, scroll_parent_id, %{scroll_offset_y: new_scroll_y})
          else
            hierarchy
          end
        else
          hierarchy
        end
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
      nil ->
        virtual_rect

      scroll_parent_id ->
        scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
        scroll_state = get_widget_state(hierarchy, scroll_parent_id)

        if scroll_info && scroll_state do
          viewport = scroll_info.viewport_rect
          scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

          screen_y = virtual_rect.y - scroll_y
          screen_bottom = screen_y + virtual_rect.height

          if screen_bottom <= viewport.y or screen_y >= viewport.y + viewport.height do
            nil
          else
            visible_top = max(screen_y, viewport.y)
            visible_bottom = min(screen_bottom, viewport.y + viewport.height)
            visible_height = visible_bottom - visible_top

            %{
              x: virtual_rect.x,
              y: visible_top,
              width: virtual_rect.width,
              height: visible_height
            }
          end
        else
          virtual_rect
        end
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
  def handle_event(hierarchy, event) do
    should_log =
      case event do
        {:mouse, %{type: :move}} -> false
        _ -> true
      end

    if should_log do
    end

    result =
      case event do
        {:key, :tab} ->
          cycle_focus(hierarchy)
          |> then(&{&1, []})

        {:key, :tab, [:shift]} ->
          cycle_focus_reverse(hierarchy)
          |> then(&{&1, []})

        {:key, ?\t} ->
          cycle_focus(hierarchy)
          |> then(&{&1, []})

        {:key, ?\t, mods} when is_list(mods) ->
          if :shift in mods do
            cycle_focus_reverse(hierarchy)
            |> then(&{&1, []})
          else
            cycle_focus(hierarchy)
            |> then(&{&1, []})
          end

        {:key, :enter} ->
          dispatch_to_focused(hierarchy, event)

        {:key, :" "} ->
          dispatch_to_focused(hierarchy, event)

        {:key, :left} ->
          try_arrow_navigation(hierarchy, event, :left)

        {:key, :left, [:shift]} ->
          try_arrow_navigation(hierarchy, event, :left)

        {:key, :right} ->
          try_arrow_navigation(hierarchy, event, :right)

        {:key, :right, [:shift]} ->
          try_arrow_navigation(hierarchy, event, :right)

        {:key, :up} ->
          try_arrow_navigation(hierarchy, event, :up)

        {:key, :up, [:shift]} ->
          try_arrow_navigation(hierarchy, event, :up)

        {:key, :down} ->
          try_arrow_navigation(hierarchy, event, :down)

        {:key, :down, [:shift]} ->
          try_arrow_navigation(hierarchy, event, :down)

        {:key, :home} ->
          dispatch_to_focused(hierarchy, event)

        {:key, :end} ->
          dispatch_to_focused(hierarchy, event)

        {:key, :page_up} ->
          dispatch_to_focused(hierarchy, event)

        {:key, :page_down} ->
          dispatch_to_focused(hierarchy, event)

        {:mouse, mouse_event} ->
          handle_mouse_event(hierarchy, mouse_event)

        {:key, _key} ->
          dispatch_to_focused(hierarchy, event)

        {:key, _key, _mods} ->
          dispatch_to_focused(hierarchy, event)

        _ ->
          {hierarchy, []}
      end

    if should_log do
    end

    result
  end

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
        current_state = WidgetServer.get_state(pid)
        updated_info = %{info | state: current_state}
        updated_widgets = Map.put(hierarchy.widgets, hierarchy.focused_widget, updated_info)
        %{hierarchy | widgets: updated_widgets}

      _ ->
        hierarchy
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
      case hierarchy.focused_widget do
        nil ->
          first_widget = hd(focusable_widgets)
          {focus_widget(hierarchy, first_widget, :down), []}

        focused_id ->
          case dispatch_to_focused(hierarchy, event) do
            {^hierarchy, []} ->
              navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction)

            {_hierarchy, [_ | _]} = result ->
              result

            {_new_hierarchy, []} = result ->
              result
          end
      end
    end
  end

  defp navigate_by_arrow(hierarchy, focused_id, focusable_widgets, direction) do
    focused_rect = Map.get(hierarchy.widget_rects, focused_id)

    if focused_rect == nil do
      {hierarchy, []}
    else
      focused_point = %{x: focused_rect.x, y: focused_rect.y}

      candidates =
        focusable_widgets
        |> Enum.reject(&(&1 == focused_id))
        |> Enum.map(fn widget_id ->
          rect = Map.get(hierarchy.widget_rects, widget_id)
          if rect, do: {widget_id, rect, %{x: rect.x, y: rect.y}}, else: nil
        end)
        |> Enum.reject(&is_nil/1)

      target =
        case direction do
          :up ->
            candidates
            |> Enum.filter(fn {_id, _rect, pt} -> pt.y < focused_point.y end)
            |> Enum.min_by(
              fn {_id, _rect, pt} ->
                {focused_point.y - pt.y, abs(pt.x - focused_point.x)}
              end,
              fn -> nil end
            )

          :down ->
            candidates
            |> Enum.filter(fn {_id, _rect, pt} -> pt.y > focused_point.y end)
            |> Enum.min_by(
              fn {_id, _rect, pt} ->
                {pt.y - focused_point.y, abs(pt.x - focused_point.x)}
              end,
              fn -> nil end
            )

          :left ->
            candidates
            |> Enum.filter(fn {_id, _rect, pt} -> pt.x < focused_point.x end)
            |> Enum.min_by(
              fn {_id, _rect, pt} ->
                {focused_point.x - pt.x, abs(pt.y - focused_point.y)}
              end,
              fn -> nil end
            )

          :right ->
            candidates
            |> Enum.filter(fn {_id, _rect, pt} -> pt.x > focused_point.x end)
            |> Enum.min_by(
              fn {_id, _rect, pt} ->
                {pt.x - focused_point.x, abs(pt.y - focused_point.y)}
              end,
              fn -> nil end
            )
        end

      case target do
        {widget_id, _rect, _pt} ->
          {focus_widget(hierarchy, widget_id, :down), []}

        nil ->
          {hierarchy, []}
      end
    end
  end

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
        case find_scroll_container_at(hierarchy, mouse_event.x, mouse_event.y) do
          nil -> {hierarchy, []}
          scroll_id -> handle_event_with_phases(hierarchy, scroll_id, {:mouse, mouse_event})
        end

      {_, nil} ->
        {hierarchy, []}

      {:move, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_up, widget_id} ->
        if :ctrl in Map.get(mouse_event, :mods, []) do
          hierarchy =
            toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y)

          {hierarchy, []}
        else
          hierarchy = clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
          hierarchy = focus_widget(hierarchy, widget_id)
          relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)

          handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
        end

      {:drag, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)

        {new_hierarchy, actions} =
          handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

        widget_state = get_widget_state(new_hierarchy, widget_id)
        new_hierarchy = maybe_start_drag_capture(new_hierarchy, widget_id, widget_state)
        {new_hierarchy, actions}

      {:scroll, widget_id} ->
        relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
        handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})

      {:mouse_down, widget_id} ->
        if :ctrl in Map.get(mouse_event, :mods, []) do
          hierarchy = toggle_scroll_lock_at(hierarchy, mouse_event.x, mouse_event.y)
          {hierarchy, []}
        else
          hierarchy = clear_scroll_locks_outside(hierarchy, mouse_event.x, mouse_event.y)
          hierarchy = focus_widget(hierarchy, widget_id)
          relative_event = make_relative_mouse_event(hierarchy, widget_id, mouse_event)
          {new_hierarchy, actions} =
            handle_event_with_phases(hierarchy, widget_id, {:mouse, relative_event})
          widget_state = get_widget_state(new_hierarchy, widget_id)
          new_hierarchy = maybe_start_drag_capture(new_hierarchy, widget_id, widget_state)
          {new_hierarchy, actions}
        end

      {_, _widget_id} ->
        {hierarchy, []}
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
      nil ->
        hierarchy

      {scroll_id, _info} ->
        case get_widget_state(hierarchy, scroll_id) do
          nil ->
            hierarchy

          state ->
            new_state = %{state | scroll_locked: not state.scroll_locked}
            update_widget_state_in_hierarchy(hierarchy, scroll_id, new_state)
        end
    end
  end

  defp clear_scroll_locks_outside(hierarchy, x, y) do
    Enum.reduce(hierarchy.scroll_containers, hierarchy, fn {scroll_id, info}, h ->
      if info.click_to_scroll do
        v = info.viewport_rect
        outside = not (x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height)

        if outside do
          case get_widget_state(h, scroll_id) do
            nil ->
              h

            state ->
              if Map.get(state, :scroll_locked, false) do
                new_state = %{state | scroll_locked: false}
                update_widget_state_in_hierarchy(h, scroll_id, new_state)
              else
                h
              end
          end
        else
          h
        end
      else
        h
      end
    end)
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

    case candidates do
      [] ->
        nil

      [{id, info}] when not info.click_to_scroll ->
        id

      _ ->
        sorted =
          Enum.sort_by(candidates, fn {_id, info} ->
            info.viewport_rect.width * info.viewport_rect.height
          end)

        Enum.find_value(sorted, fn {id, info} ->
          cond do
            not info.click_to_scroll ->
              if claimed_by_outer_click_to_scroll?(hierarchy, candidates, id), do: nil, else: id

            info.click_to_scroll ->
              state = get_widget_state(hierarchy, id)
              if state && Map.get(state, :scroll_locked, false), do: id, else: nil
          end
        end)
    end
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
        h2 = %{h1 | hover_widget: target_widget}

        if target_widget do
          {h3, _} = handle_widget_event(h2, target_widget, :hover)
          h3
        else
          h2
        end

      prev_hover == nil and target_widget != nil ->
        {h1, _} = handle_widget_event(hierarchy, target_widget, :hover)
        %{h1 | hover_widget: target_widget}

      true ->
        hierarchy
    end
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
    widget_info = Map.get(hierarchy.widgets, widget_id)

    if widget_info do
      case try_handle_event(widget_info, event) do
        {new_state, actions, :stop} ->
          new_hierarchy = set_widget_state(hierarchy, widget_id, new_state)

          if actions != [] do
          end

          {new_hierarchy, actions}

        {new_state, actions, :bubble} ->
          new_hierarchy = set_widget_state(hierarchy, widget_id, new_state)

          case widget_info.parent do
            nil ->
              if actions != [] do
              end

              {new_hierarchy, actions}

            parent_id ->
              {final_hierarchy, parent_actions} =
                handle_widget_event(new_hierarchy, parent_id, event)

              if actions != [] or parent_actions != [] do
              end

              {final_hierarchy, actions ++ parent_actions}
          end

        :not_handled ->
          case widget_info.parent do
            nil -> {hierarchy, []}
            parent_id -> handle_widget_event(hierarchy, parent_id, event)
          end
      end
    else
      {hierarchy, []}
    end
  end

  defp try_handle_event(widget_info, event) do
    if widget_info.pid do
      result = WidgetServer.send_event_sync(widget_info.pid, event)

      case result do
        {:ok, new_state, actions} ->
          {new_state, actions, :stop}

        {:ok, new_state} ->
          {new_state, [], :stop}

        {:noreply, _new_state} ->
          :not_handled

        {:bubble, new_state, actions} ->
          {new_state, actions, :bubble}

        {:bubble, new_state} ->
          {new_state, [], :bubble}

        {:pop, _} = pop ->
          {widget_info.state, [pop], :stop}

        {:push, _, _} = push ->
          {widget_info.state, [push], :stop}

        {:replace, _, _} = replace ->
          {widget_info.state, [replace], :stop}

        {:app_callback, _, _} = app_callback ->
          {widget_info.state, [app_callback], :stop}

        _ ->
          :not_handled
      end
    else
      if function_exported?(widget_info.module, :handle_event, 2) do
        result = apply(widget_info.module, :handle_event, [event, widget_info.state])

        case result do
          {:ok, new_state, actions} -> {new_state, actions, :stop}
          {:ok, new_state} -> {new_state, [], :stop}
          {:noreply, _new_state} -> :not_handled
          {:bubble, new_state, actions} -> {new_state, actions, :bubble}
          {:bubble, new_state} -> {new_state, [], :bubble}
          {:pop, _} = pop -> {widget_info.state, [pop], :stop}
          {:push, _, _} = push -> {widget_info.state, [push], :stop}
          {:replace, _, _} = replace -> {widget_info.state, [replace], :stop}
          {:app_callback, _, _} = app_callback -> {widget_info.state, [app_callback], :stop}
          _ -> :not_handled
        end
      else
        :not_handled
      end
    end
  end

  defp get_focusable_widgets(hierarchy) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      is_focusable_widget?(widget_info.module) and not is_disabled?(widget_info.state) and
        not MapSet.member?(hidden, widget_id)
    end)
    |> Enum.sort_by(fn {widget_id, _widget_info} ->
      rect = Map.get(hierarchy.widget_rects, widget_id, %{y: 0, x: 0})
      {Map.get(rect, :y, 0), Map.get(rect, :x, 0)}
    end)
    |> Enum.map(fn {widget_id, _widget_info} -> widget_id end)
  end

  defp is_disabled?(state) do
    Map.get(state, :disabled, false)
  end

  defp is_focusable_widget?(module) do
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
        cond do
          existing_id == scroll_id ->
            acc

          existing_info.click_to_scroll and
              viewport_rect_contains?(existing_info.viewport_rect, viewport_rect) ->
            updated = Map.update!(acc, existing_id, fn info ->
              %{info | scroll_exceptions: MapSet.put(info.scroll_exceptions, scroll_id)}
            end)
            updated

          click_to_scroll and
              viewport_rect_contains?(viewport_rect, existing_info.viewport_rect) ->
            Map.update!(acc, scroll_id, fn info ->
              %{info | scroll_exceptions: MapSet.put(info.scroll_exceptions, existing_id)}
            end)

          true ->
            acc
        end
      end)

    %{hierarchy | scroll_containers: updated_containers}
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
      nil ->
        Enum.reverse(acc)

      widget_info ->
        case widget_info.parent do
          nil ->
            Enum.reverse([widget_id | acc])

          parent_id ->
            build_ancestor_path(hierarchy, parent_id, [widget_id | acc])
        end
    end
  end

  defp try_handle_event_capture(widget_info, event) do
    if widget_info.pid do
      if function_exported?(widget_info.module, :handle_event_capture, 2) do
        case WidgetServer.call_capture_handler(widget_info.pid, event) do
          {:continue, updated_event, new_state} ->
            {:continue, updated_event, new_state}

          {:stop, updated_event, new_state, actions} ->
            updated_event = Drafter.Event.Object.stop_propagation(updated_event)
            {:stop, updated_event, new_state, actions}

          {:prevent, updated_event, new_state} ->
            updated_event = Drafter.Event.Object.prevent_default(updated_event)
            updated_event = Drafter.Event.Object.stop_propagation(updated_event)
            {:stop, updated_event, new_state, []}

          _ ->
            {:continue, event, widget_info.state}
        end
      else
        {:continue, event, widget_info.state}
      end
    else
      if function_exported?(widget_info.module, :handle_event_capture, 2) do
        case apply(widget_info.module, :handle_event_capture, [event, widget_info.state]) do
          {:continue, updated_event, new_state} ->
            {:continue, updated_event, new_state}

          {:stop, updated_event, new_state, actions} ->
            updated_event = Drafter.Event.Object.stop_propagation(updated_event)
            {:stop, updated_event, new_state, actions}

          {:prevent, updated_event, new_state} ->
            updated_event = Drafter.Event.Object.prevent_default(updated_event)
            updated_event = Drafter.Event.Object.stop_propagation(updated_event)
            {:stop, updated_event, new_state, []}

          _ ->
            {:continue, event, widget_info.state}
        end
      else
        {:continue, event, widget_info.state}
      end
    end
  end

  defp dispatch_capture_phase(hierarchy, event, path) do
    Enum.reduce_while(path, {hierarchy, event, []}, fn widget_id, {h, evt, actions} ->
      if evt.immediate_propagation_stopped do
        {:halt, {h, evt, actions}}
      else
        widget_info = Map.get(h.widgets, widget_id)

        if widget_info do
          evt = %{evt | current_target: widget_id, phase: :capture}

          case try_handle_event_capture(widget_info, evt) do
            {:continue, updated_event, new_state} ->
              new_h = set_widget_state(h, widget_id, new_state)
              {:cont, {new_h, updated_event, actions}}

            {:stop, updated_event, new_state, new_actions} ->
              new_h = set_widget_state(h, widget_id, new_state)
              {:halt, {new_h, updated_event, actions ++ new_actions}}
          end
        else
          {:cont, {h, evt, actions}}
        end
      end
    end)
  end
end
