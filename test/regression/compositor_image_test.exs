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
    Enum.reduce_while(1..100, false, fn _, _ ->
      out = Cap.dump(cap)

      if fun.(out) do
        {:halt, true}
      else
        Process.sleep(5)
        {:cont, false}
      end
    end)
  end

  defp settled(cap) do
    Process.sleep(80)
    Cap.dump(cap)
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

    refute String.contains?(settled(cap), "OFFSCREEN_IMG")
  end

  test "never paints an image whose box runs past the right edge", %{cap: cap} do
    Compositor.put_image(:wide, "WIDE_IMG", "", 0, 0, 10, 2)
    Compositor.place_image(:wide, 75, 1)

    refute String.contains?(settled(cap), "WIDE_IMG")
  end

  test "paints a higher-stamp frame and drops an equal-or-lower stamp for the same id", %{cap: cap} do
    Compositor.place_image(:anim, 2, 4)
    Compositor.put_image(:anim, "FRAME_FIVE", "DEL", 0, 0, 6, 2, 5)
    assert poll(cap, &String.contains?(&1, "FRAME_FIVE"))

    Cap.clear(cap)
    Compositor.put_image(:anim, "STALE_THREE", "DEL", 0, 0, 6, 2, 3)
    refute String.contains?(settled(cap), "STALE_THREE")

    Cap.clear(cap)
    Compositor.put_image(:anim, "SAME_FIVE", "DEL", 0, 0, 6, 2, 5)
    refute String.contains?(settled(cap), "SAME_FIVE")

    Cap.clear(cap)
    Compositor.put_image(:anim, "FRESH_SEVEN", "DEL", 0, 0, 6, 2, 7)
    assert poll(cap, &String.contains?(&1, "FRESH_SEVEN"))
  end

  test "clear_image resets the stamp so a lower-or-equal stamp paints again", %{cap: cap} do
    Compositor.place_image(:reapp, 2, 4)
    Compositor.put_image(:reapp, "FIRST_TEN", "DEL", 0, 0, 6, 2, 10)
    assert poll(cap, &String.contains?(&1, "FIRST_TEN"))

    Compositor.clear_image(:reapp)
    settled(cap)

    Cap.clear(cap)
    Compositor.place_image(:reapp, 2, 4)
    Compositor.put_image(:reapp, "REBORN_ONE", "DEL", 0, 0, 6, 2, 1)
    assert poll(cap, &String.contains?(&1, "REBORN_ONE"))
  end
end
