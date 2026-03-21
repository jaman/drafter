defmodule Drafter.Runtime.AppLoop do
  @moduledoc """
  Application event loop for Drafter.

  Owns the receive loop and all message dispatch logic.
  Calls Drafter.Runtime.Renderer for all rendering.
  """

  alias Drafter.{Terminal, Event, ThemeManager, SkinManager, Compositor}
  alias Drafter.Runtime.Renderer

  @scroll_debounce_ms 150

  @spec enter_loop(module(), term(), map(), map(), map() | nil, keyword()) :: :ok
  def enter_loop(app_module, app_state, screen_rect, timers \\ %{}, widget_hierarchy \\ nil, opts \\ []) do
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
    app_state = app_module.mount(initial_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)

    Process.put(:pending_intervals, [])
    ready_app_state = app_module.on_ready(app_state)
    initial_timers = collect_pending_intervals()
    {_, hierarchy} = Renderer.render_app(app_module, ready_app_state, screen_rect, hierarchy)

    app_event_loop(app_module, ready_app_state, screen_rect, initial_timers, hierarchy, [])
  end

  defp app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = make_screen_rect(width, height)
        {_, new_hierarchy} = immediate_render(app_module, app_state, new_screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, new_screen_rect, timers, new_hierarchy, session_stack)

      {:tui_event, event} ->
        case check_global_quit(event) do
          :quit when session_stack == [] ->
            cleanup_timers(timers)
            Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
            :ok

          :quit ->
            {prev_module, prev_state, prev_hierarchy, prev_timers, prev_from, prev_ref} =
              hd(session_stack)

            cleanup_timers(timers)
            Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)

            if prev_from, do: send(prev_from, {:session_result, prev_ref, :ok})

            {_, restored_hierarchy} =
              Renderer.render_app(prev_module, prev_state, screen_rect, prev_hierarchy)

            app_event_loop(prev_module, prev_state, screen_rect, prev_timers, restored_hierarchy, tl(session_stack))

          :continue ->
            has_screens = length(Drafter.ScreenManager.get_all_screens()) > 0

            if has_screens do
              Drafter.EventHandler.dispatch_event_sync(event)

              if Drafter.ScreenManager.get_all_screens() == [] do
                {_, fresh_hierarchy} =
                  immediate_render(app_module, app_state, screen_rect, widget_hierarchy)

                app_event_loop(app_module, app_state, screen_rect, timers, fresh_hierarchy, session_stack)
              else
                Renderer.render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
              end
            else
              {new_hierarchy, actions, widget_consumed} =
                if widget_hierarchy && widget_hierarchy.focused_widget do
                  Drafter.WidgetHierarchy.handle_event_consumed(widget_hierarchy, event)
                else
                  {widget_hierarchy, [], false}
                end

              raw_mouse_event? = match?({:mouse, _}, event)

              if widget_consumed do
                updated_hierarchy =
                  if Enum.member?(actions, :widget_layout_needed) do
                    Renderer.update_hierarchy_preferred_sizes(new_hierarchy)
                  else
                    new_hierarchy
                  end

                new_app_state =
                  Enum.reduce(actions, app_state, fn
                    {:app_callback, callback, data}, acc_state ->
                      dispatch_app_callback(app_module, callback, data, acc_state)

                    _, acc_state ->
                      acc_state
                  end)

                has_app_callback = Enum.any?(actions, &match?({:app_callback, _, _}, &1))

                post_widget_state =
                  if raw_mouse_event? and not has_app_callback do
                    case app_module.handle_event(event, new_app_state) do
                      {:ok, s} -> s
                      {:noreply, s} -> s
                      _ -> new_app_state
                    end
                  else
                    new_app_state
                  end

                if :scroll_fast_render in actions and scroll_optimization_enabled?() do
                  scrolled_app_state = maybe_scroll_active(app_module, post_widget_state)
                  Renderer.render_hierarchy(updated_hierarchy, screen_rect)
                  reschedule_scroll_debounce()

                  app_event_loop(
                    app_module,
                    scrolled_app_state,
                    screen_rect,
                    timers,
                    updated_hierarchy,
                    session_stack
                  )
                else
                  {_, final_hierarchy} =
                    immediate_render(app_module, post_widget_state, screen_rect, updated_hierarchy)

                  app_event_loop(
                    app_module,
                    post_widget_state,
                    screen_rect,
                    timers,
                    final_hierarchy,
                    session_stack
                  )
                end
              else
                case app_module.handle_event(event, app_state) do
                  {:ok, new_app_state} ->
                    {_, updated_hierarchy} =
                      immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)

                    app_event_loop(
                      app_module,
                      new_app_state,
                      screen_rect,
                      timers,
                      updated_hierarchy,
                      session_stack
                    )

                  {:stop, reason} ->
                    if session_stack == [] do
                      cleanup_timers(timers)
                      Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
                      if reason == :normal, do: :ok, else: {:error, reason}
                    else
                      {prev_module, prev_state, prev_hierarchy, prev_timers, prev_from, prev_ref} =
                        hd(session_stack)

                      cleanup_timers(timers)
                      Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
                      if prev_from, do: send(prev_from, {:session_result, prev_ref, :ok})

                      {_, restored_hierarchy} =
                        Renderer.render_app(prev_module, prev_state, screen_rect, prev_hierarchy)

                      app_event_loop(prev_module, prev_state, screen_rect, prev_timers, restored_hierarchy, tl(session_stack))
                    end

                  {:error, _reason} ->
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:show_modal, screen_module, props, opts} ->
                    Drafter.ScreenManager.show_modal(screen_module, props, opts)

                    Renderer.render_screens_from_manager(
                      screen_rect,
                      app_module,
                      app_state,
                      widget_hierarchy
                    )

                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:show_toast, message, opts} ->
                    Drafter.ScreenManager.show_toast(message, opts)

                    Renderer.render_screens_from_manager(
                      screen_rect,
                      app_module,
                      app_state,
                      widget_hierarchy
                    )

                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:push, screen_module, props, opts} ->
                    Drafter.ScreenManager.push(screen_module, props, opts)

                    Renderer.render_screens_from_manager(
                      screen_rect,
                      app_module,
                      app_state,
                      widget_hierarchy
                    )

                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:replace, screen_module, props, opts} ->
                    Drafter.ScreenManager.replace(screen_module, props, opts)

                    Renderer.render_screens_from_manager(
                      screen_rect,
                      app_module,
                      app_state,
                      widget_hierarchy
                    )

                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:pop, result} ->
                    Drafter.ScreenManager.pop(result)

                    Renderer.render_screens_from_manager(
                      screen_rect,
                      app_module,
                      app_state,
                      widget_hierarchy
                    )

                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

                  {:noreply, app_state} ->
                    {new_hierarchy, widget_handled, needs_rerender, actions} =
                      if widget_hierarchy do
                        case Drafter.WidgetHierarchy.handle_event(widget_hierarchy, event) do
                          {hierarchy, []} ->
                            hierarchy_changed =
                              hierarchy.focused_widget != widget_hierarchy.focused_widget

                            {hierarchy, hierarchy_changed, hierarchy_changed, []}

                          {hierarchy, actions} ->
                            {hierarchy, true, true, actions}
                        end
                      else
                        {widget_hierarchy, false, false, []}
                      end

                    updated_hierarchy =
                      if Enum.member?(actions, :widget_layout_needed) do
                        Renderer.update_hierarchy_preferred_sizes(new_hierarchy)
                      else
                        new_hierarchy
                      end

                    new_app_state =
                      Enum.reduce(actions, app_state, fn
                        {:app_callback, callback, data}, acc_state ->
                          dispatch_app_callback(app_module, callback, data, acc_state)

                        _, acc_state ->
                          acc_state
                      end)

                    if needs_rerender or widget_handled do
                      {_, final_hierarchy} =
                        immediate_render(app_module, new_app_state, screen_rect, updated_hierarchy)

                      app_event_loop(
                        app_module,
                        new_app_state,
                        screen_rect,
                        timers,
                        final_hierarchy,
                        session_stack
                      )
                    else
                      app_event_loop(
                        app_module,
                        new_app_state,
                        screen_rect,
                        timers,
                        updated_hierarchy,
                        session_stack
                      )
                    end
                end
              end
            end
        end

      {:app_event, event_name, data} ->
        result = app_module.handle_event(event_name, data, app_state)

        case result do
          {:stop, reason} ->
            if session_stack == [] do
              cleanup_timers(timers)
              Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
              if reason == :normal, do: :ok, else: {:error, reason}
            else
              {prev_module, prev_state, prev_hierarchy, prev_timers, prev_from, prev_ref} =
                hd(session_stack)

              cleanup_timers(timers)
              Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
              if prev_from, do: send(prev_from, {:session_result, prev_ref, :ok})

              {_, restored_hierarchy} =
                Renderer.render_app(prev_module, prev_state, screen_rect, prev_hierarchy)

              app_event_loop(prev_module, prev_state, screen_rect, prev_timers, restored_hierarchy, tl(session_stack))
            end

          _ ->
            new_app_state = dispatch_app_callback_result(result, app_state)

            {_, new_hierarchy} =
              immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)

            app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, session_stack)
        end

      {:bound_state_update, key, value} ->
        new_app_state = Map.put(app_state, key, value)
        {_, new_hierarchy} = immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, session_stack)

      {:theme_change, theme_name} ->
        ThemeManager.set_theme(theme_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:theme_updated, new_theme} ->
        new_app_state =
          case app_module.handle_event({:theme_updated, new_theme}, app_state) do
            {:ok, state} -> state
            {:noreply, state} -> state
            state when is_map(state) -> state
          end

        {_, new_hierarchy} = immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, session_stack)

      {:skin_change, skin_name} ->
        SkinManager.set_skin(skin_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:skin_updated, _skin} ->
        {_, new_hierarchy} = immediate_render(app_module, app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, new_hierarchy, session_stack)

      {:timer, timer_id} ->
        is_parent_timer =
          not Map.has_key?(timers, timer_id) and
            Enum.any?(session_stack, fn {_, _, _, parent_timers, _, _} ->
              Map.has_key?(parent_timers, timer_id)
            end)

        if is_parent_timer do
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        else
          new_app_state = app_module.on_timer(timer_id, app_state)

          if new_app_state === app_state do
            app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
          else
            {_, new_hierarchy} =
              Renderer.render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

            app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, session_stack)
          end
        end

      {:set_interval, interval_ms, timer_id} ->
        timer_ref = :timer.send_interval(interval_ms, {:timer, timer_id})
        new_timers = Map.put(timers, timer_id, timer_ref)
        app_event_loop(app_module, app_state, screen_rect, new_timers, widget_hierarchy, session_stack)

      {:set_timeout, timeout_ms, timer_id} ->
        Process.send_after(self(), {:timer, timer_id}, timeout_ms)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:focus_widget, widget_id} ->
        new_hierarchy =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.focus_widget(widget_hierarchy, widget_id)
          else
            widget_hierarchy
          end

        {_, updated_hierarchy} = immediate_render(app_module, app_state, screen_rect, new_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, session_stack)

      {:widget_event, event} ->
        if widget_hierarchy do
          {new_hierarchy, _actions} =
            Drafter.WidgetHierarchy.broadcast_event(widget_hierarchy, event)

          {_, updated_hierarchy} =
            immediate_render(app_module, app_state, screen_rect, new_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, session_stack)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      {:widget_event, widget_id, event} ->
        if widget_hierarchy do
          {new_hierarchy, _actions} =
            Drafter.WidgetHierarchy.send_event_to_widget(widget_hierarchy, widget_id, event)

          {_, updated_hierarchy} =
            immediate_render(app_module, app_state, screen_rect, new_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, session_stack)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      {:widget_render_needed, _widget_id} ->
        drain_widget_render_notifications()

        if widget_hierarchy do
          Renderer.render_hierarchy(widget_hierarchy, screen_rect)
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      :scroll_debounce_render ->
        drain_scroll_debounce_renders()
        Process.delete(:scroll_debounce_ref)
        idle_app_state = maybe_scroll_idle(app_module, app_state)

        if widget_hierarchy do
          {_, updated_hierarchy} =
            immediate_render(app_module, idle_app_state, screen_rect, widget_hierarchy)

          app_event_loop(app_module, idle_app_state, screen_rect, timers, updated_hierarchy, session_stack)
        else
          app_event_loop(app_module, idle_app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      {:widget_action, _widget_id, {:theme_change, theme_name}} ->
        ThemeManager.set_theme(theme_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:widget_action, _widget_id, {:skin_change, skin_name}} ->
        SkinManager.set_skin(skin_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:widget_action, _widget_id, {:app_callback, callback, data}} ->
        new_app_state = dispatch_app_callback(app_module, callback, data, app_state)

        {_, updated_hierarchy} =
          immediate_render(app_module, new_app_state, screen_rect, widget_hierarchy)

        app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy, session_stack)

      {:widget_action, _widget_id, _action} ->
        if widget_hierarchy do
          {_, updated_hierarchy} =
            immediate_render(app_module, app_state, screen_rect, widget_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, session_stack)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      {:activate_widget, widget_id} ->
        if widget_hierarchy do
          {new_hierarchy, actions} =
            Drafter.WidgetHierarchy.send_event_to_widget(widget_hierarchy, widget_id, :activate)

          new_app_state =
            Enum.reduce(actions, app_state, fn
              {:app_callback, callback, data}, acc_state ->
                dispatch_app_callback(app_module, callback, data, acc_state)

              _, acc_state ->
                acc_state
            end)

          {_, updated_hierarchy} =
            immediate_render(app_module, new_app_state, screen_rect, new_hierarchy)

          app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy, session_stack)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      {:get_widget_value, widget_id, caller} ->
        value =
          if widget_hierarchy do
            case Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id) do
              nil -> nil
              state -> extract_widget_value(state)
            end
          else
            nil
          end

        send(caller, {:widget_value, widget_id, value})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:get_widget_state, widget_id, caller} ->
        state =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id)
          else
            nil
          end

        send(caller, {:widget_state, widget_id, state})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:query_one, selector, caller} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_one(widget_hierarchy, selector)
          else
            nil
          end

        send(caller, {:query_result, :one, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:query_all, selector, caller} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_all(widget_hierarchy, selector)
          else
            []
          end

        send(caller, {:query_result, :all, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:validate_widget, widget_id, caller} ->
        result =
          if widget_hierarchy do
            {new_hierarchy, _} =
              Drafter.WidgetHierarchy.send_event_to_widget(
                widget_hierarchy,
                widget_id,
                :validate
              )

            state = Drafter.WidgetHierarchy.get_widget_state(new_hierarchy, widget_id)
            error = if state, do: Map.get(state, :error), else: nil

            case error do
              nil -> :ok
              msg -> {:error, msg}
            end
          else
            :ok
          end

        send(caller, {:validation_result, widget_id, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:get_animated_property, widget_id, property, caller} ->
        value =
          if widget_hierarchy do
            case Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id) do
              nil -> nil
              state -> get_animated_property_from_state(state, property)
            end
          else
            nil
          end

        send(caller, {:animated_property, widget_id, property, value})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:apply_animation, widget_id, property, value} ->
        if widget_hierarchy do
          case Drafter.WidgetHierarchy.get_widget_info(widget_hierarchy, widget_id) do
            nil ->
              app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

            widget_info ->
              updated_state = apply_animated_property(widget_info.state, property, value)

              new_hierarchy =
                Drafter.WidgetHierarchy.update_widget_state(
                  widget_hierarchy,
                  widget_id,
                  updated_state
                )

              {_, final_hierarchy} = throttled_render(app_module, app_state, screen_rect, new_hierarchy)
              app_event_loop(app_module, app_state, screen_rect, timers, final_hierarchy, session_stack)
          end
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)
        end

      :animation_tick ->
        {_, updated_hierarchy} = throttled_render(app_module, app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, session_stack)

      :screen_render_needed ->
        Renderer.render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, session_stack)

      {:__drafter_stop__, reason} ->
        if session_stack == [] do
          cleanup_timers(timers)
          Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
          if reason == :normal, do: :ok, else: {:error, reason}
        else
          {prev_module, prev_state, prev_hierarchy, prev_timers, prev_from, prev_ref} =
            hd(session_stack)

          cleanup_timers(timers)
          Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
          if prev_from, do: send(prev_from, {:session_result, prev_ref, :ok})

          {_, restored_hierarchy} =
            Renderer.render_app(prev_module, prev_state, screen_rect, prev_hierarchy)

          app_event_loop(prev_module, prev_state, screen_rect, prev_timers, restored_hierarchy, tl(session_stack))
        end

      {:push_session, new_module, opts, from_pid, ref} ->
        mount_props = Keyword.drop(opts, [:scroll_optimization, :syntax_highlighting, :refresh_rate]) |> Map.new()
        setup_frame_rate(new_module, opts)
        new_state = new_module.mount(mount_props)
        {_, new_hierarchy} = Renderer.render_app(new_module, new_state, screen_rect)
        Process.put(:pending_intervals, [])
        ready_state = new_module.on_ready(new_state)
        initial_timers = collect_pending_intervals()
        drain_stale_events()
        {_, new_hierarchy} = Renderer.render_app(new_module, ready_state, screen_rect, new_hierarchy)
        current = {app_module, app_state, widget_hierarchy, timers, from_pid, ref}
        app_event_loop(new_module, ready_state, screen_rect, initial_timers, new_hierarchy, [current | session_stack])

      :deferred_render ->
        Process.delete(:render_deferred)
        Process.put(:last_render_ms, System.monotonic_time(:millisecond))
        {_, new_hierarchy} = Renderer.render_app(app_module, app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, new_hierarchy, session_stack)

      other ->
        new_app_state = maybe_on_message(app_module, other, app_state)
        app_event_loop(app_module, new_app_state, screen_rect, timers, widget_hierarchy, session_stack)
    end
  end

  defp dispatch_app_callback(app_module, callback, data, acc_state) do
    result = app_module.handle_event(callback, data, acc_state)
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

  defp extract_widget_value(state) do
    cond do
      Map.has_key?(state, :text) ->
        state.text

      Map.has_key?(state, :checked) ->
        state.checked

      Map.has_key?(state, :state) and state.state in [:on, :off] ->
        state.state == :on

      Map.has_key?(state, :selected_index) and Map.has_key?(state, :options) ->
        case Enum.at(state.options, state.selected_index) do
          %{id: id} -> id
          nil -> nil
        end

      Map.has_key?(state, :selected_indices) and Map.has_key?(state, :options) ->
        state.selected_indices
        |> MapSet.to_list()
        |> Enum.map(fn idx ->
          case Enum.at(state.options, idx) do
            %{id: id} -> id
            nil -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      Map.has_key?(state, :expanded) ->
        state.expanded

      Map.has_key?(state, :active_tab) ->
        state.active_tab

      Map.has_key?(state, :selected_rows) ->
        MapSet.to_list(state.selected_rows)

      Map.has_key?(state, :selected_nodes) ->
        MapSet.to_list(state.selected_nodes)

      true ->
        nil
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
      %{type: :key, key: :c, modifiers: [:ctrl]} -> :quit
      {:key, :c, [:ctrl]} -> :quit
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

  defp scroll_optimization_enabled?, do: Process.get(:scroll_optimization, true) != false

  defp maybe_on_message(app_module, msg, app_state) do
    if function_exported?(app_module, :on_message, 2) do
      app_module.on_message(msg, app_state)
    else
      app_state
    end
  end

  defp maybe_scroll_active(app_module, app_state) do
    if Process.get(:scroll_gesture_active) do
      app_state
    else
      Process.put(:scroll_gesture_active, true)

      if function_exported?(app_module, :on_scroll_active, 1) do
        app_module.on_scroll_active(app_state)
      else
        app_state
      end
    end
  end

  defp maybe_scroll_idle(app_module, app_state) do
    Process.delete(:scroll_gesture_active)

    if function_exported?(app_module, :on_scroll_idle, 1) do
      app_module.on_scroll_idle(app_state)
    else
      app_state
    end
  end

  defp make_screen_rect(width, height) do
    %{x: 0, y: 0, width: width, height: height}
  end

  defp setup_frame_rate(app_module, opts) do
    rate =
      Keyword.get(opts, :refresh_rate) ||
        (function_exported?(app_module, :refresh_rate, 0) && app_module.refresh_rate()) ||
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
        fps = if String.contains?(fps_str, "."), do: String.to_float(fps_str), else: String.to_integer(fps_str)
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
    Process.put(:last_render_ms, System.monotonic_time(:millisecond))
    Process.delete(:render_deferred)
    Renderer.render_app(app_module, app_state, screen_rect, hierarchy)
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
          unless Process.get(:render_deferred) do
            remaining = interval - (now - last)
            Process.send_after(self(), :deferred_render, remaining)
            Process.put(:render_deferred, true)
          end

          {[], hierarchy}
        end
    end
  end
end
