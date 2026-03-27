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

  @session_pdict_keys [
    :drafter_event_manager,
    :drafter_compositor,
    :drafter_theme_manager,
    :drafter_screen_manager,
    :drafter_event_handler,
    :drafter_skin_manager
  ]

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

  @spec update_preferred_size(t(), widget_id(), integer()) :: t()
  def update_preferred_size(hierarchy, widget_id, size) do
    new_sizes = Map.put(hierarchy.preferred_sizes, widget_id, size)
    %{hierarchy | preferred_sizes: new_sizes}
  end

  @spec get_preferred_size(t(), widget_id()) :: integer() | nil
  def get_preferred_size(hierarchy, widget_id) do
    Map.get(hierarchy.preferred_sizes, widget_id)
  end

  defp mark_widget_rendered(widget_id) do
    rendered = Process.get(:rendered_widget_ids, MapSet.new())
    Process.put(:rendered_widget_ids, MapSet.put(rendered, widget_id))
  end

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

    session_ctx = collect_session_pdict()

    {:ok, pid} =
      WidgetServer.start_link(
        id: widget_id,
        module: widget_module,
        props: mount_props,
        rect: rect,
        session_ctx: session_ctx
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

  @spec get_widget_info(t(), widget_id()) :: map() | nil
  def get_widget_info(hierarchy, widget_id) do
    Map.get(hierarchy.widgets, widget_id)
  end

  @spec get_parent(t(), widget_id()) :: widget_id() | nil
  def get_parent(hierarchy, widget_id) do
    case get_widget_info(hierarchy, widget_id) do
      nil -> nil
      widget_info -> widget_info.parent
    end
  end

  @spec get_children(t(), widget_id()) :: [widget_id()]
  def get_children(hierarchy, parent_id) do
    hierarchy.widgets
    |> Enum.filter(fn {_id, widget_info} ->
      widget_info.parent == parent_id
    end)
    |> Enum.map(fn {id, _widget_info} -> id end)
  end

  @spec update_widget_state(t(), widget_id(), map()) :: t()
  def update_widget_state(hierarchy, widget_id, new_state) do
    update_widget_info(hierarchy, widget_id, &%{&1 | state: new_state})
  end

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

  @spec get_widget_state(t(), widget_id()) :: map() | nil
  def get_widget_state(hierarchy, widget_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> nil
      %{pid: pid} when is_pid(pid) -> WidgetServer.get_state(pid)
      widget_info -> widget_info.state
    end
  end

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

  def put_widget(hierarchy, widget_id, widget_info) do
    %{hierarchy | widgets: Map.put(hierarchy.widgets, widget_id, widget_info)}
  end

  def update_widget_info(hierarchy, widget_id, fun) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> hierarchy
      info -> put_widget(hierarchy, widget_id, fun.(info))
    end
  end

  def update_widget_state_in_hierarchy(hierarchy, widget_id, new_state) do
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

  def live_widget_state(%{pid: pid}) when is_pid(pid), do: WidgetServer.get_state(pid)
  def live_widget_state(%{state: state}), do: state

  def collect_session_pdict do
    Enum.reduce(@session_pdict_keys, %{}, fn key, acc ->
      case Process.get(key) do
        nil -> acc
        val -> Map.put(acc, key, val)
      end
    end)
  end

  defdelegate focus_widget(hierarchy, widget_id), to: __MODULE__.Focus
  defdelegate focus_widget(hierarchy, widget_id, direction), to: __MODULE__.Focus
  defdelegate cycle_focus(hierarchy), to: __MODULE__.Focus
  defdelegate cycle_focus_reverse(hierarchy), to: __MODULE__.Focus

  defdelegate handle_event(hierarchy, event), to: __MODULE__.EventRouter
  defdelegate handle_event_consumed(hierarchy, event), to: __MODULE__.EventRouter
  defdelegate broadcast_event(hierarchy, event), to: __MODULE__.EventRouter
  defdelegate send_event_to_widget(hierarchy, widget_id, event), to: __MODULE__.EventRouter

  defdelegate find_widget_at(hierarchy, x, y), to: __MODULE__.HitTest

  defdelegate query_all(hierarchy, selector), to: __MODULE__.Query
  defdelegate query_one(hierarchy, selector), to: __MODULE__.Query

  defdelegate register_scroll_container(
                hierarchy,
                scroll_id,
                viewport_rect,
                content_height,
                content_width
              ),
              to: __MODULE__.Scroll

  defdelegate register_scroll_container(
                hierarchy,
                scroll_id,
                viewport_rect,
                content_height,
                content_width,
                click_to_scroll
              ),
              to: __MODULE__.Scroll

  defdelegate set_widget_scroll_parent(hierarchy, widget_id, scroll_parent_id),
    to: __MODULE__.Scroll

  defdelegate get_widget_scroll_parent(hierarchy, widget_id),
    to: __MODULE__.Scroll

  defdelegate get_scroll_container_info(hierarchy, scroll_id),
    to: __MODULE__.Scroll

  defdelegate update_scroll_container_content(
                hierarchy,
                scroll_id,
                content_height,
                content_width
              ),
              to: __MODULE__.Scroll
end
