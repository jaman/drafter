defmodule Drafter.Regression.CompositorImageTest do
  use ExUnit.Case, async: false

  alias Drafter.{Compositor, Event}

  defmodule Cap do
    def start, do: Agent.start_link(fn -> [] end)
    def write(pid, data), do: Agent.update(pid, &[IO.iodata_to_binary(data) | &1])
    def get_size(_pid), do: {80, 24}
    def dump(pid), do: pid |> Agent.get(& &1) |> Enum.reverse() |> Enum.join()
    def clear(pid), do: Agent.update(pid, fn _ -> [] end)
  end

  setup do
    {:ok, em} = Event.Manager.start_link(name: nil)
    {:ok, cap} = Cap.start()
    {:ok, comp} = Compositor.start_link(terminal_driver: {Cap, cap}, event_manager: em)
    Process.put(:drafter_compositor, comp)
    %{cap: cap, comp: comp}
  end

  defp poll(cap, fun) do
    Enum.reduce_while(1..50, false, fn _, _ ->
      out = Cap.dump(cap)
      if fun.(out), do: {:halt, true}, else: {:cont, false}
    end)
  end

  test "paints an image that fits on screen and clears it via the clear sequence", %{cap: cap} do
    Compositor.put_image(:chart, "PAINTBYTES", "DELETESEQ", 0, 0, 6, 2)
    Compositor.place_image(:chart, 3, 5)
    assert poll(cap, &String.contains?(&1, "PAINTBYTES"))

    Cap.clear(cap)
    Compositor.clear_image(:chart)
    assert poll(cap, &String.contains?(&1, "DELETESEQ"))
  end

  test "never paints an image whose box falls below the screen", %{cap: cap} do
    Compositor.put_image(:offchart, "OFFSCREEN_IMG", "", 0, 0, 6, 4)
    Compositor.place_image(:offchart, 0, 22)

    refute poll(cap, &String.contains?(&1, "OFFSCREEN_IMG"))
  end

  test "never paints an image whose box runs past the right edge", %{cap: cap} do
    Compositor.put_image(:wide, "WIDE_IMG", "", 0, 0, 10, 2)
    Compositor.place_image(:wide, 75, 1)

    refute poll(cap, &String.contains?(&1, "WIDE_IMG"))
  end
end
