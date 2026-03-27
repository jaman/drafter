defmodule Drafter.WidgetHierarchy.EventRouter do
  @moduledoc false

  alias Drafter.Event
  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetHierarchy.{Focus, Mouse}
  alias Drafter.WidgetServer

  @spec handle_event(WidgetHierarchy.t(), term()) :: {WidgetHierarchy.t(), [term()]}
  def handle_event(hierarchy, {:mouse, mouse_event}) do
    Mouse.handle_mouse_event(hierarchy, mouse_event)
  end

  def handle_event(hierarchy, event), do: handle_key_event(hierarchy, event)

  def handle_key_event(hierarchy, {:key, :tab}), do: {Focus.cycle_focus(hierarchy), []}
  def handle_key_event(hierarchy, {:key, :tab, _}), do: {Focus.cycle_focus_reverse(hierarchy), []}
  def handle_key_event(hierarchy, {:key, ?\t}), do: {Focus.cycle_focus(hierarchy), []}

  def handle_key_event(hierarchy, {:key, ?\t, mods}) when is_list(mods) do
    if :shift in mods, do: {Focus.cycle_focus_reverse(hierarchy), []}, else: {Focus.cycle_focus(hierarchy), []}
  end

  def handle_key_event(hierarchy, {:key, dir} = event) when dir in [:left, :right, :up, :down] do
    Focus.try_arrow_navigation(hierarchy, event, dir)
  end

  def handle_key_event(hierarchy, {:key, dir, _} = event) when dir in [:left, :right, :up, :down] do
    Focus.try_arrow_navigation(hierarchy, event, dir)
  end

  def handle_key_event(hierarchy, event), do: dispatch_to_focused_or_ignore(hierarchy, event)

  def dispatch_to_focused_or_ignore(hierarchy, {:key, _} = event), do: dispatch_to_focused(hierarchy, event)
  def dispatch_to_focused_or_ignore(hierarchy, {:key, _, _} = event), do: dispatch_to_focused(hierarchy, event)
  def dispatch_to_focused_or_ignore(hierarchy, {:char, _} = event), do: dispatch_to_focused(hierarchy, event)
  def dispatch_to_focused_or_ignore(hierarchy, _), do: {hierarchy, []}

  def handle_event_consumed(hierarchy, event) do
    hierarchy = sync_focused_pid_state(hierarchy)
    {new_hierarchy, actions} = handle_event(hierarchy, event)
    consumed = actions != [] or
               new_hierarchy.focused_widget != hierarchy.focused_widget or
               :erlang.phash2(new_hierarchy.widgets) != :erlang.phash2(hierarchy.widgets)
    {new_hierarchy, actions, consumed}
  end

  def sync_focused_pid_state(hierarchy) do
    case hierarchy.focused_widget && Map.get(hierarchy.widgets, hierarchy.focused_widget) do
      %{pid: pid} = info when not is_nil(pid) ->
        WidgetHierarchy.put_widget(hierarchy, hierarchy.focused_widget, %{info | state: WidgetServer.get_state(pid)})

      _ ->
        hierarchy
    end
  end

  def dispatch_to_focused(hierarchy, semantic_event) do
    case hierarchy.focused_widget do
      nil ->
        {hierarchy, []}

      widget_id ->
        handle_event_with_phases(hierarchy, widget_id, semantic_event)
    end
  end

  def handle_event_with_phases(hierarchy, target_id, tuple_event) do
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

  def handle_widget_event(hierarchy, widget_id, event) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        {hierarchy, []}

      widget_info ->
        dispatch_widget_event(hierarchy, widget_id, widget_info, event)
    end
  end

  def dispatch_widget_event(hierarchy, widget_id, widget_info, event) do
    case try_handle_event(widget_info, event) do
      {new_state, actions, :stop} ->
        {WidgetHierarchy.set_widget_state(hierarchy, widget_id, new_state), actions}

      {new_state, actions, :bubble} ->
        new_hierarchy = WidgetHierarchy.set_widget_state(hierarchy, widget_id, new_state)
        bubble_to_parent(new_hierarchy, widget_info.parent, event, actions)

      :not_handled ->
        bubble_to_parent(hierarchy, widget_info.parent, event, [])
    end
  end

  def bubble_to_parent(hierarchy, nil, _event, actions), do: {hierarchy, actions}

  def bubble_to_parent(hierarchy, parent_id, event, actions) do
    {final_hierarchy, parent_actions} = handle_widget_event(hierarchy, parent_id, event)
    {final_hierarchy, actions ++ parent_actions}
  end

  def try_handle_event(%{pid: pid} = widget_info, event) when is_pid(pid) do
    WidgetServer.send_event_sync(pid, event)
    |> Drafter.EventResult.parse(widget_info.state)
  end

  def try_handle_event(widget_info, event) do
    if function_exported?(widget_info.module, :handle_event, 2) do
      widget_info.module.handle_event(event, widget_info.state)
      |> Drafter.EventResult.parse(widget_info.state)
    else
      :not_handled
    end
  end

  def build_ancestor_path(hierarchy, widget_id, acc \\ []) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> Enum.reverse(acc)
      %{parent: nil} -> Enum.reverse([widget_id | acc])
      %{parent: parent_id} -> build_ancestor_path(hierarchy, parent_id, [widget_id | acc])
    end
  end

  def try_handle_event_capture(%{pid: pid} = widget_info, event) when is_pid(pid) do
    if function_exported?(widget_info.module, :handle_event_capture, 2) do
      WidgetServer.call_capture_handler(pid, event)
      |> classify_capture_result(event, widget_info.state)
    else
      {:continue, event, widget_info.state}
    end
  end

  def try_handle_event_capture(widget_info, event) do
    if function_exported?(widget_info.module, :handle_event_capture, 2) do
      widget_info.module.handle_event_capture(event, widget_info.state)
      |> classify_capture_result(event, widget_info.state)
    else
      {:continue, event, widget_info.state}
    end
  end

  def classify_capture_result({:continue, updated_event, new_state}, _event, _fallback_state) do
    {:continue, updated_event, new_state}
  end

  def classify_capture_result({:stop, updated_event, new_state, actions}, _event, _fallback_state) do
    {:stop, Event.Object.stop_propagation(updated_event), new_state, actions}
  end

  def classify_capture_result({:prevent, updated_event, new_state}, _event, _fallback_state) do
    stopped = updated_event |> Event.Object.prevent_default() |> Event.Object.stop_propagation()
    {:stop, stopped, new_state, []}
  end

  def classify_capture_result(_, event, fallback_state) do
    {:continue, event, fallback_state}
  end

  def dispatch_capture_phase(hierarchy, event, path) do
    Enum.reduce_while(path, {hierarchy, event, []}, fn widget_id, {h, evt, actions} ->
      if evt.immediate_propagation_stopped do
        {:halt, {h, evt, actions}}
      else
        process_capture_widget(h, widget_id, evt, actions)
      end
    end)
  end

  def process_capture_widget(h, widget_id, evt, actions) do
    case Map.get(h.widgets, widget_id) do
      nil ->
        {:cont, {h, evt, actions}}

      widget_info ->
        evt = %{evt | current_target: widget_id, phase: :capture}

        case try_handle_event_capture(widget_info, evt) do
          {:continue, updated_event, new_state} ->
            {:cont, {WidgetHierarchy.set_widget_state(h, widget_id, new_state), updated_event, actions}}

          {:stop, updated_event, new_state, new_actions} ->
            {:halt, {WidgetHierarchy.set_widget_state(h, widget_id, new_state), updated_event, actions ++ new_actions}}
        end
    end
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
end
