defmodule Drafter.Test.Harness do
  @moduledoc """
  Manages the lifecycle of a headless TUI app instance for testing.

  Starts the required services (`HeadlessDriver`, `Compositor`, `ThemeManager`,
  `Event.Manager`) and spawns the app event loop without any terminal I/O.
  Returns a context map used by `Drafter.Test` functions. Call `stop_app/1`
  to cleanly shut down all services started by the harness.
  """

  use GenServer

  alias Drafter.{Compositor, Event, EventHandler, ScreenManager, Test, ThemeManager}
  alias Drafter.Runtime.AppLoop

  defstruct [
    :app_module,
    :app_pid,
    :app_monitor,
    :props,
    :test_pid
  ]

  @typedoc """
  The context returned by `start_app/3` and consumed by `Drafter.Test` and `stop_app/1`.
  """
  @type context :: %{
          app_module: module(),
          app_pid: pid(),
          app_monitor: reference(),
          props: map(),
          test_pid: pid(),
          session_pids: %{atom() => pid()}
        }

  @doc "Returns `{:ok, init_arg}` unchanged."
  @impl GenServer
  @spec init(term()) :: {:ok, term()}
  def init(init_arg) do
    {:ok, init_arg}
  end

  @doc """
  Start a headless app and every service it needs, returning a test context.

  Starts an unnamed `Drafter.Event.Manager`, `Drafter.Compositor`,
  `Drafter.ThemeManager`, `Drafter.EventHandler` and `Drafter.ScreenManager` plus the
  named `Drafter.Test.HeadlessDriver`, links them to the caller, and spawns the app
  loop with the session's pids copied into its process dictionary. `props` is passed
  to the app's `mount/1` and defaults to `%{}`.

  Returns `{:ok, context}`, `{:error, :already_started}` when a service of the same
  name is already running (that service is linked to the caller first), or the first
  service's own `{:error, reason}`.

  ## Options

    * `:test_pid` - process the headless driver reports output to. Default: the
      calling process.
    * `:size` - terminal size as `{columns, rows}`. Default: `{80, 24}`.

  """
  @spec start_app(module(), map(), keyword()) :: {:ok, context()} | {:error, term()}
  def start_app(app_module, props \\ %{}, opts \\ []) do
    test_pid = Keyword.get(opts, :test_pid, self())
    size = Keyword.get(opts, :size, {80, 24})

    with {:ok, em} <- Event.Manager.start_link(name: nil),
         {:ok, _} <-
           Test.HeadlessDriver.start_link(
             test_pid: test_pid,
             size: size,
             event_manager: em
           ),
         {:ok, comp} <-
           Compositor.start_link(
             name: nil,
             terminal_driver: Test.HeadlessDriver,
             event_manager: em
           ),
         {:ok, tm} <- ThemeManager.start_link(name: nil),
         {:ok, eh} <- EventHandler.start_link(name: nil),
         {:ok, sm} <- ScreenManager.start_link(name: nil, event_handler: eh),
         :ok <- Test.HeadlessDriver.setup() do
      session_pdict = %{
        drafter_event_manager: em,
        drafter_compositor: comp,
        drafter_theme_manager: tm,
        drafter_screen_manager: sm,
        drafter_event_handler: eh
      }

      app_pid =
        spawn_link(fn ->
          propagate_pdict(session_pdict)
          run_headless_app(app_module, props)
        end)

      Event.Manager.subscribe_to(em, app_pid)

      ref = Process.monitor(app_pid)

      ctx = %{
        app_module: app_module,
        app_pid: app_pid,
        app_monitor: ref,
        props: props,
        test_pid: test_pid,
        session_pids: session_pdict
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

  @doc """
  Shut down the app and every service `start_app/3` started.

  Sends `:shutdown` to the app loop and waits up to 500 ms for it to exit, killing it
  if it does not. Always returns `:ok`, including when a service has already stopped.
  """
  @spec stop_app(context()) :: :ok
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

    stop_session_pids(ctx)
    stop_services()
    :ok
  end

  defp stop_session_pids(%{session_pids: pids}) when is_map(pids) do
    Enum.each(pids, fn {_key, pid} -> stop_quietly(pid) end)
  end

  defp stop_session_pids(_ctx), do: :ok

  defp stop_services, do: stop_quietly(Drafter.Test.HeadlessDriver)

  defp stop_quietly(name_or_pid) do
    GenServer.stop(name_or_pid, :normal, 1000)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp propagate_pdict(pdict) do
    Enum.each(pdict, fn {key, val} -> Process.put(key, val) end)
  end

  defp run_headless_app(app_module, props) do
    Drafter.AppRegistry.register()
    Drafter.ThemeManager.register_app(self())
    Drafter.SkinManager.register_app(self())
    Drafter.ScreenManager.register_app(self())

    {width, height} = Drafter.Compositor.get_screen_size()
    screen_rect = %{x: 0, y: 0, width: width, height: height}

    AppLoop.start(app_module, screen_rect, props: props)
  end
end
