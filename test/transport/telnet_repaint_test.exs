defmodule Drafter.Transport.TelnetRepaintTest do
  @moduledoc """
  What a telnet client receives, over a real socket.

  Covers that a keystroke repaints, and that a session registers a loop while it
  runs and leaves none behind once it closes.
  """

  use ExUnit.Case, async: false

  alias Drafter.TestSupport.ScreenModel

  defmodule Echo do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{last: "none"}
    def render(state), do: vertical([label("LAST=#{state.last}")])
    def handle_event({:key, key}, state), do: {:ok, %{state | last: to_string(key)}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp connect do
    port = 34_000 + :rand.uniform(1500)
    {:ok, server} = Drafter.Server.start_telnet(Echo, port: port)
    Process.sleep(400)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 2000)
    on_exit(fn -> teardown(socket, server) end)

    {socket, server}
  end

  defp teardown(socket, server) do
    :gen_tcp.close(socket)

    if Process.alive?(server) do
      Process.unlink(server)
      Process.exit(server, :kill)
    end

    await_no_live_loops()
  end

  defp await_live_loop(attempts \\ 40)
  defp await_live_loop(0), do: false

  defp await_live_loop(attempts) do
    if live_loops() != [] do
      true
    else
      Process.sleep(25)
      await_live_loop(attempts - 1)
    end
  end

  defp await_no_live_loops(attempts \\ 40)
  defp await_no_live_loops(0), do: :ok

  defp await_no_live_loops(attempts) do
    if live_loops() == [] do
      :ok
    else
      Process.sleep(25)
      await_no_live_loops(attempts - 1)
    end
  end

  defp live_loops do
    :drafter_app_registry
    |> :ets.tab2list()
    |> Enum.filter(fn
      {{:loop, _session}, pid} -> Process.alive?(pid)
      _ -> false
    end)
  rescue
    ArgumentError -> []
  end

  defp read_until(socket, seen, pattern, attempts \\ 20) do
    Enum.reduce_while(1..attempts, seen, fn _attempt, acc ->
      accumulate(:gen_tcp.recv(socket, 0, 400), acc, pattern)
    end)
  end

  defp accumulate({:error, _reason}, acc, _pattern), do: {:cont, acc}

  defp accumulate({:ok, data}, acc, pattern) do
    text = acc <> data
    if shows?(text, pattern), do: {:halt, text}, else: {:cont, text}
  end

  defp shows?(bytes, text), do: [bytes] |> ScreenModel.apply() |> ScreenModel.shows?(text)

  @tag :telnet
  test "a single keystroke repaints" do
    {socket, _server} = connect()
    seen = read_until(socket, "", "LAST=none")
    assert shows?(seen, "LAST=none")

    :gen_tcp.send(socket, "Q")

    assert shows?(read_until(socket, seen, "LAST=Q"), "LAST=Q"),
           "one keystroke produced no repaint; frames are lagging behind events"
  end

  @tag :telnet
  test "a closed session leaves no loop behind" do
    before = live_loops()
    {socket, server} = connect()
    assert shows?(read_until(socket, "", "LAST=none"), "LAST=none")
    assert await_live_loop()

    teardown(socket, server)

    assert await_loops_gone(before),
           "this session's loop outlived it: #{inspect(live_loops() -- before)}"
  end

  defp await_loops_gone(baseline, attempts \\ 60)
  defp await_loops_gone(baseline, 0), do: live_loops() -- baseline == []

  defp await_loops_gone(baseline, attempts) do
    if live_loops() -- baseline == [] do
      true
    else
      Process.sleep(25)
      await_loops_gone(baseline, attempts - 1)
    end
  end
end
