defmodule Drafter.Transport.SSH do
  @moduledoc false

  alias Drafter.{
    Accounts,
    Compositor,
    Event,
    EventHandler,
    Logging,
    ScreenManager,
    Session,
    ThemeManager
  }

  alias Drafter.Accounts.RegisterApp
  alias Drafter.Transport.SSHDriver

  @max_failures 3

  @doc """
  Start an `:ssh` daemon that runs `app_module` as each client's shell.

  ## Options

    * `:port` - TCP port. Default: `2222`.
    * `:ip` - what to bind: an IPv4 or IPv6 address tuple, `{0, 0, 0, 0}` for every
      IPv4 interface, `{0, 0, 0, 0, 0, 0, 0, 0}` for every IPv6 interface, `:any` for
      both families on every interface, or a list of any of these, each bound by a
      daemon of its own on the same port. Default: `{127, 0, 0, 1}`.
    * `:mode` - `:isolated` or `:shared`. Default: `:isolated`. `:shared` starts the
      app's shared-state server before the daemon.
    * `:auth` - `[{username, password}]` pairs, `[{username, password, props}]`
      triples whose `props` map is merged into that user's mount props,
      `{:accounts, server}` to check passwords against a `Drafter.Accounts`
      server, or `:anonymous` to accept anything. Default: `[{"admin", "admin"}]`.
    * `:register_as` - with `{:accounts, server}`, a username that opens the
      registration form instead of an account. Default `nil`: no registration.
    * `:register_app` - `{module, props}`, the app the registration form runs
      (`props` merged over `accounts:` and `notify:`). Default
      `{Drafter.Accounts.RegisterApp, %{}}`.
    * `:tunnel` - `boolean()`, default `false`. `true` lets a client ask the daemon
      to listen on a port and forward its connections back to the client, which is
      `ssh -R`.
    * `:system_dir` - host-key directory. Default: `drafter_ssh` under the system
      temp directory, populated by `ssh-keygen` on first use.
    * `:mount_props` - map handed to each session's `mount/1`. Default: `%{}`. The
      connecting username is merged in under `:username` as a string.

  """
  @type bind :: :inet.ip_address() | :any

  @spec start_link(module(), keyword()) :: {:ok, pid() | [pid()]} | {:error, term()}
  def start_link(app_module, opts \\ []) do
    port = Keyword.get(opts, :port, 2222)
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})
    mode = Keyword.get(opts, :mode, :isolated)
    mount_props = Keyword.get(opts, :mount_props, %{})
    system_dir = opts |> Keyword.get(:system_dir) |> resolve_system_dir()

    auth = Keyword.get(opts, :auth, [{"admin", "admin"}])
    user_props = user_props(auth)
    tunnel = Keyword.get(opts, :tunnel, false)

    registration =
      registration(
        auth,
        Keyword.get(opts, :register_as),
        Keyword.get(opts, :register_app, {RegisterApp, %{}})
      )

    if mode == :shared do
      Session.SharedState.get_or_start(app_module)
    end

    shell_fun = fn username, _peer_addr ->
      props = Map.merge(mount_props, Map.get(user_props, to_string(username), %{}))
      spawn(fn -> do_start_shell(app_module, mode, props, username, registration) end)
    end

    daemon_opts =
      [
        system_dir: to_charlist(system_dir),
        parallel_login: true,
        tcpip_tunnel_out: tunnel,
        shell: shell_fun
      ] ++ auth_opts(auth, registration)

    case ip do
      binds when is_list(binds) -> daemons(binds, port, daemon_opts)
      bind -> :ssh.daemon(port, bind_opts(bind) ++ daemon_opts)
    end
  end

  @doc "Stop what `start_link/2` returned: one daemon, or every daemon of a list."
  @spec stop(pid() | [pid()]) :: :ok
  def stop(daemons) when is_list(daemons), do: Enum.each(daemons, &:ssh.stop_daemon/1)
  def stop(daemon), do: :ssh.stop_daemon(daemon)

  defp daemons(binds, port, daemon_opts) do
    Enum.reduce_while(binds, {:ok, []}, fn bind, {:ok, started} ->
      case :ssh.daemon(port, bind_opts(bind) ++ daemon_opts) do
        {:ok, pid} ->
          {:cont, {:ok, started ++ [pid]}}

        {:error, reason} ->
          stop(started)
          {:halt, {:error, {bind, reason}}}
      end
    end)
  end

  defp bind_opts(:any), do: [ifaddr: {0, 0, 0, 0, 0, 0, 0, 0}, inet: :inet6, ipv6_v6only: false]
  defp bind_opts(ip) when tuple_size(ip) == 8, do: [ifaddr: ip, inet: :inet6, ipv6_v6only: true]
  defp bind_opts(ip) when tuple_size(ip) == 4, do: [ifaddr: ip, inet: :inet]

  defp do_start_shell(app_module, mode, mount_props, username, registration) do
    Process.flag(:trap_exit, true)
    _ = Logging.setup()
    gl = Process.group_leader()
    username_str = to_string(username)

    {:ok, driver_pid} = SSHDriver.start_link(group_leader: gl, session: self())

    session_ctx = start_session_services(driver_pid)
    Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)
    SSHDriver.setup(driver_pid, session_ctx.event_manager, Drafter.terminal_opts(app_module))
    session_ctx = put_probed_protocol(session_ctx, SSHDriver.probe(driver_pid))

    try do
      case account_props(registration, username_str, session_ctx) do
        {:ok, account} ->
          full_props =
            mount_props |> Map.merge(account.props) |> Map.put(:username, account.username)

          Drafter.run_session(
            app_module,
            session_ctx,
            build_session_opts(app_module, mode, full_props)
          )

        :cancelled ->
          :ok
      end
    after
      SSHDriver.cleanup(driver_pid)
      stop_session_services(session_ctx)
      exit(:normal)
    end
  end

  defp account_props(nil, username, _session_ctx), do: {:ok, %{username: username, props: %{}}}

  defp account_props(%{register_as: register_as} = registration, username, session_ctx)
       when username == register_as do
    {app, extra} = registration.register_app
    props = Map.merge(%{accounts: registration.accounts, notify: self()}, extra)
    Drafter.run_session(app, session_ctx, mode: :isolated, props: props)

    receive do
      {:drafter_registration, {:ok, account}} -> {:ok, account}
      {:drafter_registration, :cancelled} -> :cancelled
    after
      0 -> :cancelled
    end
  end

  defp account_props(registration, username, _session_ctx) do
    case Accounts.fetch(registration.accounts, username) do
      {:ok, account} -> {:ok, account}
      :error -> :cancelled
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

  defp registration({:accounts, accounts}, register_as, register_app),
    do: %{accounts: accounts, register_as: register_as, register_app: register_app}

  defp registration(_auth, _register_as, _register_app), do: nil

  defp auth_opts({:accounts, accounts}, registration) do
    [
      auth_methods: ~c"password",
      pwdfun: fn user, password, {ip, _port}, state ->
        check_password(
          accounts,
          registration,
          to_string(user),
          to_string(password),
          ip,
          failures(state)
        )
      end
    ]
  end

  defp auth_opts(auth, _registration), do: auth_opts(auth)

  defp failures(count) when is_integer(count), do: count
  defp failures(_none_yet), do: 0

  defp check_password(_accounts, %{register_as: register_as}, user, _password, _ip, _failures)
       when user == register_as,
       do: true

  defp check_password(accounts, _registration, user, password, ip, failures) do
    case Accounts.authenticate(accounts, user, password, peer: ip) do
      {:ok, _account} -> true
      _refused when failures + 1 >= @max_failures -> :disconnect
      _refused -> {false, failures + 1}
    end
  end

  defp auth_opts(:anonymous) do
    [
      auth_methods: ~c"password",
      pwdfun: fn _user, _password, _peer_addr, _state -> true end
    ]
  end

  defp auth_opts(entries) when is_list(entries) do
    user_passwords =
      Enum.map(entries, fn entry ->
        {username, password} = credentials(entry)
        {to_charlist(username), to_charlist(password)}
      end)

    [
      auth_methods: ~c"password",
      user_passwords: user_passwords
    ]
  end

  defp credentials({username, password}), do: {username, password}
  defp credentials({username, password, _props}), do: {username, password}

  defp user_props(:anonymous), do: %{}
  defp user_props({:accounts, _accounts}), do: %{}

  defp user_props(entries) do
    for {username, _password, props} <- entries, into: %{}, do: {to_string(username), props}
  end

  defp generate_host_key(dir) do
    System.cmd(
      "ssh-keygen",
      ["-t", "rsa", "-b", "2048", "-f", Path.join(dir, "ssh_host_rsa_key"), "-N", ""],
      stderr_to_stdout: true
    )
  end
end
