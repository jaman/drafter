defmodule Drafter.Transport.SSH do
  @moduledoc false

  alias Drafter.{Compositor, Event, EventHandler, Logging, ScreenManager, Session, ThemeManager}
  alias Drafter.Transport.SSHDriver

  @doc """
  Start an `:ssh` daemon that runs `app_module` as each client's shell.

  ## Options

    * `:port` - TCP port. Default: `2222`.
    * `:ip` - interface address tuple to bind. Default: `{127, 0, 0, 1}`.
    * `:mode` - `:isolated` or `:shared`. Default: `:isolated`. `:shared` starts the
      app's shared-state server before the daemon.
    * `:auth` - `[{username, password}]` pairs, or `:anonymous` to accept anything.
      Default: `[{"admin", "admin"}]`.
    * `:system_dir` - host-key directory. Default: `drafter_ssh` under the system
      temp directory, populated by `ssh-keygen` on first use.
    * `:mount_props` - map handed to each session's `mount/1`. Default: `%{}`. The
      connecting username is merged in under `:username` as a string.

  """
  @spec start_link(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(app_module, opts \\ []) do
    port = Keyword.get(opts, :port, 2222)
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})
    mode = Keyword.get(opts, :mode, :isolated)
    mount_props = Keyword.get(opts, :mount_props, %{})
    system_dir = opts |> Keyword.get(:system_dir) |> resolve_system_dir()

    auth = Keyword.get(opts, :auth, [{"admin", "admin"}])

    if mode == :shared do
      Session.SharedState.get_or_start(app_module)
    end

    shell_fun = fn username, _peer_addr ->
      spawn(fn -> do_start_shell(app_module, mode, mount_props, username) end)
    end

    daemon_opts =
      [
        ifaddr: ip,
        system_dir: to_charlist(system_dir),
        parallel_login: true,
        shell: shell_fun
      ] ++ auth_opts(auth)

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
    session_ctx = put_probed_protocol(session_ctx, SSHDriver.probe(driver_pid))
    Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)

    session_opts = build_session_opts(app_module, mode, full_props)

    try do
      Drafter.run_session(app_module, session_ctx, session_opts)
    after
      SSHDriver.cleanup(driver_pid)
      stop_session_services(session_ctx)
      exit(:normal)
    end
  end

  defp build_session_opts(app_module, :shared, mount_props) do
    shared_state = Session.SharedState.get_or_start(app_module)
    [mode: :shared, shared_state: shared_state, props: mount_props]
  end

  defp build_session_opts(_app_module, mode, mount_props) do
    [mode: mode, props: mount_props]
  end

  defp put_probed_protocol(session_ctx, {:ok, protocol}),
    do: Map.put(session_ctx, :terminal_protocol, protocol)

  defp put_probed_protocol(session_ctx, :unprobed), do: session_ctx

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

    %{
      event_manager: em,
      compositor: comp,
      screen_manager: sm,
      theme_manager: tm,
      event_handler: eh
    }
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

  defp auth_opts(:anonymous) do
    [
      auth_methods: ~c"password",
      pwdfun: fn _user, _password, _peer_addr, _state -> true end
    ]
  end

  defp auth_opts(pairs) when is_list(pairs) do
    user_passwords =
      Enum.map(pairs, fn {u, p} -> {to_charlist(u), to_charlist(p)} end)

    [
      auth_methods: ~c"password",
      user_passwords: user_passwords
    ]
  end

  defp generate_host_key(dir) do
    System.cmd(
      "ssh-keygen",
      ["-t", "rsa", "-b", "2048", "-f", Path.join(dir, "ssh_host_rsa_key"), "-N", ""],
      stderr_to_stdout: true
    )
  end
end
