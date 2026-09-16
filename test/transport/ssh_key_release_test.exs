defmodule Drafter.Transport.SSHKeyReleaseTest do
  @moduledoc """
  An app that asks for key releases gets the kitty keyboard protocol turned on in
  its ssh clients' terminals, sees their confirmation and their releases, and has
  the protocol turned off again when the session ends.
  """

  use ExUnit.Case, async: false

  alias Drafter.Terminal.KittyKeyboard

  @moduletag :ssh
  @moduletag timeout: 60_000

  defmodule Held do
    @moduledoc false
    use Drafter.App, key_release: true

    def mount(props), do: %{props: props, released: nil, supported: false}
    def render(state), do: vertical([label("released=#{inspect(state.released)}")])

    def handle_event({:key_up, key, _mods}, state), do: {:ok, %{state | released: key}}
    def handle_event({:key_release_support, true}, state), do: {:ok, %{state | supported: true}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    :ssh.start()
    port = 39_000 + :rand.uniform(900)

    {:ok, daemon} =
      Drafter.Server.start_ssh(Held,
        port: port,
        tunnel: true,
        auth: [{"admin", "admin"}, {"alice", "pw", %{pulse_port: 24_713}}]
      )

    Process.sleep(500)
    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    {:ok, port: port}
  end

  defp connect(port, user, password) do
    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: to_charlist(user),
          password: to_charlist(password),
          silently_accept_hosts: true,
          user_interaction: false,
          auth_methods: ~c"password"
        ],
        5000
      )

    {:ok, channel} = :ssh_connection.session_channel(conn, 5000)
    :ssh_connection.ptty_alloc(conn, channel, term: ~c"xterm", width: 80, height: 24)
    :ok = :ssh_connection.shell(conn, channel)
    {conn, channel}
  end

  defp collect_until(conn, channel, marker, seen \\ "") do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, 0, data}} ->
        seen = seen <> data

        if String.contains?(seen, marker),
          do: {:ok, seen},
          else: collect_until(conn, channel, marker, seen)

      {:ssh_cm, ^conn, _other} ->
        collect_until(conn, channel, marker, seen)
    after
      5_000 -> {:timeout, seen}
    end
  end

  defp loop_pid(attempts \\ 60)
  defp loop_pid(0), do: nil

  defp loop_pid(attempts) do
    case live_loops() do
      [{_key, pid} | _] ->
        pid

      [] ->
        Process.sleep(50)
        loop_pid(attempts - 1)
    end
  end

  defp live_loops do
    :drafter_app_registry
    |> :ets.tab2list()
    |> Enum.filter(fn
      {{:loop, _session}, pid} when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end)
  rescue
    ArgumentError -> []
  end

  defp loop_state(pid), do: Drafter.Test.get_state(%{app_pid: pid})

  defp await(fun, attempts \\ 40) do
    case fun.() do
      {:ok, value} ->
        value

      _ when attempts > 0 ->
        Process.sleep(50)
        await(fun, attempts - 1)

      other ->
        flunk("gave up waiting: #{inspect(other)}")
    end
  end

  test "the protocol is pushed and queried before the graphics probe", %{port: port} do
    {conn, channel} = connect(port, "admin", "admin")

    {:ok, seen} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    {pushed, _} = :binary.match(seen, KittyKeyboard.push())
    {queried, _} = :binary.match(seen, KittyKeyboard.query())
    {probed, _} = :binary.match(seen, FrenchCurve.Capability.probe())
    assert pushed < queried and queried < probed

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "a confirming terminal's releases reach the app and the session knows", %{port: port} do
    {conn, channel} = connect(port, "admin", "admin")
    {:ok, _seen} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    :ssh_connection.send(conn, channel, "\e[?27u\e[?62;22c")

    pid = loop_pid()
    assert pid

    :ssh_connection.send(conn, channel, "\e[97;1:3u")

    assert :ok ==
             await(fn ->
               with {:dictionary, dict} <- Process.info(pid, :dictionary),
                    true <- Keyword.get(dict, :drafter_key_release, false) do
                 {:ok, :ok}
               else
                 _ -> :not_yet
               end
             end)

    state =
      await(fn ->
        case loop_state(pid) do
          %{released: :a} = state -> {:ok, state}
          _ -> :not_yet
        end
      end)

    assert state.supported

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "the protocol is popped when the session ends", %{port: port} do
    {conn, channel} = connect(port, "admin", "admin")
    {:ok, _seen} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    :ssh_connection.send(conn, channel, "\e[?62;22c")
    pid = loop_pid()

    :ssh_connection.send(conn, channel, "\x11")

    assert {:ok, _} = collect_until(conn, channel, KittyKeyboard.pop())
    refute await(fn -> if Process.alive?(pid), do: :alive, else: {:ok, false} end)

    :ssh.close(conn)
  end

  test "a user's own props reach mount", %{port: port} do
    {conn, channel} = connect(port, "alice", "pw")
    {:ok, _seen} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    :ssh_connection.send(conn, channel, "\e[?62;22c")
    pid = loop_pid()

    state = await(fn -> {:ok, loop_state(pid)} end)
    assert state.props.username == "alice"
    assert state.props.pulse_port == 24_713

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "the daemon accepts a reverse forward when tunnels are on", %{port: port} do
    {conn, channel} = connect(port, "admin", "admin")
    {:ok, _seen} = collect_until(conn, channel, FrenchCurve.Capability.probe())

    assert {:ok, _port} =
             :ssh.tcpip_tunnel_from_server(conn, ~c"127.0.0.1", 0, ~c"127.0.0.1", 1, 5000)

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end
end
