defmodule Drafter.Transport.SSHSessionTest do
  @moduledoc """
  Session lifecycle over a real SSH connection.

  Covers that a connected session registers a loop, and that the loop is gone
  after both a clean disconnect and an abrupt client death.
  """

  use ExUnit.Case, async: false

  @moduletag :ssh
  @moduletag timeout: 60_000

  defmodule Echo do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{last: "none"}
    def render(state), do: vertical([label("LAST=#{state.last}")])
    def handle_event({:key, key}, state), do: {:ok, %{state | last: to_string(key)}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    :ssh.start()
    port = 39_000 + :rand.uniform(900)
    {:ok, daemon} = Drafter.Server.start_ssh(Echo, port: port)
    Process.sleep(500)

    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    {:ok, port: port}
  end

  defp open(port) do
    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: ~c"admin",
          password: ~c"admin",
          silently_accept_hosts: true,
          user_interaction: false,
          auth_methods: ~c"password"
        ],
        5000
      )

    {:ok, channel} = :ssh_connection.session_channel(conn, 5000)
    :ssh_connection.ptty_alloc(conn, channel, term: ~c"xterm", width: 80, height: 24)
    :ok = :ssh_connection.shell(conn, channel)

    assert await_loops(&(&1 > 0)), "the ssh session registered no loop"

    {conn, channel}
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

  defp await_loops(predicate, attempts \\ 60)
  defp await_loops(_predicate, 0), do: false

  defp await_loops(predicate, attempts) do
    if predicate.(length(live_loops())) do
      true
    else
      Process.sleep(50)
      await_loops(predicate, attempts - 1)
    end
  end

  test "a connected session registers a loop", %{port: port} do
    {conn, channel} = open(port)

    assert live_loops() != []

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "a clean disconnect leaves no loop behind", %{port: port} do
    {conn, channel} = open(port)

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)

    assert await_loops(&(&1 == 0)),
           "a closed ssh session left #{length(live_loops())} loop(s) registered"
  end

  defp loop_protocol(attempts \\ 60)
  defp loop_protocol(0), do: :never_set

  defp loop_protocol(attempts) do
    with [{_key, loop} | _] <- live_loops(),
         {:dictionary, dictionary} <- Process.info(loop, :dictionary),
         {:ok, protocol} <- Keyword.get(dictionary, :drafter_terminal_protocol) do
      protocol
    else
      _ ->
        Process.sleep(50)
        loop_protocol(attempts - 1)
    end
  end

  defp open_answering(port, reply) do
    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: ~c"admin",
          password: ~c"admin",
          silently_accept_hosts: true,
          user_interaction: false,
          auth_methods: ~c"password"
        ],
        5000
      )

    {:ok, channel} = :ssh_connection.session_channel(conn, 5000)
    :ssh_connection.ptty_alloc(conn, channel, term: ~c"xterm", width: 80, height: 24)
    :ok = :ssh_connection.shell(conn, channel)

    assert answer_probe(conn, channel, reply), "the server never sent the graphics probe"

    {conn, channel}
  end

  defp answer_probe(conn, channel, reply, seen \\ "") do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, 0, data}} ->
        seen = seen <> data

        if String.contains?(seen, FrenchCurve.Capability.probe()) do
          :ssh_connection.send(conn, channel, reply)
          true
        else
          answer_probe(conn, channel, reply, seen)
        end

      {:ssh_cm, ^conn, _other} ->
        answer_probe(conn, channel, reply, seen)
    after
      5_000 -> false
    end
  end

  test "a client answering the graphics probe is taken at its word", %{port: port} do
    {conn, channel} = open_answering(port, "\eP>|kitty(0.32.2)\e\\\e[?62;22c")

    assert loop_protocol() == :kitty

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "a client reporting sixel among its attributes gets sixel", %{port: port} do
    {conn, channel} = open_answering(port, "\e[?62;4;6c")

    assert loop_protocol() == :sixel

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "a client with no graphics is recorded as having none", %{port: port} do
    {conn, channel} = open_answering(port, "\e[?62;22c")

    assert loop_protocol() == nil

    :ssh_connection.close(conn, channel)
    :ssh.close(conn)
  end

  test "an abrupt client death leaves no loop behind", %{port: port} do
    {conn, _channel} = open(port)

    Process.exit(conn, :kill)

    assert await_loops(&(&1 == 0)),
           "an abandoned ssh session left #{length(live_loops())} loop(s) registered"
  end
end
