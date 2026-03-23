defmodule Drafter.Transport.Telnet do
  @moduledoc false

  alias Drafter.{Compositor, Event, EventHandler, ScreenManager, Session, ThemeManager}
  alias Drafter.Transport.TelnetDriver

  @spec start_link(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(app_module, opts \\ []) do
    port = Keyword.get(opts, :port, 2323)
    acceptor_opts = [app_module: app_module, server_opts: opts]
    pid = spawn_link(fn -> accept_loop(port, acceptor_opts) end)
    {:ok, pid}
  end

  defp accept_loop(port, opts) do
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [
        :binary,
        {:packet, :raw},
        {:active, false},
        {:reuseaddr, true}
      ])

    do_accept(listen_socket, opts)
  end

  defp do_accept(listen_socket, opts) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        spawn(fn -> handle_connection(client_socket, opts) end)
        do_accept(listen_socket, opts)

      {:error, :closed} ->
        :ok
    end
  end

  defp handle_connection(socket, opts) do
    app_module = Keyword.fetch!(opts, :app_module)
    server_opts = Keyword.get(opts, :server_opts, [])
    mode = Keyword.get(server_opts, :mode, :isolated)
    mount_props = Keyword.get(server_opts, :mount_props, %{})

    {:ok, driver_pid} = TelnetDriver.start_link(socket: socket)

    session_ctx = start_session_services(driver_pid)
    TelnetDriver.setup(driver_pid, session_ctx.event_manager)
    Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)

    session_opts = build_session_opts(app_module, mode, mount_props)

    try do
      Drafter.run_session(app_module, session_ctx, session_opts)
    after
      TelnetDriver.cleanup(driver_pid)
      stop_session_services(session_ctx)
    end
  end

  defp build_session_opts(app_module, :shared, mount_props) do
    shared_state = Session.SharedState.get_or_start(app_module)
    [mode: :shared, shared_state: shared_state] ++ Map.to_list(mount_props)
  end

  defp build_session_opts(_app_module, mode, mount_props) do
    [mode: mode] ++ Map.to_list(mount_props)
  end

  defp start_session_services(driver_pid) do
    {:ok, em} = Event.Manager.start_link(name: nil)

    {:ok, comp} =
      Compositor.start_link(
        name: nil,
        terminal_driver: {TelnetDriver, driver_pid},
        event_manager: em
      )

    {:ok, tm} = ThemeManager.start_link(name: nil)
    {:ok, eh} = EventHandler.start_link(name: nil)
    {:ok, sm} = ScreenManager.start_link(name: nil, event_handler: eh)

    %{event_manager: em, compositor: comp, screen_manager: sm, theme_manager: tm, event_handler: eh}
  end

  defp stop_session_services(ctx) do
    for {_, pid} <- ctx, is_pid(pid), Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end
  end
end
