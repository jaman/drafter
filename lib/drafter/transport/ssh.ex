defmodule Drafter.Transport.SSH do
  @moduledoc false

  alias Drafter.{Compositor, Event, EventHandler, Logging, ScreenManager, Session, ThemeManager}
  alias Drafter.Transport.SSHDriver

  @spec start_link(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(app_module, opts \\ []) do
    port = Keyword.get(opts, :port, 2222)
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})
    mode = Keyword.get(opts, :mode, :isolated)
    mount_props = Keyword.get(opts, :mount_props, %{})
    system_dir = opts |> Keyword.get(:system_dir) |> resolve_system_dir()

    user_passwords =
      opts
      |> Keyword.get(:auth, [{"admin", "admin"}])
      |> Enum.map(fn {u, p} -> {to_charlist(u), to_charlist(p)} end)

    if mode == :shared do
      Session.SharedState.get_or_start(app_module)
    end

    shell_fun = fn username, _peer_addr ->
      spawn(fn -> do_start_shell(app_module, mode, mount_props, username) end)
    end

    daemon_opts = [
      ifaddr: ip,
      system_dir: to_charlist(system_dir),
      auth_methods: ~c"password",
      user_passwords: user_passwords,
      parallel_login: true,
      shell: shell_fun
    ]

    case :ssh.daemon(port, daemon_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_start_shell(app_module, mode, mount_props, username) do
    Process.flag(:trap_exit, true)
    _ = Logging.setup()
    gl = Process.group_leader()
    username_str = to_string(username)
    full_props = Map.put(mount_props, :username, username_str)

    {:ok, driver_pid} = SSHDriver.start_link(group_leader: gl)

    session_ctx = start_session_services(driver_pid)
    SSHDriver.setup(driver_pid, session_ctx.event_manager)
    Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)

    session_opts = build_session_opts(app_module, mode, full_props)

    try do
      Drafter.run_session(app_module, session_ctx, session_opts)
    after
      SSHDriver.cleanup(driver_pid)
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
        terminal_driver: {SSHDriver, driver_pid},
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

  defp resolve_system_dir(nil) do
    dir = Path.join(System.tmp_dir!(), "drafter_ssh")
    File.mkdir_p!(dir)

    unless File.exists?(Path.join(dir, "ssh_host_rsa_key")) do
      generate_host_key(dir)
    end

    dir
  end

  defp resolve_system_dir(dir), do: dir

  defp generate_host_key(dir) do
    System.cmd(
      "ssh-keygen",
      ["-t", "rsa", "-b", "2048", "-f", Path.join(dir, "ssh_host_rsa_key"), "-N", ""],
      stderr_to_stdout: true
    )
  end
end
