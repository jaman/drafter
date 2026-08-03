defmodule ReproApp do
  @moduledoc """
  Draws the last key it received, so each keystroke changes one row of the screen.
  """

  use Drafter.App

  def mount(_props), do: %{last: "none"}

  def render(state), do: vertical([label("LAST=#{state.last}")])

  def handle_event({:key, key}, state) do
    case Process.whereis(:repro_watcher) do
      nil -> :ok
      pid -> send(pid, {:app_event, key})
    end

    {:ok, %{state | last: to_string(key)}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

defmodule Repro do
  @moduledoc """
  Reports what a telnet client receives after the screen is already painted.

  Prints PASS when a single key repaints and the last key's frame reaches the client,
  FAIL when frames lag behind events.

  Run with `mix run scripts/repro_telnet_repaint_lag.exs`.
  """

  def run do
    Process.register(self(), :repro_watcher)

    port = 31_000 + :rand.uniform(900)
    {:ok, _} = Drafter.Server.start_telnet(ReproApp, port: port)
    Process.sleep(400)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 2000)

    painted = read_until(socket, "LAST=none", 24)
    IO.puts("initial paint: #{byte_size(painted)} bytes, visible=#{painted =~ "LAST=none"}")

    :gen_tcp.send(socket, "Q")
    one = read_until(socket, "LAST=Q", 20)
    IO.puts("after one key: #{byte_size(one)} bytes, repainted=#{one =~ "Q"}")
    IO.puts("  application saw the key: #{received_key?()}")

    for key <- ["W", "E", "R"] do
      :gen_tcp.send(socket, key)
      Process.sleep(200)
    end

    more = drain(socket, 8)

    IO.puts("after three more keys: #{byte_size(more)} bytes")
    IO.puts("  W visible=#{more =~ "W"}  E visible=#{more =~ "E"}  R visible=#{more =~ "R"}")
    IO.puts("")
    IO.puts(verdict(one =~ "Q", more =~ "R"))

    :gen_tcp.close(socket)
  end

  defp verdict(true, true), do: "PASS: a single key repaints and no frame is left unwritten."

  defp verdict(false, _last_visible?),
    do: "FAIL: one key produced no repaint; frames lag at least one event behind."

  defp verdict(_first?, false),
    do: "FAIL: the last key's frame was never written; frames lag one event behind."

  defp received_key? do
    receive do
      {:app_event, _key} -> true
    after
      500 -> false
    end
  end

  defp read_until(socket, pattern, attempts) do
    Enum.reduce_while(1..attempts, "", fn _attempt, acc ->
      case :gen_tcp.recv(socket, 0, 500) do
        {:ok, data} ->
          text = acc <> data
          if text =~ pattern, do: {:halt, text}, else: {:cont, text}

        {:error, _reason} ->
          {:cont, acc}
      end
    end)
  end

  defp drain(socket, attempts) do
    Enum.reduce(1..attempts, "", fn _attempt, acc ->
      case :gen_tcp.recv(socket, 0, 400) do
        {:ok, data} -> acc <> data
        {:error, _reason} -> acc
      end
    end)
  end
end

Repro.run()
