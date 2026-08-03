defmodule Drafter.WidgetHierarchy.EventRouter do
  @moduledoc """
  Routes an event through a widget hierarchy and collects the actions it produced.

  `handle_event/2` is the entry point. Mouse events go to the mouse router,
  which picks a widget by position. Everything else is treated as a key event and is
  handled in one of three ways:

    * `:tab` and `Shift+Tab` move focus, unless the focused widget has both
      `:focused` and `:trap_focus` set in its state, in which case it receives the key.
    * Arrow keys are offered to directional focus navigation first.
    * Anything else goes to the focused widget. `{:key, _}`, `{:key, _, _}`,
      `{:char, _}` and `{:bracketed_paste, _}` are dispatched; every other shape is
      dropped. Paste text is passed through `Drafter.Clipboard.sanitize/1`.

  ## Dispatch phases

  A dispatched event travels the ancestor path root-first in the `:capture` phase,
  where an ancestor exporting `handle_event_capture/2` may rewrite it, consume it or
  prevent its default. It is then delivered to the target in the `:target` phase. If
  the target does not consume it, it walks back up in the `:bubble` phase, one
  ancestor at a time, until an ancestor consumes it or the root is reached.

  The event is an `Drafter.Event.Object` while it travels, so phase, target and
  propagation flags are available to capture handlers; it is converted back to a
  tuple before each widget's `handle_event/2` is called.

  Actions returned by widgets are gathered in the order they were produced and
  returned alongside the updated hierarchy.

  A widget backed by a process is asked through the widget's process; one without a
  process has its module's `handle_event/2` called directly, and the result is
  normalised by `Drafter.EventResult.parse/2`.
  """

  alias Drafter.Event
  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetHierarchy.{Focus, Mouse}
  alias Drafter.WidgetServer

  @doc """
  Route `event` through `hierarchy` and return `{hierarchy, actions}`.

  Mouse events are resolved by position; everything else is treated as a key event.
  Actions are in the order the widgets produced them. Use
  `handle_event_consumed/2` when the caller needs to know whether anything acted.
  """
  @spec handle_event(WidgetHierarchy.t(), term()) :: {WidgetHierarchy.t(), [term()]}
  def handle_event(hierarchy, {:mouse, mouse_event}) do
    Mouse.handle_mouse_event(hierarchy, mouse_event)
  end

  def handle_event(hierarchy, event), do: handle_key_event(hierarchy, event)

  @doc """
  Route a non-mouse event: focus movement first, then the focused widget.

  `Tab` and `Shift+Tab`, in both their `:tab` and `?\\t` spellings, cycle focus
  forwards and backwards unless the focused widget traps focus. Arrow keys are
  offered to directional navigation, which falls back to the focused widget when no
  neighbour is found. Returns `{hierarchy, actions}`.
  """
  def handle_key_event(hierarchy, {:key, :tab} = event) do
    if focused_widget_traps_tab?(hierarchy),
      do: dispatch_to_focused(hierarchy, event),
      else: {Focus.cycle_focus(hierarchy), []}
  end

  def handle_key_event(hierarchy, {:key, :tab, _} = event) do
    if focused_widget_traps_tab?(hierarchy),
      do: dispatch_to_focused(hierarchy, event),
      else: {Focus.cycle_focus_reverse(hierarchy), []}
  end

  def handle_key_event(hierarchy, {:key, ?\t} = event) do
    if focused_widget_traps_tab?(hierarchy),
      do: dispatch_to_focused(hierarchy, event),
      else: {Focus.cycle_focus(hierarchy), []}
  end

  def handle_key_event(hierarchy, {:key, ?\t, mods} = event) when is_list(mods) do
    if focused_widget_traps_tab?(hierarchy) do
      dispatch_to_focused(hierarchy, event)
    else
      if :shift in mods,
        do: {Focus.cycle_focus_reverse(hierarchy), []},
        else: {Focus.cycle_focus(hierarchy), []}
    end
  end

  def handle_key_event(hierarchy, {:key, dir} = event) when dir in [:left, :right, :up, :down] do
    Focus.try_arrow_navigation(hierarchy, event, dir)
  end

  def handle_key_event(hierarchy, {:key, dir, _} = event)
      when dir in [:left, :right, :up, :down] do
    Focus.try_arrow_navigation(hierarchy, event, dir)
  end

  def handle_key_event(hierarchy, event), do: dispatch_to_focused_or_ignore(hierarchy, event)

  @doc """
  Dispatch `event` to the focused widget, or drop it.

  `{:key, _}`, `{:key, _, _}`, `{:char, _}` and `{:bracketed_paste, _}` are
  dispatched; paste text is sanitized first. Every other shape returns the
  hierarchy unchanged with no actions.
  """
  def dispatch_to_focused_or_ignore(hierarchy, {:key, _} = event),
    do: dispatch_to_focused(hierarchy, event)

  def dispatch_to_focused_or_ignore(hierarchy, {:key, _, _} = event),
    do: dispatch_to_focused(hierarchy, event)

  def dispatch_to_focused_or_ignore(hierarchy, {:char, _} = event),
    do: dispatch_to_focused(hierarchy, event)

  def dispatch_to_focused_or_ignore(hierarchy, {:bracketed_paste, text}) do
    dispatch_to_focused(hierarchy, {:bracketed_paste, Drafter.Clipboard.sanitize(text)})
  end

  def dispatch_to_focused_or_ignore(hierarchy, _), do: {hierarchy, []}

  @doc """
  Route an event and report whether anything in the hierarchy acted on it.

  Returns `{hierarchy, actions, consumed?}`. The event counts as consumed if it
  produced actions, moved focus, or was marked consumed by a widget that stopped
  propagation.
  """
  @spec handle_event_consumed(WidgetHierarchy.t(), term()) ::
          {WidgetHierarchy.t(), [term()], boolean()}
  def handle_event_consumed(hierarchy, event) do
    hierarchy = WidgetHierarchy.clear_consumed(hierarchy)
    {new_hierarchy, actions} = handle_event(hierarchy, event)

    consumed =
      actions != [] or
        new_hierarchy.focused_widget != hierarchy.focused_widget or
        new_hierarchy.event_consumed

    {WidgetHierarchy.clear_consumed(new_hierarchy), actions, consumed}
  end

  @doc """
  Refresh the cached copy of the focused widget's state from its process.

  Returns the hierarchy unchanged when nothing is focused, when the focused widget
  has no process, or when that process does not answer.
  """
  def sync_focused_pid_state(hierarchy) do
    case hierarchy.focused_widget && Map.get(hierarchy.widgets, hierarchy.focused_widget) do
      %{pid: pid} = info when not is_nil(pid) ->
        fresh = WidgetServer.safe_get_state(pid) || info.state
        WidgetHierarchy.put_widget(hierarchy, hierarchy.focused_widget, %{info | state: fresh})

      _ ->
        hierarchy
    end
  end

  @trap_focus_fields [:focused, :trap_focus]

  defp focused_widget_fields(hierarchy) do
    case hierarchy.focused_widget && Map.get(hierarchy.widgets, hierarchy.focused_widget) do
      %{pid: pid} when is_pid(pid) -> WidgetServer.get_state_fields(pid, @trap_focus_fields)
      %{state: state} when is_map(state) -> state
      _ -> %{}
    end
  end

  @doc """
  Send `semantic_event` through the phase pipeline with the focused widget as target.

  Returns `{hierarchy, []}` when no widget is focused.
  """
  def dispatch_to_focused(hierarchy, semantic_event) do
    case hierarchy.focused_widget do
      nil ->
        {hierarchy, []}

      widget_id ->
        handle_event_with_phases(hierarchy, widget_id, semantic_event)
    end
  end

  @doc """
  Run `tuple_event` through the capture and target phases with `target_id` as target.

  The event is converted to a `Drafter.Event.Object`, timestamped, and offered to
  each ancestor from the root down. If a capture handler stopped propagation the
  target is never called and only the capture actions are returned. Otherwise the
  target handles it, which may start the bubble phase. Returns
  `{hierarchy, actions}` with capture actions before target actions.
  """
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

  @doc """
  Offer `event` to the widget registered as `widget_id`.

  Returns `{hierarchy, []}` for an unknown id. Otherwise see
  `dispatch_widget_event/4`.
  """
  def handle_widget_event(hierarchy, widget_id, event) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        {hierarchy, []}

      widget_info ->
        dispatch_widget_event(hierarchy, widget_id, widget_info, event)
    end
  end

  @doc """
  Offer `event` to a widget whose registration record is already in hand.

  A `:stop` result stores the widget's new state and marks the hierarchy's event as
  consumed. A `:bubble` result stores the state and continues up the ancestor chain.
  `:not_handled` leaves the state alone and continues up. Returns
  `{hierarchy, actions}`.
  """
  def dispatch_widget_event(hierarchy, widget_id, widget_info, event) do
    case try_handle_event(widget_info, event) do
      {new_state, actions, :stop} ->
        hierarchy = WidgetHierarchy.set_widget_state(hierarchy, widget_id, new_state)
        {WidgetHierarchy.mark_consumed(hierarchy), actions}

      {new_state, actions, :bubble} ->
        hierarchy
        |> WidgetHierarchy.set_widget_state(widget_id, new_state)
        |> bubble_to_parent(widget_info.parent, event, actions)

      :not_handled ->
        bubble_to_parent(hierarchy, widget_info.parent, event, [])
    end
  end

  @doc """
  Walk an unhandled event up the ancestor chain.

  Each ancestor is dispatched with `:phase` set to `:bubble` and
  `:current_target` set to itself. The walk ends at the root, or at the first
  ancestor that stops propagation. Returns the updated hierarchy and the actions
  gathered along the way, in the order they were produced.
  """
  @spec bubble_to_parent(WidgetHierarchy.t(), term(), term(), [term()]) ::
          {WidgetHierarchy.t(), [term()]}
  def bubble_to_parent(hierarchy, parent_id, event, actions) do
    {final_hierarchy, reversed} =
      bubble_up(hierarchy, parent_id, Drafter.Event.from_tuple(event), Enum.reverse(actions))

    {final_hierarchy, Enum.reverse(reversed)}
  end

  defp bubble_up(hierarchy, nil, _event, acc), do: {hierarchy, acc}

  defp bubble_up(hierarchy, widget_id, event, acc) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil ->
        {hierarchy, acc}

      widget_info ->
        event = %{event | phase: :bubble, current_target: widget_id}
        dispatch_bubble_step(hierarchy, widget_id, widget_info, event, acc)
    end
  end

  defp dispatch_bubble_step(hierarchy, widget_id, widget_info, event, acc) do
    tuple = Drafter.Event.to_tuple(event)

    case try_handle_event(widget_info, tuple) do
      {new_state, actions, :stop} ->
        updated =
          hierarchy
          |> WidgetHierarchy.set_widget_state(widget_id, new_state)
          |> WidgetHierarchy.mark_consumed()

        {updated, prepend_reversed(actions, acc)}

      {new_state, actions, :bubble} ->
        updated = WidgetHierarchy.set_widget_state(hierarchy, widget_id, new_state)
        continue_bubble(updated, widget_info.parent, event, prepend_reversed(actions, acc))

      :not_handled ->
        continue_bubble(hierarchy, widget_info.parent, event, acc)
    end
  end

  defp continue_bubble(hierarchy, parent_id, event, acc) do
    if event.propagation_stopped do
      {hierarchy, acc}
    else
      bubble_up(hierarchy, parent_id, event, acc)
    end
  end

  defp prepend_reversed(items, acc), do: Enum.reduce(items, acc, &[&1 | &2])

  @doc """
  Ask one widget to handle `event`, in whichever way that widget is backed.

  A widget with a process is asked through the widget's process, which owns its
  state; the cached copy in the hierarchy is returned unchanged. A widget without
  one has its module's `handle_event/2` called and the return normalised by
  `Drafter.EventResult.parse/2`.

  Returns `{new_state, actions, :stop | :bubble}`, or `:not_handled` when the widget
  did not act or exports no `handle_event/2`.
  """
  def try_handle_event(%{pid: pid, state: cached}, event) when is_pid(pid) do
    case WidgetServer.dispatch_event(pid, event) do
      {:not_handled, _actions} -> :not_handled
      {mode, actions} -> {cached, actions, mode}
    end
  end

  def try_handle_event(widget_info, event) do
    if function_exported?(widget_info.module, :handle_event, 2) do
      widget_info.module.handle_event(event, widget_info.state)
      |> Drafter.EventResult.parse(widget_info.state)
    else
      :not_handled
    end
  end

  @doc """
  The chain of widget ids from the root down to `widget_id`, inclusive.

  This is the order the capture phase visits. Returns `[]` for an unknown id.
  `acc` is the accumulator of the walk and callers pass nothing for it.
  """
  def build_ancestor_path(hierarchy, widget_id, acc \\ []) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> Enum.reverse(acc)
      %{parent: nil} -> Enum.reverse([widget_id | acc])
      %{parent: parent_id} -> build_ancestor_path(hierarchy, parent_id, [widget_id | acc])
    end
  end

  @doc """
  Offer `event` to one widget's `handle_event_capture/2`.

  `event` is a `Drafter.Event.Object`. A widget that does not export the callback
  returns `{:continue, event, state}` unchanged. See `classify_capture_result/3` for
  the shapes a capture handler may return.
  """
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

  @doc """
  Normalise what a `handle_event_capture/2` returned.

  Accepted returns and their results:

    * `{:continue, event, state}` → passed through; the event carries on down
    * `{:stop, event, state, actions}` → `{:stop, event_with_propagation_stopped,
      state, actions}`
    * `{:prevent, event, state}` → `{:stop, event_with_default_prevented_and_
      propagation_stopped, state, []}`

  Anything else yields `{:continue, event, fallback_state}`, discarding whatever the
  handler returned. `event` and `fallback_state` are the values to fall back to.
  """
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

  @doc """
  Walk `event` down `path`, offering it to each widget's capture handler.

  `path` runs root-first, as `build_ancestor_path/3` returns it. The walk ends early
  when a handler stops propagation or has already stopped immediate propagation.
  Returns `{hierarchy, event, actions}` with the event as the handlers left it.
  """
  def dispatch_capture_phase(hierarchy, event, path) do
    Enum.reduce_while(path, {hierarchy, event, []}, fn widget_id, {h, evt, actions} ->
      if evt.immediate_propagation_stopped do
        {:halt, {h, evt, actions}}
      else
        process_capture_widget(h, widget_id, evt, actions)
      end
    end)
  end

  @doc """
  Run one step of the capture walk over the widget `widget_id`.

  Sets the event's `:current_target` and `:phase` before calling the widget's
  capture handler. Returns a `Enum.reduce_while/3` instruction: `{:cont, acc}` to
  keep walking down, `{:halt, acc}` when the widget stopped the event, where `acc`
  is `{hierarchy, event, actions}`. An unknown id is skipped.
  """
  def process_capture_widget(h, widget_id, evt, actions) do
    case Map.get(h.widgets, widget_id) do
      nil ->
        {:cont, {h, evt, actions}}

      widget_info ->
        evt = %{evt | current_target: widget_id, phase: :capture}

        case try_handle_event_capture(widget_info, evt) do
          {:continue, updated_event, new_state} ->
            {:cont,
             {WidgetHierarchy.set_widget_state(h, widget_id, new_state), updated_event, actions}}

          {:stop, updated_event, new_state, new_actions} ->
            stopped =
              h
              |> WidgetHierarchy.set_widget_state(widget_id, new_state)
              |> WidgetHierarchy.mark_consumed()

            {:halt, {stopped, updated_event, actions ++ new_actions}}
        end
    end
  end

  @doc """
  Offer `event` to every widget in the hierarchy, without phases.

  Widgets are visited in map order, which is not the tree order, and each one may
  bubble the event to its parent. Returns `{hierarchy, actions}` with the actions
  concatenated in visit order.
  """
  def broadcast_event(hierarchy, event) do
    Enum.reduce(hierarchy.widgets, {hierarchy, []}, fn {widget_id, _widget_info}, {h, actions} ->
      {new_h, new_actions} = send_event_to_widget(h, widget_id, event)
      {new_h, actions ++ new_actions}
    end)
  end

  @doc "Offer `event` to a single widget by id, without phases."
  def send_event_to_widget(hierarchy, widget_id, event) do
    handle_widget_event(hierarchy, widget_id, event)
  end

  defp focused_widget_traps_tab?(hierarchy) do
    fields = focused_widget_fields(hierarchy)
    Map.get(fields, :focused, false) and Map.get(fields, :trap_focus, false) == true
  end
end
