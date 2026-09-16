defmodule Drafter.Regression.CompositorImageTest do
  use ExUnit.Case, async: false

  alias Drafter.{Compositor, Event}
  alias Drafter.Draw.Strip

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
    {:ok, comp} = Compositor.start_link(name: nil, terminal_driver: {Cap, cap}, event_manager: em)
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
    Compositor.put_image(:chart, "PAINTBYTES", "DELETESEQ", %{dx: 0, dy: 0, cols: 6, rows: 2})
    Compositor.place_image(:chart, 3, 5)
    assert poll(cap, &String.contains?(&1, "PAINTBYTES"))

    Cap.clear(cap)
    Compositor.clear_image(:chart)
    assert poll(cap, &String.contains?(&1, "DELETESEQ"))
  end

  test "never paints an image whose box falls below the screen", %{cap: cap} do
    Compositor.put_image(:offchart, "OFFSCREEN_IMG", "", %{dx: 0, dy: 0, cols: 6, rows: 4})
    Compositor.place_image(:offchart, 0, 22)

    refute String.contains?(settled(cap), "OFFSCREEN_IMG")
  end

  test "never paints an image whose box runs past the right edge", %{cap: cap} do
    Compositor.put_image(:wide, "WIDE_IMG", "", %{dx: 0, dy: 0, cols: 10, rows: 2})
    Compositor.place_image(:wide, 75, 1)

    refute String.contains?(settled(cap), "WIDE_IMG")
  end

  test "paints a higher-stamp frame and drops an equal-or-lower stamp for the same id", %{
    cap: cap
  } do
    Compositor.place_image(:anim, 2, 4)
    Compositor.put_image(:anim, "FRAME_FIVE", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 5})
    assert poll(cap, &String.contains?(&1, "FRAME_FIVE"))

    Cap.clear(cap)
    Compositor.put_image(:anim, "STALE_THREE", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 3})
    refute String.contains?(settled(cap), "STALE_THREE")

    Cap.clear(cap)
    Compositor.put_image(:anim, "SAME_FIVE", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 5})
    refute String.contains?(settled(cap), "SAME_FIVE")

    Cap.clear(cap)
    Compositor.put_image(:anim, "FRESH_SEVEN", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 7})
    assert poll(cap, &String.contains?(&1, "FRESH_SEVEN"))
  end

  test "text on an image's row is written around the image, the cells it covers left alone, and the image is not sent again",
       %{cap: cap} do
    Compositor.put_image(:field, "FULL_IMAGE", "DEL", %{
      dx: 0,
      dy: 0,
      cols: 6,
      rows: 2,
      stamp: 1,
      place: "PLACE_ONLY"
    })

    Compositor.place_image(:field, 3, 4)
    assert poll(cap, &String.contains?(&1, "FULL_IMAGE"))

    Cap.clear(cap)
    Compositor.render_strips([Strip.from_text("abcdefghijklmnop")], 0, 4)
    assert poll(cap, &String.contains?(&1, "jklmnop"))
    out = settled(cap)
    assert String.contains?(out, "abc")
    refute String.contains?(out, "defghi"), "the cells under the image were written"
    assert String.contains?(out, "\e[5;10H"), "the text after the image resumes at its column"
    refute String.contains?(out, "PLACE_ONLY")
    refute String.contains?(out, "FULL_IMAGE")
  end

  test "an image not yet on screen does not hold text back, and is painted after it", %{cap: cap} do
    Compositor.render_strips([Strip.from_text("abcdefghijklmnop")], 0, 4)
    assert poll(cap, &String.contains?(&1, "abcdefghijklmnop"))

    Cap.clear(cap)

    Compositor.put_image(:sixel, "PIXEL_BYTES", "", %{
      dx: 0,
      dy: 0,
      cols: 6,
      rows: 2,
      stamp: 1,
      place: nil
    })

    Compositor.place_image(:sixel, 3, 4)
    assert poll(cap, &String.contains?(&1, "PIXEL_BYTES"))

    Cap.clear(cap)
    Compositor.render_strips([Strip.from_text("ABCDEFGHIJKLMNOP")], 0, 4)
    out = settled(cap)
    assert String.contains?(out, "ABC") and String.contains?(out, "JKLMNOP")
    refute String.contains?(out, "DEFGHI")
    refute String.contains?(out, "PIXEL_BYTES")
  end

  test "clear_image resets the stamp so a lower-or-equal stamp paints again", %{cap: cap} do
    Compositor.place_image(:reapp, 2, 4)
    Compositor.put_image(:reapp, "FIRST_TEN", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 10})
    assert poll(cap, &String.contains?(&1, "FIRST_TEN"))

    Compositor.clear_image(:reapp)
    settled(cap)

    Cap.clear(cap)
    Compositor.place_image(:reapp, 2, 4)
    Compositor.put_image(:reapp, "REBORN_ONE", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 1})
    assert poll(cap, &String.contains?(&1, "REBORN_ONE"))
  end

  defmodule SlowCap do
    def start, do: Agent.start_link(fn -> [] end)

    def write(pid, data) do
      binary = IO.iodata_to_binary(data)
      if String.contains?(binary, "IMG"), do: Process.sleep(60)
      Agent.update(pid, &[binary | &1])
    end

    def get_size(_pid), do: {80, 24}
    def dump(pid), do: pid |> Agent.get(& &1) |> Enum.reverse() |> Enum.join()
    def writes(pid), do: pid |> Agent.get(& &1) |> Enum.reverse()
  end

  test "an image frame is written after the text, outside the synchronized update, in its own write",
       %{cap: cap} do
    Compositor.put_image(:chart, "PAINTBYTES", "DELETESEQ", %{dx: 0, dy: 0, cols: 6, rows: 2})
    Compositor.place_image(:chart, 3, 5)
    assert poll(cap, &String.contains?(&1, "PAINTBYTES"))

    out = Cap.dump(cap)
    [before_image, _] = String.split(out, "PAINTBYTES", parts: 2)
    assert String.contains?(before_image, "\e[?2026l")

    assert length(String.split(before_image, "\e[?2026h")) ==
             length(String.split(before_image, "\e[?2026l"))
  end

  test "text keeps flowing while a slow terminal digests images, and only the newest image is written" do
    {:ok, em} = Event.Manager.start_link(name: nil)
    {:ok, slow} = SlowCap.start()

    {:ok, comp} =
      Compositor.start_link(name: nil, terminal_driver: {SlowCap, slow}, event_manager: em)

    Process.put(:drafter_compositor, comp)

    Compositor.put_image(:chart, "IMG1", "", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: 1})
    Compositor.place_image(:chart, 3, 5)
    Process.sleep(20)

    for n <- 2..6 do
      Compositor.put_image(:chart, "IMG#{n}", "", %{dx: 0, dy: 0, cols: 6, rows: 2, stamp: n})
      Compositor.render_strips([Strip.from_text("row#{n}")], 0, 20)
      Process.sleep(5)
    end

    Process.sleep(400)
    writes = SlowCap.writes(slow)
    text_writes = Enum.filter(writes, &String.contains?(&1, "row"))
    image_writes = Enum.filter(writes, &String.contains?(&1, "IMG"))

    assert Enum.any?(text_writes, &String.contains?(&1, "row6"))
    assert List.last(image_writes) =~ "IMG6"
    assert length(image_writes) < 6
    assert Enum.all?(image_writes, &(not String.contains?(&1, "row")))
  end
end
