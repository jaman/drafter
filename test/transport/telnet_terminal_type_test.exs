defmodule Drafter.Transport.TelnetTerminalTypeTest do
  @moduledoc """
  Telnet TERMINAL-TYPE negotiation, over a real socket.

  Telnet carries no environment, so the terminal a client is running is asked for
  rather than read: the server offers `DO TERMINAL-TYPE`, and a client that answers
  `WILL` is sent a `SEND` subnegotiation and replies with the name. That name is
  what the session detects a graphics protocol from, so a client on kitty gets
  images whatever the host serving it is running under.
  """

  use ExUnit.Case, async: false

  @iac 255
  @telnet_do 253
  @telnet_will 251
  @telnet_sb 250
  @telnet_se 240
  @telnet_ttype 24
  @telnet_ttype_is 0
  @telnet_ttype_send 1

  defmodule Echo do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{}
    def render(_state), do: vertical([label("ready")])
  end

  defp connect do
    port = 35_600 + :rand.uniform(1500)
    {:ok, server} = Drafter.Server.start_telnet(Echo, port: port)
    Process.sleep(400)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 2000)

    on_exit(fn ->
      :gen_tcp.close(socket)

      if Process.alive?(server) do
        Process.unlink(server)
        Process.exit(server, :kill)
      end
    end)

    socket
  end

  defp recv_until(socket, matcher, acc \\ "", attempts \\ 30)

  defp recv_until(_socket, _matcher, acc, 0), do: {:timeout, acc}

  defp recv_until(socket, matcher, acc, attempts) do
    case :gen_tcp.recv(socket, 0, 500) do
      {:ok, data} ->
        acc = acc <> data
        if matcher.(acc), do: {:ok, acc}, else: recv_until(socket, matcher, acc, attempts - 1)

      {:error, :timeout} ->
        if matcher.(acc), do: {:ok, acc}, else: recv_until(socket, matcher, acc, attempts - 1)

      {:error, reason} ->
        {:error, reason, acc}
    end
  end

  defp contains?(haystack, needle), do: :binary.match(haystack, needle) != :nomatch

  defp live_loop do
    :drafter_app_registry
    |> :ets.tab2list()
    |> Enum.find_value(fn
      {{:loop, _session}, pid} when is_pid(pid) -> if Process.alive?(pid), do: pid
      _ -> nil
    end)
  rescue
    ArgumentError -> nil
  end

  defp await_loop_env(attempts \\ 60)
  defp await_loop_env(0), do: nil

  defp await_loop_env(attempts) do
    with loop when is_pid(loop) <- live_loop(),
         {:dictionary, dictionary} <- Process.info(loop, :dictionary),
         env when is_map(env) <- Keyword.get(dictionary, :drafter_terminal_env) do
      env
    else
      _ ->
        Process.sleep(50)
        await_loop_env(attempts - 1)
    end
  end

  test "the server offers TERMINAL-TYPE and asks a client that accepts" do
    socket = connect()

    assert {:ok, offer} =
             recv_until(socket, &contains?(&1, <<@iac, @telnet_do, @telnet_ttype>>))

    assert contains?(offer, <<@iac, @telnet_do, @telnet_ttype>>),
           "the server never offered TERMINAL-TYPE"

    :gen_tcp.send(socket, <<@iac, @telnet_will, @telnet_ttype>>)

    assert {:ok, request} =
             recv_until(
               socket,
               &contains?(
                 &1,
                 <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_send, @iac, @telnet_se>>
               )
             )

    assert contains?(
             request,
             <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_send, @iac, @telnet_se>>
           ),
           "the server never asked for the terminal type"
  end

  test "the name the client answers is what the session detects from" do
    socket = connect()

    recv_until(socket, &contains?(&1, <<@iac, @telnet_do, @telnet_ttype>>))
    :gen_tcp.send(socket, <<@iac, @telnet_will, @telnet_ttype>>)

    recv_until(
      socket,
      &contains?(&1, <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_send, @iac, @telnet_se>>)
    )

    :gen_tcp.send(
      socket,
      <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_is>> <>
        "XTERM-KITTY" <> <<@iac, @telnet_se>>
    )

    env = await_loop_env()

    assert env["TERM"] == "xterm-kitty", "the answered terminal type reached the session"
    assert FrenchCurve.Capability.detect(env) == :kitty
  end

  defp await_loop_protocol(attempts \\ 60)
  defp await_loop_protocol(0), do: :never_set

  defp await_loop_protocol(attempts) do
    with loop when is_pid(loop) <- live_loop(),
         {:dictionary, dictionary} <- Process.info(loop, :dictionary),
         {:ok, protocol} <- Keyword.get(dictionary, :drafter_terminal_protocol) do
      protocol
    else
      _ ->
        Process.sleep(50)
        await_loop_protocol(attempts - 1)
    end
  end

  test "a client that answers the graphics probe is taken at its word" do
    socket = connect()

    assert {:ok, _} = recv_until(socket, &contains?(&1, FrenchCurve.Capability.probe()))

    :gen_tcp.send(socket, "\eP>|kitty(0.32.2)\e\\\e[?62;22c")

    assert await_loop_protocol() == :kitty
  end

  test "a client reporting sixel among its attributes gets sixel" do
    socket = connect()

    recv_until(socket, &contains?(&1, FrenchCurve.Capability.probe()))
    :gen_tcp.send(socket, "\e[?62;4;6c")

    assert await_loop_protocol() == :sixel
  end

  test "a client that answers with no graphics is not second-guessed" do
    socket = connect()

    recv_until(socket, &contains?(&1, FrenchCurve.Capability.probe()))
    :gen_tcp.send(socket, "\e[?62;22c")

    assert await_loop_protocol() == nil
  end

  test "a client that never answers still gets a session" do
    socket = connect()

    recv_until(socket, &contains?(&1, <<@iac, @telnet_do, @telnet_ttype>>))

    assert await_loop_env() == %{},
           "a silent client should start with an empty terminal environment"
  end
end
