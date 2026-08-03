defmodule Drafter.CompositorRepaintTest do
  use ExUnit.Case, async: false

  alias Drafter.Compositor
  alias Drafter.Draw.Strip

  defmodule CountingDriver do
    @moduledoc false
    use Agent

    def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)

    def write(data), do: Agent.update(__MODULE__, &[IO.iodata_to_binary(data) | &1])

    def get_size, do: {80, 24}

    def writes, do: Agent.get(__MODULE__, &Enum.reverse/1)

    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)
  end

  setup do
    start_supervised!(CountingDriver)
    unique = System.unique_integer([:positive])
    manager = :"events_#{unique}"
    name = :"compositor_#{unique}"

    start_supervised!({Drafter.Event.Manager, name: manager}, id: manager)

    pid =
      start_supervised!(
        {Compositor, name: name, terminal_driver: CountingDriver, event_manager: manager},
        id: name
      )

    Process.put(:drafter_compositor, pid)
    CountingDriver.reset()

    {:ok, compositor: pid}
  end

  defp paint(pid, text) do
    GenServer.cast(pid, {:render_strips, [Strip.from_text(text)], 0, 0})
  end

  defp settle(pid) do
    :sys.get_state(pid)
    Process.sleep(5)
    :sys.get_state(pid)
  end

  defp painted?(text), do: Enum.any?(CountingDriver.writes(), &String.contains?(&1, text))

  describe "sustained repaint" do
    test "a single paint reaches the terminal" do
      pid = Process.get(:drafter_compositor)

      paint(pid, "hello")
      settle(pid)

      assert painted?("hello")
    end

    test "the final frame of a burst always reaches the terminal" do
      pid = Process.get(:drafter_compositor)

      for n <- 1..500, do: paint(pid, "frame #{n}")
      settle(pid)

      assert painted?("frame 500"),
             "the tail of a burst was coalesced away; #{length(CountingDriver.writes())} writes"
    end

    test "repeated bursts each land their final frame" do
      pid = Process.get(:drafter_compositor)

      for round <- 1..10 do
        for n <- 1..100, do: paint(pid, "r#{round} n#{n}")
        settle(pid)

        assert painted?("r#{round} n100"), "round #{round} never reached the terminal"
      end
    end

    test "sustained paints keep producing writes rather than flatlining" do
      pid = Process.get(:drafter_compositor)

      for n <- 1..2000 do
        paint(pid, "tick #{n}")
        if rem(n, 100) == 0, do: settle(pid)
      end

      settle(pid)

      assert length(CountingDriver.writes()) >= 10,
             "only #{length(CountingDriver.writes())} writes for 2000 paints"
    end

    test "painting identical content twice writes once" do
      pid = Process.get(:drafter_compositor)

      paint(pid, "steady")
      settle(pid)
      CountingDriver.reset()

      paint(pid, "steady")
      settle(pid)

      assert CountingDriver.writes() == []
    end
  end
end
