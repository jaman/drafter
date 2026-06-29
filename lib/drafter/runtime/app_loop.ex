defmodule Drafter.Runtime.AppLoop do
  @moduledoc """
  Application event loop for Drafter.

  Owns the receive loop and all message dispatch logic.
  Calls Drafter.Runtime.Renderer for all rendering.
  """

  alias Drafter.{Compositor, Event, RenderCache, SkinManager, Terminal, ThemeManager}
  alias Drafter.Runtime
  alias Drafter.Runtime.Renderer
  alias Drafter.Widget.SplitPaneDivider

  @scroll_debounce_ms 150

  @spec enter_loop(module(), term(), map(), map(), map() | nil, keyword()) :: :ok
  def enter_loop(
        app_module,
        app_state,
        screen_rect,
        timers \\ %{},
        widget_hierarchy \\ nil,
        opts \\ []
      ) do
    setup_frame_rate(app_module, opts)
    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, [])
  end

  @spec run(module(), keyword()) :: :ok
  def run(app_module, opts \\ []) do
    setup_frame_rate(app_module, opts)
    Drafter.AppRegistry.register()

    ThemeManager.register_app(self())
    SkinManager.register_app(self())
    Drafter.ScreenManager.reset()
    Drafter.ScreenManager.register_app(self())
    Drafter.WidgetStripCache.clear()
    Drafter.Event.Manager.drain_queue()
    Terminal.Driver.drain_pending_input()
    Event.Manager.subscribe(self())
    Drafter.Event.Manager.drain_queue()
    drain_stale_events()
    Terminal.Driver.start_input()
    Process.sleep(50)
    Terminal.Driver.drain_pending_input()
    Drafter.Event.Manager.drain_queue()
    drain_stale_events()
    Compositor.clear_screen()

    initial_props = %{}
    app_state = Runtime.for_app(app_module).mount(app_module, initial_props)

    {width, height} = Terminal.Driver.refresh_size()
    Compositor.resize(width, height)
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)

    Process.put(:pending_intervals, [])
    ready_app_state = Runtime.for_app(app_module).ready(app_module, app_state)
    initial_timers = collect_pending_intervals()
    {_, hierarchy} = Renderer.render_app(app_module, ready_app_state, screen_rect, hierarchy)

    app_event_loop(app_module, ready_app_state, screen_rect, initial_timers, hierarchy, [])
  end

  defp app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack) do
    ctx = {app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack}

    receive do
      msg -> dispatch_loop_msg(msg, ctx)
    end
  end

  defp dispatch_loop_msg({:tui_event, {:resize, {w, h}}}, {app_module, app_state, _rect, timers, wh, ss}) do
    {fw, fh} = drain_pending_resizes(w, h)
    Process.put(:last_resize_ms, System.monotonic_time(:millisecond))
    rect = make_screen_rect(fw, fh)
    RenderCache.invalidate()
    {_, new_wh} = immediate_render(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:tui_event, event}, {app_module, app_state, rect, timers, wh, ss}) do
    Drafter.Trace.log_sync(["I ", Drafter.Trace.ts(), " ", inspect(event), "\n"])

    case check_global_quit(event) do
      :quit -> handle_stop(:normal, app_module, app_state, rect, timers, wh, ss)
      :continue -> handle_continue_event(app_module, app_state, rect, timers, wh, ss, event)
    end
  end

  defp dispatch_loop_msg(:coalesced_render, {app_module, app_state, rect, timers, wh, ss}) do
    {_, new_wh} = do_render(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:app_event, name, data}, {app_module, app_state, rect, timers, wh, ss}) do
    result = Runtime.for_app(app_module).handle_message(app_module, name, data, app_state)

    case result do
      {:stop, reason} -> handle_stop(reason, app_module, app_state, rect, timers, wh, ss)
      _ ->
        new_state = dispatch_app_callback_result(result, app_state)
        {_, new_wh} = immediate_render(app_module, new_state, rect, wh)
        app_event_loop(app_module, new_state, rect, timers, new_wh, ss)
    end
  end

  defp dispatch_loop_msg({:bound_state_update, key, value}, {app_module, app_state, rect, timers, wh, ss}) do
    new_state = Map.put(app_state, key, value)
    {_, new_wh} = immediate_render(app_module, new_state, rect, wh)
    app_event_loop(app_module, new_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:theme_change, name}, {app_module, app_state, rect, timers, wh, ss}) do
    ThemeManager.set_theme(name)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:theme_updated, theme}, {app_module, app_state, rect, timers, wh, ss}) do
    new_state =
      case Runtime.for_app(app_module).handle_input(app_module, {:theme_updated, theme}, app_state) do
        {:ok, s} -> s
        {:noreply, s} -> s
        s when is_map(s) -> s
      end

    RenderCache.invalidate()
    {_, new_wh} = immediate_render(app_module, new_state, rect, wh)
    app_event_loop(app_module, new_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:skin_change, name}, {app_module, app_state, rect, timers, wh, ss}) do
    SkinManager.set_skin(name)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:skin_updated, skin}, {app_module, app_state, rect, timers, wh, ss}) do
    Process.put(:drafter_skin, skin)
    RenderCache.invalidate()
    {_, new_wh} = immediate_render(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:timer, timer_id}, {app_module, app_state, rect, timers, wh, ss}) do
    is_parent =
      not Map.has_key?(timers, timer_id) and
        Enum.any?(ss, fn {_, _, _, parent_timers, _, _} -> Map.has_key?(parent_timers, timer_id) end)

    if is_parent do
      app_event_loop(app_module, app_state, rect, timers, wh, ss)
    else
      new_state = Runtime.for_app(app_module).timer(app_module, timer_id, app_state)

      if new_state === app_state do
        app_event_loop(app_module, app_state, rect, timers, wh, ss)
      else
        {_, new_wh} = Renderer.render_app(app_module, new_state, rect, wh)
        app_event_loop(app_module, new_state, rect, timers, new_wh, ss)
      end
    end
  end

  defp dispatch_loop_msg({:set_interval, ms, timer_id}, {app_module, app_state, rect, timers, wh, ss}) do
    {:ok, timer_ref} = :timer.send_interval(ms, {:timer, timer_id})
    app_event_loop(app_module, app_state, rect, Map.put(timers, timer_id, timer_ref), wh, ss)
  end

  defp dispatch_loop_msg({:set_timeout, ms, timer_id}, {app_module, app_state, rect, timers, wh, ss}) do
    Process.send_after(self(), {:timer, timer_id}, ms)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:focus_widget, widget_id}, {app_module, app_state, rect, timers, wh, ss}) do
    new_wh = if wh, do: Drafter.WidgetHierarchy.focus_widget(wh, widget_id), else: wh
    Process.put(:render_cache_layout_dirty, true)
    {_, updated_wh} = immediate_render(app_module, app_state, rect, new_wh)
    app_event_loop(app_module, app_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:widget_event, event}, {app_module, app_state, rect, timers, wh, ss}) when wh != nil do
    {new_wh, _} = Drafter.WidgetHierarchy.broadcast_event(wh, event)
    Process.put(:render_cache_layout_dirty, true)
    {_, updated_wh} = immediate_render(app_module, app_state, rect, new_wh)
    app_event_loop(app_module, app_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:widget_event, _event}, {app_module, app_state, rect, timers, wh, ss}) do
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:widget_event, widget_id, event}, {app_module, app_state, rect, timers, wh, ss}) when wh != nil do
    {new_wh, _} = Drafter.WidgetHierarchy.send_event_to_widget(wh, widget_id, event)
    Process.put(:render_cache_layout_dirty, true)
    {_, updated_wh} = immediate_render(app_module, app_state, rect, new_wh)
    app_event_loop(app_module, app_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:widget_event, _widget_id, _event}, {app_module, app_state, rect, timers, wh, ss}) do
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:widget_render_needed, _id}, {app_module, app_state, rect, timers, wh, ss}) do
    drain_widget_render_notifications()
    Process.put(:render_cache_layout_dirty, true)
    if wh, do: Renderer.render_hierarchy(wh, rect)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg(:scroll_debounce_render, {app_module, app_state, rect, timers, wh, ss}) do
    drain_scroll_debounce_renders()
    Process.delete(:scroll_debounce_ref)
    idle_state = maybe_scroll_idle(app_module, app_state)

    if wh do
      {_, updated_wh} = immediate_render(app_module, idle_state, rect, wh)
      app_event_loop(app_module, idle_state, rect, timers, updated_wh, ss)
    else
      app_event_loop(app_module, idle_state, rect, timers, wh, ss)
    end
  end

  defp dispatch_loop_msg({:widget_action, _, {:theme_change, name}}, {app_module, app_state, rect, timers, wh, ss}) do
    ThemeManager.set_theme(name)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:widget_action, _, {:skin_change, name}}, {app_module, app_state, rect, timers, wh, ss}) do
    SkinManager.set_skin(name)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:widget_action, _, {:app_callback, cb, data}}, {app_module, app_state, rect, timers, wh, ss}) do
    new_state = dispatch_app_callback(app_module, cb, data, app_state)
    {_, updated_wh} = immediate_render(app_module, new_state, rect, wh)
    app_event_loop(app_module, new_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:widget_action, _, _action}, {app_module, app_state, rect, timers, wh, ss}) when wh != nil do
    {_, updated_wh} = immediate_render(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:widget_action, _, _action}, {app_module, app_state, rect, timers, wh, ss}) do
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:activate_widget, widget_id}, {app_module, app_state, rect, timers, wh, ss}) when wh != nil do
    {new_wh, actions} = Drafter.WidgetHierarchy.send_event_to_widget(wh, widget_id, :activate)

    new_state =
      Enum.reduce(actions, app_state, fn
        {:app_callback, cb, data}, acc -> dispatch_app_callback(app_module, cb, data, acc)
        _, acc -> acc
      end)

    {_, updated_wh} = immediate_render(app_module, new_state, rect, new_wh)
    app_event_loop(app_module, new_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg({:activate_widget, _}, {app_module, app_state, rect, timers, wh, ss}) do
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:get_widget_value, widget_id, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    value =
      if wh do
        case Drafter.WidgetHierarchy.get_widget_state(wh, widget_id) do
          nil -> nil
          state -> extract_widget_value(state)
        end
      else
        nil
      end

    send(caller, {:widget_value, widget_id, value})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:get_widget_state, widget_id, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    state = if wh, do: Drafter.WidgetHierarchy.get_widget_state(wh, widget_id), else: nil
    send(caller, {:widget_state, widget_id, state})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:query_one, selector, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    result = if wh, do: Drafter.WidgetHierarchy.query_one(wh, selector), else: nil
    send(caller, {:query_result, :one, result})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:query_all, selector, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    result = if wh, do: Drafter.WidgetHierarchy.query_all(wh, selector), else: []
    send(caller, {:query_result, :all, result})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:validate_widget, widget_id, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    result = validate_widget_in_hierarchy(wh, widget_id)
    send(caller, {:validation_result, widget_id, result})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:get_animated_property, widget_id, prop, caller}, {app_module, app_state, rect, timers, wh, ss}) do
    value =
      if wh do
        case Drafter.WidgetHierarchy.get_widget_state(wh, widget_id) do
          nil -> nil
          state -> get_animated_property_from_state(state, prop)
        end
      else
        nil
      end

    send(caller, {:animated_property, widget_id, prop, value})
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:apply_animation, widget_id, prop, value}, {app_module, app_state, rect, timers, wh, ss}) when wh != nil do
    case Drafter.WidgetHierarchy.get_widget_info(wh, widget_id) do
      nil ->
        app_event_loop(app_module, app_state, rect, timers, wh, ss)

      widget_info ->
        new_wh = Drafter.WidgetHierarchy.update_widget_state(wh, widget_id, apply_animated_property(widget_info.state, prop, value))
        {_, final_wh} = throttled_render(app_module, app_state, rect, new_wh)
        app_event_loop(app_module, app_state, rect, timers, final_wh, ss)
    end
  end

  defp dispatch_loop_msg({:apply_animation, _, _, _}, {app_module, app_state, rect, timers, wh, ss}) do
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg(:animation_tick, {app_module, app_state, rect, timers, wh, ss}) do
    {_, updated_wh} = throttled_render(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, updated_wh, ss)
  end

  defp dispatch_loop_msg(:screen_render_needed, {app_module, app_state, rect, timers, wh, ss}) do
    Renderer.render_screens_from_manager(rect, app_module, app_state, wh)
    app_event_loop(app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:__drafter_stop__, reason}, {app_module, app_state, rect, timers, wh, ss}) do
    handle_stop(reason, app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg({:push_session, new_module, opts, action_handlers, from_pid, ref}, {app_module, app_state, rect, timers, wh, ss}) do
    RenderCache.invalidate()
    mount_props = opts |> Keyword.drop([:scroll_optimization, :syntax_highlighting, :refresh_rate]) |> Map.new()
    setup_frame_rate(new_module, opts)
    prev_handlers = Drafter.ActionRegistry.collect()
    Drafter.ActionRegistry.init(action_handlers)
    new_state = Runtime.for_app(new_module).mount(new_module, mount_props)
    {_, new_wh} = Renderer.render_app(new_module, new_state, rect)
    Process.put(:pending_intervals, [])
    ready_state = Runtime.for_app(new_module).ready(new_module, new_state)
    initial_timers = collect_pending_intervals()
    drain_stale_events()
    {_, new_wh} = Renderer.render_app(new_module, ready_state, rect, new_wh)
    current = {app_module, app_state, wh, timers, from_pid, ref, prev_handlers}
    app_event_loop(new_module, ready_state, rect, initial_timers, new_wh, [current | ss])
  end

  defp dispatch_loop_msg(:deferred_render, {app_module, app_state, rect, timers, wh, ss}) do
    Process.delete(:render_deferred)
    Process.put(:last_render_ms, System.monotonic_time(:millisecond))
    {_, new_wh} = Renderer.render_app(app_module, app_state, rect, wh)
    app_event_loop(app_module, app_state, rect, timers, new_wh, ss)
  end

  defp dispatch_loop_msg({:EXIT, _pid, _reason}, {app_module, app_state, rect, timers, wh, ss}) do
    handle_stop(:normal, app_module, app_state, rect, timers, wh, ss)
  end

  defp dispatch_loop_msg(:shutdown, _ctx), do: :ok

  defp dispatch_loop_msg(other, {app_module, app_state, rect, timers, wh, ss}) do
    new_state = maybe_on_message(app_module, other, app_state)

    if new_state === app_state do
      app_event_loop(app_module, app_state, rect, timers, wh, ss)
    else
      {_, new_wh} = immediate_render(app_module, new_state, rect, wh)
      app_event_loop(app_module, new_state, rect, timers, new_wh, ss)
    end
  end

  defp handle_continue_event(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event) do
    if Drafter.ScreenManager.get_all_screens() != [] do
      Drafter.EventHandler.dispatch_event_sync(event)
      handle_post_screen_dispatch(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
    else
      handle_no_screens_event(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event)
    end
  end

  defp handle_post_screen_dispatch(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack) do
    if Drafter.ScreenManager.get_all_screens() == [] do
      {_, fresh_hierarchy} = immediate_render(app_module, app_state, screen_rect, widget_hierarchy)
      app_event_loop(app_module, app_state, screen_rect, timers, fresh_hierarchy, session_stack)
    else
      render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
    end
  end

  defp handle_no_screens_event(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event) do
    {new_hierarchy, actions, widget_consumed} =
      if widget_hierarchy && widget_hierarchy.focused_widget do
        Drafter.WidgetHierarchy.handle_event_consumed(widget_hierarchy, event)
      else
        {widget_hierarchy, [], false}
      end

    raw_mouse_event? = match?({:mouse, _}, event)

    if widget_consumed do
      handle_widget_consumed(
        app_module, app_state, screen_rect, timers, new_hierarchy,
        session_stack, actions, {event, raw_mouse_event?}
      )
    else
      dispatch_app_event(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event)
    end
  end

  defp handle_widget_consumed(app_module, app_state, screen_rect, timers, new_hierarchy, session_stack, actions, {event, raw_mouse_event?}) do
    Process.put(:render_cache_layout_dirty, true)
    {needs_layout, layout_direction} = RenderCache.extract_layout_impact(actions)

    new_app_state =
      Enum.reduce(actions, app_state, fn
        {:app_callback, callback, data}, acc_state ->
          dispatch_app_callback(app_module, callback, data, acc_state)
        _, acc_state ->
          acc_state
      end)

    has_app_callback = Enum.any?(actions, &match?({:app_callback, _, _}, &1))
    post_widget_state = maybe_passthrough_mouse(app_module, event, new_app_state, raw_mouse_event?, has_app_callback)

    divider_mode = find_divider_mode(actions)

    cond do
      divider_mode == :quick ->
        moved_hierarchy = move_divider_rect(new_hierarchy)
        Renderer.render_hierarchy(moved_hierarchy, screen_rect)
        app_event_loop(app_module, post_widget_state, screen_rect, timers, moved_hierarchy, session_stack)

      needs_layout ->
        clear_divider_origins()
        scoped_invalidate_for_layout(layout_direction, screen_rect)
        updated_h = Renderer.update_hierarchy_preferred_sizes(new_hierarchy)
        {_, done_h} = immediate_render(app_module, post_widget_state, screen_rect, updated_h)
        app_event_loop(app_module, post_widget_state, screen_rect, timers, done_h, session_stack)

      :scroll_fast_render in actions and scroll_optimization_enabled?() ->
        scrolled_app_state = maybe_scroll_active(app_module, post_widget_state)
        Renderer.render_hierarchy(new_hierarchy, screen_rect)
        reschedule_scroll_debounce()
        app_event_loop(app_module, scrolled_app_state, screen_rect, timers, new_hierarchy, session_stack)

      true ->
        {_, final_hierarchy} = immediate_render(app_module, post_widget_state, screen_rect, new_hierarchy)
        app_event_loop(app_module, post_widget_state, screen_rect, timers, final_hierarchy, session_stack)
    end
  end

  defp maybe_passthrough_mouse(app_module, event, app_state, true = _raw_mouse, false = _has_callback) do
    case Runtime.for_app(app_module).handle_input(app_module, event, app_state) do
      {:ok, s} -> s
      {:noreply, s} -> s
      _ -> app_state
    end
  end

  defp maybe_passthrough_mouse(_app_module, _event, app_state, _raw_mouse, _has_callback), do: app_state

  defp dispatch_app_event(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event) do
    result = Runtime.for_app(app_module).handle_input(app_module, event, app_state)
    apply_app_event_result(result, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, event)
  end

  defp apply_app_event_result({:ok, new_app_state}, app_module, _app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    {_, updated_hierarchy} = immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)
    app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy, session_stack)
  end

  defp apply_app_event_result({:stop, reason}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    handle_stop(reason, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:error, _reason}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:show_modal, screen_module, props, opts}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    Drafter.ScreenManager.show_modal(screen_module, props, opts)
    render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:show_toast, message, opts}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    Drafter.ScreenManager.show_toast(message, opts)
    render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:push, screen_module, props, opts}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    Drafter.ScreenManager.push(screen_module, props, opts)
    render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:replace, screen_module, props, opts}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    Drafter.ScreenManager.replace(screen_module, props, opts)
    render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:pop, result}, app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack, _event) do
    Drafter.ScreenManager.pop(result)
    render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp apply_app_event_result({:noreply, new_app_state}, app_module, _app_state, screen_rect, timers, widget_hierarchy, session_stack, event) do
    handle_noreply_with_hierarchy(
      app_module, new_app_state, screen_rect, timers, widget_hierarchy, session_stack, event
    )
  end

  defp render_screens_and_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack) do
    Renderer.render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
  end

  defp handle_stop(reason, _app_module, _app_state, _screen_rect, timers, widget_hierarchy, []) do
    Drafter.Trace.log_sync(["Q stop_start ", Drafter.Trace.ts(), "\n"])
    cleanup_timers(timers)
    Drafter.Trace.log_sync(["Q timers_done ", Drafter.Trace.ts(), "\n"])
    Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
    Drafter.Trace.log_sync(["Q servers_stopped ", Drafter.Trace.ts(), "\n"])
    if reason == :normal, do: :ok, else: {:error, reason}
  end

  defp handle_stop(_reason, _app_module, _app_state, screen_rect, timers, widget_hierarchy, session_stack) do
    {prev_module, prev_state, prev_hierarchy, prev_timers, prev_from, prev_ref, prev_handlers} = hd(session_stack)
    cleanup_timers(timers)
    Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
    Drafter.ScreenManager.reset()
    if prev_from, do: send(prev_from, {:session_result, prev_ref, :ok})
    Drafter.ActionRegistry.init(prev_handlers)
    {_, restored_hierarchy} = Renderer.render_app(prev_module, prev_state, screen_rect, prev_hierarchy)
    app_event_loop(prev_module, prev_state, screen_rect, prev_timers, restored_hierarchy, tl(session_stack))
  end

  defp handle_noreply_with_hierarchy(
         app_module,
         app_state,
         screen_rect,
         timers,
         widget_hierarchy,
         session_stack,
         event
       ) do
    {new_hierarchy, widget_handled, needs_rerender, actions} =
      resolve_hierarchy_event(widget_hierarchy, event)

    {needs_layout, layout_direction} = RenderCache.extract_layout_impact(actions)

    updated_hierarchy =
      if needs_layout do
        Process.put(:render_cache_layout_dirty, true)
        scoped_invalidate_for_layout(layout_direction, screen_rect)
        Renderer.update_hierarchy_preferred_sizes(new_hierarchy)
      else
        new_hierarchy
      end

    if widget_handled, do: Process.put(:render_cache_layout_dirty, true)

    new_app_state =
      Enum.reduce(actions, app_state, fn
        {:app_callback, callback, data}, acc_state ->
          dispatch_app_callback(app_module, callback, data, acc_state)
        _, acc_state ->
          acc_state
      end)

    if needs_rerender or widget_handled do
      {_, final_hierarchy} = immediate_render(app_module, new_app_state, screen_rect, updated_hierarchy)
      app_event_loop(app_module, new_app_state, screen_rect, timers, final_hierarchy, session_stack)
    else
      app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy, session_stack)
    end
  end

  defp resolve_hierarchy_event(nil, _event), do: {nil, false, false, []}

  defp resolve_hierarchy_event(widget_hierarchy, event) do
    case Drafter.WidgetHierarchy.handle_event(widget_hierarchy, event) do
      {hierarchy, []} ->
        changed = hierarchy.focused_widget != widget_hierarchy.focused_widget
        {hierarchy, changed, changed, []}
      {hierarchy, actions} ->
        {hierarchy, true, true, actions}
    end
  end

  defp dispatch_app_callback(app_module, callback, data, acc_state) do
    result = Runtime.for_app(app_module).handle_message(app_module, callback, data, acc_state)
    dispatch_app_callback_result(result, acc_state)
  end

  defp dispatch_app_callback_result(result, acc_state) do
    case result do
      {:stop, reason} ->
        send(self(), {:__drafter_stop__, reason})
        acc_state

      _ ->
        Drafter.ActionRegistry.dispatch(result, acc_state)
    end
  end

  defp extract_widget_value(%{text: text}), do: text
  defp extract_widget_value(%{checked: checked}), do: checked
  defp extract_widget_value(%{state: s}) when s in [:on, :off], do: s == :on
  defp extract_widget_value(%{selected_index: idx, options: options}),
    do: option_id_at(options, idx)
  defp extract_widget_value(%{selected_indices: indices, options: options}) do
    indices
    |> MapSet.to_list()
    |> Enum.map(&option_id_at(options, &1))
    |> Enum.reject(&is_nil/1)
  end
  defp extract_widget_value(%{expanded: expanded}), do: expanded
  defp extract_widget_value(%{active_tab: tab}), do: tab
  defp extract_widget_value(%{selected_rows: rows}), do: MapSet.to_list(rows)
  defp extract_widget_value(%{selected_nodes: nodes}), do: MapSet.to_list(nodes)
  defp extract_widget_value(_state), do: nil

  defp option_id_at(options, idx) do
    case Enum.at(options, idx) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp get_animated_property_from_state(state, property) do
    case property do
      :opacity -> Map.get(state, :opacity, 1.0)
      :background -> get_in(state, [:style, :bg]) || Map.get(state, :bg)
      :color -> get_in(state, [:style, :fg]) || Map.get(state, :fg)
      :offset_x -> Map.get(state, :offset_x, 0)
      :offset_y -> Map.get(state, :offset_y, 0)
      _ -> nil
    end
  end

  defp apply_animated_property(state, property, value) do
    case property do
      :opacity ->
        Map.put(state, :opacity, value)

      :background ->
        put_in(state, [:style, :bg], value)

      :color ->
        put_in(state, [:style, :fg], value)

      :offset_x ->
        Map.put(state, :offset_x, value)

      :offset_y ->
        Map.put(state, :offset_y, value)

      _ ->
        state
    end
  end

  defp check_global_quit(event) do
    case event do
      %{type: :key, key: :q, modifiers: [:ctrl]} -> :quit
      {:key, :q, [:ctrl]} -> :quit
      _ -> :continue
    end
  end

  defp cleanup_timers(timers) do
    Enum.each(timers, fn {_id, timer_ref} ->
      :timer.cancel(timer_ref)
    end)
  end

  defp reschedule_scroll_debounce do
    case Process.get(:scroll_debounce_ref) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    new_ref = Process.send_after(self(), :scroll_debounce_render, @scroll_debounce_ms)
    Process.put(:scroll_debounce_ref, new_ref)
  end

  defp drain_pending_resizes(w, h) do
    receive do
      {:tui_event, {:resize, {nw, nh}}} -> drain_pending_resizes(nw, nh)
    after
      0 -> {w, h}
    end
  end

  defp drain_stale_events do
    receive do
      {:tui_event, _} -> drain_stale_events()
      {:widget_render_needed, _} -> drain_stale_events()
      {:widget_action, _, _} -> drain_stale_events()
      {:activate_widget, _} -> drain_stale_events()
      {:__drafter_stop__, _} -> drain_stale_events()
      :screen_render_needed -> drain_stale_events()
      :scroll_debounce_render -> drain_stale_events()
      {:timer, _} -> drain_stale_events()
    after
      0 -> :ok
    end
  end

  defp drain_widget_render_notifications do
    receive do
      {:widget_render_needed, _} -> drain_widget_render_notifications()
    after
      0 -> :ok
    end
  end

  defp drain_scroll_debounce_renders do
    receive do
      :scroll_debounce_render -> drain_scroll_debounce_renders()
    after
      0 -> :ok
    end
  end

  defp validate_widget_in_hierarchy(nil, _widget_id), do: :ok

  defp validate_widget_in_hierarchy(wh, widget_id) do
    {new_wh, _} = Drafter.WidgetHierarchy.send_event_to_widget(wh, widget_id, :validate)
    state = Drafter.WidgetHierarchy.get_widget_state(new_wh, widget_id)
    error = if state, do: Map.get(state, :error), else: nil
    if error, do: {:error, error}, else: :ok
  end

  defp scroll_optimization_enabled?, do: Process.get(:scroll_optimization, true) != false

  defp maybe_on_message(app_module, msg, app_state) do
    Runtime.for_app(app_module).on_message(app_module, msg, app_state)
  end

  defp maybe_scroll_active(app_module, app_state) do
    if Process.get(:scroll_gesture_active) do
      app_state
    else
      Process.put(:scroll_gesture_active, true)
      Runtime.for_app(app_module).scroll_active(app_module, app_state)
    end
  end

  defp maybe_scroll_idle(app_module, app_state) do
    Process.delete(:scroll_gesture_active)
    Runtime.for_app(app_module).scroll_idle(app_module, app_state)
  end

  defp make_screen_rect(width, height) do
    %{x: 0, y: 0, width: width, height: height}
  end

  defp setup_frame_rate(app_module, opts) do
    rate =
      Keyword.get(opts, :refresh_rate) ||
        Runtime.for_app(app_module).refresh_rate(app_module) ||
        "30fps"

    interval = parse_refresh_rate(rate)
    Process.put(:frame_interval_ms, interval)
    Drafter.AppRegistry.set_frame_interval(interval)
    Process.delete(:last_render_ms)
    Process.delete(:render_deferred)
  end

  defp parse_refresh_rate(:unlimited), do: nil
  defp parse_refresh_rate(n) when is_integer(n) and n > 0, do: n

  defp parse_refresh_rate(s) when is_binary(s) do
    cond do
      s == "unlimited" ->
        nil

      Regex.match?(~r/^\d+(\.\d+)?\s*fps$/i, s) ->
        [fps_str] = Regex.run(~r/[\d.]+/, s)

        fps =
          if String.contains?(fps_str, "."),
            do: String.to_float(fps_str),
            else: String.to_integer(fps_str)

        round(1000 / fps)

      true ->
        raise ArgumentError, "invalid refresh_rate: #{inspect(s)}"
    end
  end

  defp collect_pending_intervals do
    pending = Process.delete(:pending_intervals) || []

    Enum.reduce(pending, %{}, fn {interval_ms, timer_id}, acc ->
      {:ok, timer_ref} = :timer.send_interval(interval_ms, {:timer, timer_id})
      Map.put(acc, timer_id, timer_ref)
    end)
  end

  defp immediate_render(app_module, app_state, screen_rect, hierarchy) do
    if pending_messages?() do
      schedule_coalesced_render()
      {nil, hierarchy}
    else
      do_render(app_module, app_state, screen_rect, hierarchy)
    end
  end

  defp do_render(app_module, app_state, screen_rect, hierarchy) do
    Process.delete(:coalesced_render_scheduled)
    Process.put(:last_render_ms, System.monotonic_time(:millisecond))
    Process.delete(:render_deferred)

    if Drafter.Trace.enabled?() do
      t0 = System.monotonic_time(:microsecond)
      result = Renderer.render_app(app_module, app_state, screen_rect, hierarchy)

      Drafter.Trace.log([
        "R ",
        Drafter.Trace.ts(),
        " render_app_us=",
        Integer.to_string(System.monotonic_time(:microsecond) - t0),
        "\n"
      ])

      result
    else
      Renderer.render_app(app_module, app_state, screen_rect, hierarchy)
    end
  end

  defp schedule_coalesced_render do
    unless Process.get(:coalesced_render_scheduled) do
      Process.put(:coalesced_render_scheduled, true)
      send(self(), :coalesced_render)
    end
  end

  defp pending_messages? do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} -> len > 0
      _ -> false
    end
  end

  defp throttled_render(app_module, app_state, screen_rect, hierarchy) do
    case Process.get(:frame_interval_ms) do
      nil ->
        Renderer.render_app(app_module, app_state, screen_rect, hierarchy)

      interval ->
        now = System.monotonic_time(:millisecond)
        last = Process.get(:last_render_ms, 0)

        if now - last >= interval do
          Process.put(:last_render_ms, now)
          Process.delete(:render_deferred)
          Renderer.render_app(app_module, app_state, screen_rect, hierarchy)
        else
          schedule_deferred_render_if_needed(interval - (now - last))
          {[], hierarchy}
        end
    end
  end

  defp schedule_deferred_render_if_needed(remaining) do
    unless Process.get(:render_deferred) do
      Process.send_after(self(), :deferred_render, remaining)
      Process.put(:render_deferred, true)
    end
  end

  defp move_divider_rect(hierarchy) do
    Enum.reduce(hierarchy.widgets, hierarchy, fn {widget_id, widget_info}, acc ->
      state = widget_info.state

      if widget_info.module == SplitPaneDivider and
           Map.get(state, :dragging, false) do
        apply_divider_delta(acc, widget_id, state)
      else
        acc
      end
    end)
  end

  defp apply_divider_delta(hierarchy, widget_id, state) do
    current_rect = Map.get(hierarchy.widget_rects, widget_id)
    start_pos = Map.get(state, :drag_start_pos)

    if current_rect && start_pos do
      origin_key = {:divider_origin_rect, widget_id}

      origin_rect =
        case Process.get(origin_key) do
          nil ->
            Process.put(origin_key, current_rect)
            current_rect

          rect ->
            rect
        end

      new_pos = SplitPaneDivider.effective_pos(state)
      delta = new_pos - start_pos

      new_rect =
        if state.orientation == :horizontal do
          %{origin_rect | x: origin_rect.x + delta}
        else
          %{origin_rect | y: origin_rect.y + delta}
        end

      Drafter.WidgetHierarchy.update_widget_rect(hierarchy, widget_id, new_rect)
    else
      hierarchy
    end
  end

  defp find_divider_mode(actions) do
    Enum.find_value(actions, nil, fn
      {:divider_move, mode} -> mode
      _ -> nil
    end)
  end

  defp clear_divider_origins do
    Process.get_keys()
    |> Enum.each(fn
      {:divider_origin_rect, _} = key -> Process.delete(key)
      _ -> :ok
    end)
  end

  defp scoped_invalidate_for_layout(:all, _screen_rect) do
    RenderCache.invalidate()
  end

  defp scoped_invalidate_for_layout(:resize, _screen_rect) do
    Process.put(:render_cache_layout_dirty, true)
  end

  defp scoped_invalidate_for_layout(direction, screen_rect) when direction in [:self, :below, :above, :left, :right, :parent] do
    Process.put(:render_cache_layout_dirty, true)
    Process.put(:render_cache_layout_direction, direction)
    Process.put(:render_cache_layout_rect, screen_rect)
  end

  defp scoped_invalidate_for_layout(_, _screen_rect) do
    RenderCache.invalidate()
  end
end
