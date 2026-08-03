defmodule Drafter.Session.Worker do
  @moduledoc false

  use GenServer

  alias Drafter.{Compositor, Event, EventHandler, ScreenManager, ThemeManager, Transport}

  @doc """
  Start a session worker, which owns one session's services and app process.

  Starts and links a private `Drafter.Event.Manager`, `Drafter.Compositor`,
  `Drafter.ThemeManager`, `Drafter.EventHandler` and the screen manager, then
  spawns the app under `Drafter.run_session/3`. The worker stops normally as soon as
  the app process goes down.

  ## Options

    * `:app_module` - the `Drafter.App` module to run. Required; missing raises.
    * `:driver_pid` - pid of the transport driver the session renders through.
      Required; missing raises. Linked to the worker.
    * `:mode` - `:isolated` or `:shared`, passed through to the session. Default:
      `:isolated`.
    * `:shared_state` - pid of a shared-state server, passed through
      to the session. Default: `nil`.
    * `:mount_props` - map of mount props, flattened into the session options.
      Default: `%{}`.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    app_module = Keyword.fetch!(opts, :app_module)
    driver_pid = Keyword.fetch!(opts, :driver_pid)
    mode = Keyword.get(opts, :mode, :isolated)
    shared_state = Keyword.get(opts, :shared_state)
    mount_props = Keyword.get(opts, :mount_props, %{})

    {:ok, em} = Event.Manager.start_link(name: nil)

    {:ok, comp} =
      Compositor.start_link(
        name: nil,
        terminal_driver: {Transport.SessionDriver, driver_pid},
        event_manager: em
      )

    {:ok, tm} = ThemeManager.start_link(name: nil)
    {:ok, eh} = EventHandler.start_link(name: nil)
    {:ok, sm} = ScreenManager.start_link(name: nil, event_handler: eh)

    Process.link(em)
    Process.link(comp)
    Process.link(sm)
    Process.link(tm)
    Process.link(eh)
    Process.link(driver_pid)

    session_ctx = %{
      event_manager: em,
      compositor: comp,
      screen_manager: sm,
      theme_manager: tm,
      event_handler: eh
    }

    session_opts = [mode: mode, shared_state: shared_state] ++ Map.to_list(mount_props)

    app_pid =
      spawn_link(fn ->
        Drafter.run_session(app_module, session_ctx, session_opts)
      end)

    Transport.SessionDriver.set_event_manager(driver_pid, em)
    Event.Manager.subscribe_to(em, app_pid, :all)

    Process.monitor(app_pid)

    {:ok, %{app_pid: app_pid, session_ctx: session_ctx, driver_pid: driver_pid}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
