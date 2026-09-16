defmodule Drafter.Transport.SlowLinkTest do
  @moduledoc """
  A session driver's write blocks until the bytes are on the wire, so a link
  that cannot keep up makes the compositor fall behind by one frame at most:
  frames rendered meanwhile merge into its buffer and go out as one diff.
  """

  use ExUnit.Case, async: false

  alias Drafter.Compositor
  alias Drafter.Draw.Strip
  alias Drafter.Transport.{SSHDriver, TelnetDriver}

  defmodule SlowDriver do
    @moduledoc false
    use GenServer

    def start_link(delay), do: GenServer.start_link(__MODULE__, delay)

    def write(pid, data), do: GenServer.call(pid, {:driver_write, data}, :infinity)

    def get_size(_pid), do: {80, 24}

    def writes(pid), do: GenServer.call(pid, :writes)

    @impl GenServer
    def init(delay), do: {:ok, %{delay: delay, writes: []}}

    @impl GenServer
    def handle_call({:driver_write, data}, _from, state) do
      Process.sleep(state.delay)
      {:reply, :ok, %{state | writes: [IO.iodata_to_binary(data) | state.writes]}}
    end

    def handle_call(:writes, _from, state), do: {:reply, Enum.reverse(state.writes), state}
  end

  setup do
    {:ok, driver} = SlowDriver.start_link(40)
    unique = System.unique_integer([:positive])
    manager = :"events_#{unique}"
    start_supervised!({Drafter.Event.Manager, name: manager}, id: manager)

    {:ok, compositor} =
      Compositor.start_link(
        name: nil,
        terminal_driver: {SlowDriver, driver},
        event_manager: manager
      )

    {:ok, driver: driver, compositor: compositor}
  end

  defp paint(compositor, text) do
    GenServer.cast(compositor, {:render_strips, [Strip.from_text(text)], 0, 0})
  end

  test "a burst faster than the link becomes a few frames, the last one complete",
       %{driver: driver, compositor: compositor} do
    for n <- 1..30 do
      paint(compositor, "frame #{n}")
      Process.sleep(2)
    end

    Process.sleep(300)
    :sys.get_state(compositor)
    writes = SlowDriver.writes(driver)

    assert length(writes) < 30
    assert writes |> List.last() |> String.contains?("frame 30")

    numbers =
      Enum.map(writes, fn write ->
        Regex.run(~r/frame (\d+)/, write) |> List.last() |> String.to_integer()
      end)

    assert Enum.zip(numbers, tl(numbers)) |> Enum.any?(fn {a, b} -> b - a > 1 end),
           "frames were not merged: #{inspect(numbers)}"
  end

  defmodule SlowChannel do
    @moduledoc false

    def start(delay) do
      spawn_link(fn -> serve(delay, []) end)
    end

    def written(pid) do
      send(pid, {:written, self()})

      receive do
        {:written, list} -> list
      end
    end

    defp serve(delay, written) do
      receive do
        {:io_request, from, ref, {:put_chars, _encoding, chars}} ->
          Process.sleep(delay)
          send(from, {:io_reply, ref, :ok})
          serve(delay, [IO.chardata_to_string(chars) | written])

        {:io_request, from, ref, {:get_chars, _, _, _}} ->
          send(from, {:io_reply, ref, :eof})
          serve(delay, written)

        {:io_request, from, ref, {:get_geometry, :columns}} ->
          send(from, {:io_reply, ref, 80})
          serve(delay, written)

        {:io_request, from, ref, {:get_geometry, :rows}} ->
          send(from, {:io_reply, ref, 24})
          serve(delay, written)

        {:io_request, from, ref, _other} ->
          send(from, {:io_reply, ref, :ok})
          serve(delay, written)

        {:written, caller} ->
          send(caller, {:written, Enum.reverse(written)})
          serve(delay, written)
      end
    end
  end

  test "the ssh driver's write returns only once the channel took the bytes" do
    channel = SlowChannel.start(60)
    {:ok, driver} = SSHDriver.start_link(group_leader: channel)
    {:ok, manager} = Drafter.Event.Manager.start_link(name: nil)
    :ok = SSHDriver.setup(driver, manager)

    {elapsed, :ok} = :timer.tc(fn -> SSHDriver.write(driver, "frame") end)

    assert elapsed >= 60_000
    assert Enum.any?(SlowChannel.written(channel), &String.contains?(&1, "frame"))
  end

  test "the telnet driver's write returns once the socket took the bytes" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)

    {:ok, driver} = TelnetDriver.start_link(socket: server, session: self())
    :ok = :gen_tcp.controlling_process(server, driver)
    {:ok, manager} = Drafter.Event.Manager.start_link(name: nil)
    :ok = TelnetDriver.setup(driver, manager)

    assert :ok == TelnetDriver.write(driver, "frame")
    {:ok, received} = :gen_tcp.recv(client, 0, 1000)

    assert String.contains?(received, "frame") or
             String.contains?(drain(client, received), "frame")
  end

  defp drain(socket, acc) do
    case :gen_tcp.recv(socket, 0, 200) do
      {:ok, more} -> drain(socket, acc <> more)
      _ -> acc
    end
  end
end
