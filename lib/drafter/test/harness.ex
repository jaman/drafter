defmodule Drafter.Test.Harness do
  @moduledoc """
  Manages the lifecycle of a headless TUI app instance for testing.

  Starts the required services (`HeadlessDriver`, `Compositor`, `ThemeManager`,
  `Event.Manager`) and spawns the app event loop without any terminal I/O.
  Returns a context map used by `Drafter.Test` functions. Call `stop_app/1`
  to cleanly shut down all services started by the harness.
  """

  use GenServer

  defstruct [
    :app_module,
    :app_pid,
    :app_monitor,
    :props,
    :test_pid
  ]

  def init(init_arg) do
    {:ok, init_arg}
  end

  def start_app(app_module, props \\ %{}, opts \\ []) do
    test_pid = Keyword.get(opts, :test_pid, self())
    size = Keyword.get(opts, :size, {80, 24})

    with {:ok, _} <- Drafter.Event.Manager.start_link(),
         {:ok, _} <- Drafter.Test.HeadlessDriver.start_link(test_pid: test_pid, size: size),
         {:ok, _} <-
           Drafter.Compositor.start_link(terminal_driver: Drafter.Test.HeadlessDriver),
         {:ok, _} <- Drafter.ThemeManager.start_link(),
         :ok <- Drafter.Test.HeadlessDriver.setup() do
      app_pid =
        spawn_link(fn ->
          run_headless_app(app_module, props)
        end)

      Drafter.Event.Manager.subscribe(app_pid)

      ref = Process.monitor(app_pid)

      ctx = %{
        app_module: app_module,
        app_pid: app_pid,
        app_monitor: ref,
        props: props,
        test_pid: test_pid
      }

      {:ok, ctx}
    else
      {:error, {:already_started, pid}} ->
        Process.link(pid)
        {:error, :already_started}

      error ->
        error
    end
  end

  def stop_app(ctx) do
    if Process.alive?(ctx.app_pid) do
      monitor_ref = ctx.app_monitor
      send(ctx.app_pid, :shutdown)

      receive do
        {:DOWN, ^monitor_ref, :process, _, _} -> :ok
      after
        500 ->
          Process.exit(ctx.app_pid, :kill)
      end

      Process.demonitor(ctx.app_monitor, [:flush])
    end

    stop_services()
    :ok
  end

  defp stop_services do
    services = [
      Drafter.Test.HeadlessDriver,
      Drafter.Compositor,
      Drafter.ThemeManager,
      Drafter.Event.Manager
    ]

    Enum.each(services, fn service ->
      if Process.whereis(service) do
        GenServer.stop(service, :normal, 1000)
      end
    end)
  end

  defp run_headless_app(app_module, props) do
    Drafter.AppRegistry.register()

    Drafter.ThemeManager.register_app(self())
    Drafter.ScreenManager.register_app(self())

    app_state = app_module.mount(props)

    {width, height} = Drafter.Compositor.get_screen_size()
    screen_rect = %{x: 0, y: 0, width: width, height: height}

    {_, hierarchy} = render_app(app_module, app_state, screen_rect)

    ready_app_state =
      if function_exported?(app_module, :on_ready, 1) do
        app_module.on_ready(app_state)
      else
        app_state
      end

    {_, hierarchy} = render_app(app_module, ready_app_state, screen_rect, hierarchy)

    headless_event_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy)
  end

  defp render_app(app_module, app_state, screen_rect, previous_hierarchy \\ nil) do
    layout = app_module.render(app_state)
    theme = Drafter.ThemeManager.get_current_theme()

    hierarchy =
      Drafter.ComponentRenderer.render_tree(
        layout,
        screen_rect,
        theme,
        app_state,
        previous_hierarchy,
        app_module: app_module
      )

    {[], hierarchy}
  end

  defp headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = %{x: 0, y: 0, width: width, height: height}
        {_, new_hierarchy} = render_app(app_module, app_state, new_screen_rect, widget_hierarchy)
        headless_event_loop(app_module, app_state, new_screen_rect, timers, new_hierarchy)

      {:tui_event, event} ->
        case check_global_quit(event) do
          :quit ->
            cleanup_timers(timers)
            :ok

          :continue ->
            case app_module.handle_event(event, app_state) do
              {:ok, new_app_state} ->
                {_, updated_hierarchy} =
                  render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

                headless_event_loop(
                  app_module,
                  new_app_state,
                  screen_rect,
                  timers,
                  updated_hierarchy
                )

              {:stop, _reason} ->
                cleanup_timers(timers)
                :ok

              {:error, _reason} ->
                headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

              {:noreply, app_state} ->
                {new_hierarchy, _widget_handled, needs_rerender, actions} =
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

                new_app_state =
                  Enum.reduce(actions, app_state, fn action, acc_state ->
                    case action do
                      {:app_callback, callback, data} ->
                        result = app_module.handle_event(callback, data, acc_state)

                        case result do
                          {:ok, new_state} -> new_state
                          {:stop, _reason} -> acc_state
                          {:noreply, new_state} -> new_state
                          _other -> acc_state
                        end

                      _ ->
                        acc_state
                    end
                  end)

                if needs_rerender do
                  {_, final_hierarchy} =
                    render_app(app_module, new_app_state, screen_rect, new_hierarchy)

                  headless_event_loop(
                    app_module,
                    new_app_state,
                    screen_rect,
                    timers,
                    final_hierarchy
                  )
                else
                  headless_event_loop(
                    app_module,
                    new_app_state,
                    screen_rect,
                    timers,
                    new_hierarchy
                  )
                end
            end
        end

      {:get_state, from} ->
        send(from, {:state, app_state})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:get_hierarchy, from} ->
        send(from, {:hierarchy, widget_hierarchy})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:query_one, selector, from} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_one(widget_hierarchy, selector)
          else
            nil
          end

        send(from, {:query_result, :one, result})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:query_all, selector, from} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_all(widget_hierarchy, selector)
          else
            []
          end

        send(from, {:query_result, :all, result})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:get_widget_value, widget_id, from} ->
        value =
          if widget_hierarchy do
            case Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id) do
              nil -> nil
              widget_state -> extract_widget_value(widget_state)
            end
          else
            nil
          end

        send(from, {:widget_value, widget_id, value})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:get_widget_state, widget_id, from} ->
        widget_state =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id)
          else
            nil
          end

        send(from, {:widget_state, widget_id, widget_state})
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:widget_render_needed, _widget_id} ->
        {_, new_hierarchy} = render_app(app_module, app_state, screen_rect, widget_hierarchy)
        headless_event_loop(app_module, app_state, screen_rect, timers, new_hierarchy)

      {:widget_action, _widget_id, {:app_callback, callback, data}} ->
        case app_module.handle_event(callback, data, app_state) do
          {:ok, new_state} ->
            {_, new_hierarchy} = render_app(app_module, new_state, screen_rect, widget_hierarchy)
            headless_event_loop(app_module, new_state, screen_rect, timers, new_hierarchy)

          {:noreply, new_state} ->
            headless_event_loop(app_module, new_state, screen_rect, timers, widget_hierarchy)

          {:stop, _reason} ->
            cleanup_timers(timers)
            :ok

          _other ->
            headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      :shutdown ->
        cleanup_timers(timers)
        :ok

      msg ->
        IO.puts("Unhandled message in headless_event_loop: #{inspect(msg)}")
        headless_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
    end
  end

  defp check_global_quit({:key, key}) when key in [:q, :Q] do
    modifiers = Process.get(:last_key_modifiers, [])

    if :ctrl in modifiers do
      :quit
    else
      :continue
    end
  end

  defp check_global_quit(_event), do: :continue

  defp cleanup_timers(timers) do
    Enum.each(timers, fn {_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)
  end

  defp extract_widget_value(state) do
    cond do
      Map.has_key?(state, :text) -> state.text
      Map.has_key?(state, :checked) -> state.checked
      Map.has_key?(state, :enabled) -> state.enabled
      Map.has_key?(state, :selected_option) -> state.selected_option
      Map.has_key?(state, :selected_indices) -> MapSet.to_list(state.selected_indices)
      Map.has_key?(state, :selected_index) -> state.selected_index
      Map.has_key?(state, :expanded) -> state.expanded
      Map.has_key?(state, :active_tab) -> state.active_tab
      true -> nil
    end
  end
end
