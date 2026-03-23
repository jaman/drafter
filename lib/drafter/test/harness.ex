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

    loop_state = %{
      app_module: app_module,
      app_state: ready_app_state,
      screen_rect: screen_rect,
      timers: %{},
      hierarchy: hierarchy
    }

    headless_event_loop(loop_state)
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

  defp headless_event_loop(loop) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = %{x: 0, y: 0, width: width, height: height}
        {_, new_hierarchy} = render_app(loop.app_module, loop.app_state, new_screen_rect, loop.hierarchy)
        headless_event_loop(%{loop | screen_rect: new_screen_rect, hierarchy: new_hierarchy})

      {:tui_event, event} ->
        handle_tui_event(loop, event)

      {:get_state, from} ->
        send(from, {:state, loop.app_state})
        headless_event_loop(loop)

      {:get_hierarchy, from} ->
        send(from, {:hierarchy, loop.hierarchy})
        headless_event_loop(loop)

      {:query_one, selector, from} ->
        result = query_hierarchy(loop.hierarchy, :one, selector)
        send(from, {:query_result, :one, result})
        headless_event_loop(loop)

      {:query_all, selector, from} ->
        result = query_hierarchy(loop.hierarchy, :all, selector)
        send(from, {:query_result, :all, result})
        headless_event_loop(loop)

      {:get_widget_value, widget_id, from} ->
        value = get_widget_value_from_hierarchy(loop.hierarchy, widget_id)
        send(from, {:widget_value, widget_id, value})
        headless_event_loop(loop)

      {:get_widget_state, widget_id, from} ->
        widget_state = get_widget_state_from_hierarchy(loop.hierarchy, widget_id)
        send(from, {:widget_state, widget_id, widget_state})
        headless_event_loop(loop)

      {:widget_render_needed, _widget_id} ->
        {_, new_hierarchy} = render_app(loop.app_module, loop.app_state, loop.screen_rect, loop.hierarchy)
        headless_event_loop(%{loop | hierarchy: new_hierarchy})

      {:widget_action, _widget_id, {:app_callback, callback, data}} ->
        handle_widget_action(loop, callback, data)

      :shutdown ->
        cleanup_timers(loop.timers)
        :ok

      _msg ->
        headless_event_loop(loop)
    end
  end

  defp handle_tui_event(loop, event) do
    case check_global_quit(event) do
      :quit ->
        cleanup_timers(loop.timers)
        :ok

      :continue ->
        handle_app_event(loop, event)
    end
  end

  defp handle_app_event(loop, event) do
    case loop.app_module.handle_event(event, loop.app_state) do
      {:ok, new_app_state} ->
        {_, updated_hierarchy} = render_app(loop.app_module, new_app_state, loop.screen_rect, loop.hierarchy)
        headless_event_loop(%{loop | app_state: new_app_state, hierarchy: updated_hierarchy})

      {:stop, _reason} ->
        cleanup_timers(loop.timers)
        :ok

      {:error, _reason} ->
        headless_event_loop(loop)

      {:noreply, _app_state} ->
        handle_widget_event(loop, event)
    end
  end

  defp handle_widget_event(loop, event) do
    {new_hierarchy, needs_rerender, actions} = dispatch_to_widgets(loop.hierarchy, event)
    new_app_state = process_actions(loop.app_module, loop.app_state, actions)

    if needs_rerender do
      {_, final_hierarchy} = render_app(loop.app_module, new_app_state, loop.screen_rect, new_hierarchy)
      headless_event_loop(%{loop | app_state: new_app_state, hierarchy: final_hierarchy})
    else
      headless_event_loop(%{loop | app_state: new_app_state, hierarchy: new_hierarchy})
    end
  end

  defp dispatch_to_widgets(nil, _event), do: {nil, false, []}

  defp dispatch_to_widgets(hierarchy, event) do
    case Drafter.WidgetHierarchy.handle_event(hierarchy, event) do
      {new_hierarchy, []} ->
        changed = new_hierarchy.focused_widget != hierarchy.focused_widget
        {new_hierarchy, changed, []}

      {new_hierarchy, actions} ->
        {new_hierarchy, true, actions}
    end
  end

  defp process_actions(app_module, app_state, actions) do
    Enum.reduce(actions, app_state, fn action, acc_state ->
      process_single_action(app_module, acc_state, action)
    end)
  end

  defp process_single_action(app_module, acc_state, {:app_callback, callback, data}) do
    case app_module.handle_event(callback, data, acc_state) do
      {:ok, new_state} -> new_state
      {:noreply, new_state} -> new_state
      _ -> acc_state
    end
  end

  defp process_single_action(_app_module, acc_state, _action), do: acc_state

  defp handle_widget_action(loop, callback, data) do
    case loop.app_module.handle_event(callback, data, loop.app_state) do
      {:ok, new_state} ->
        {_, new_hierarchy} = render_app(loop.app_module, new_state, loop.screen_rect, loop.hierarchy)
        headless_event_loop(%{loop | app_state: new_state, hierarchy: new_hierarchy})

      {:noreply, new_state} ->
        headless_event_loop(%{loop | app_state: new_state})

      {:stop, _reason} ->
        cleanup_timers(loop.timers)
        :ok

      _other ->
        headless_event_loop(loop)
    end
  end

  defp query_hierarchy(nil, :one, _selector), do: nil
  defp query_hierarchy(nil, :all, _selector), do: []
  defp query_hierarchy(hierarchy, :one, selector), do: Drafter.WidgetHierarchy.query_one(hierarchy, selector)
  defp query_hierarchy(hierarchy, :all, selector), do: Drafter.WidgetHierarchy.query_all(hierarchy, selector)

  defp get_widget_value_from_hierarchy(nil, _widget_id), do: nil

  defp get_widget_value_from_hierarchy(hierarchy, widget_id) do
    case Drafter.WidgetHierarchy.get_widget_state(hierarchy, widget_id) do
      nil -> nil
      widget_state -> extract_widget_value(widget_state)
    end
  end

  defp get_widget_state_from_hierarchy(nil, _widget_id), do: nil
  defp get_widget_state_from_hierarchy(hierarchy, widget_id), do: Drafter.WidgetHierarchy.get_widget_state(hierarchy, widget_id)

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

  @value_keys [:text, :checked, :enabled, :selected_option, :selected_indices, :selected_index, :expanded, :active_tab]

  defp extract_widget_value(state) when is_map(state) do
    case Enum.find(@value_keys, &Map.has_key?(state, &1)) do
      nil -> nil
      :selected_indices -> MapSet.to_list(state.selected_indices)
      key -> Map.get(state, key)
    end
  end

  defp extract_widget_value(_state), do: nil
end
