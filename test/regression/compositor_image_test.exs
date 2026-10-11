defmodule Drafter.Regression.CompositorImageTest do
  use ExUnit.Case, async: false

  alias Drafter.{Compositor, Event}
  alias Drafter.Draw.Strip
  alias Drafter.TestSupport.ScreenModel

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

  test "does not send the image again when the same bytes are put", %{cap: cap} do
    region = %{dx: 0, dy: 0, cols: 6, rows: 2}
    Compositor.put_image(:still, "SAMEBYTES", "DEL", region)
    Compositor.place_image(:still, 3, 5)
    assert poll(cap, &String.contains?(&1, "SAMEBYTES"))

    Cap.clear(cap)
    Compositor.put_image(:still, "SAMEBYTES", "DEL", Map.put(region, :stamp, 1))
    Compositor.put_image(:still, "SAMEBYTES", "DEL", Map.put(region, :stamp, 2))

    refute String.contains?(settled(cap), "SAMEBYTES"),
           "the same picture was transmitted again"
  end

  test "sends the image again as soon as its bytes change", %{cap: cap} do
    region = %{dx: 0, dy: 0, cols: 6, rows: 2}
    Compositor.put_image(:moving, "FRAME_ONE", "DEL", region)
    Compositor.place_image(:moving, 3, 5)
    assert poll(cap, &String.contains?(&1, "FRAME_ONE"))

    Cap.clear(cap)
    Compositor.put_image(:moving, "FRAME_TWO", "DEL", Map.put(region, :stamp, 1))
    assert poll(cap, &String.contains?(&1, "FRAME_TWO"))
  end

  test "sends the image again when the same bytes move to a new size", %{cap: cap} do
    Compositor.put_image(:resized, "SAMEBYTES2", "DEL", %{dx: 0, dy: 0, cols: 6, rows: 2})
    Compositor.place_image(:resized, 3, 5)
    assert poll(cap, &String.contains?(&1, "SAMEBYTES2"))

    Cap.clear(cap)

    Compositor.put_image(:resized, "SAMEBYTES2", "DEL", %{
      dx: 0,
      dy: 0,
      cols: 8,
      rows: 3,
      stamp: 1
    })

    assert poll(cap, &String.contains?(&1, "SAMEBYTES2"))
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

  test "text changing under an image is written and the image placed again over it, not sent again in full",
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
    assert String.contains?(out, "abcdefghijklmnop"), "the cells under the image were not written"
    assert String.contains?(out, "PLACE_ONLY"), "the image was not placed again over the new text"
    refute String.contains?(out, "FULL_IMAGE")
  end

  test "text changing beside an image, not under it, leaves the image alone", %{cap: cap} do
    Compositor.put_image(:aside, "ASIDE_IMAGE", "DEL", %{
      dx: 0,
      dy: 0,
      cols: 6,
      rows: 2,
      stamp: 1,
      place: "ASIDE_PLACE"
    })

    Compositor.place_image(:aside, 3, 4)
    assert poll(cap, &String.contains?(&1, "ASIDE_IMAGE"))

    Cap.clear(cap)

    Compositor.render_strips(
      [Strip.from_text("   " <> String.duplicate(" ", 6) <> "jklmnop")],
      0,
      4
    )

    assert poll(cap, &String.contains?(&1, "jklmnop"))
    out = settled(cap)
    refute String.contains?(out, "ASIDE_PLACE")
    refute String.contains?(out, "ASIDE_IMAGE")
  end

  test "clearing one image on rows another image still covers redraws those rows and keeps the other image",
       %{cap: cap, comp: comp} do
    Compositor.put_image(:left, "LEFT_IMAGE", "LEFT_DEL", %{
      dx: 0,
      dy: 0,
      cols: 6,
      rows: 2,
      place: "LEFT_PLACE"
    })

    Compositor.place_image(:left, 2, 4)

    Compositor.put_image(:right, "RIGHT_IMAGE", "RIGHT_DEL", %{
      dx: 0,
      dy: 0,
      cols: 6,
      rows: 2,
      place: "RIGHT_PLACE"
    })

    Compositor.place_image(:right, 20, 4)

    assert poll(
             cap,
             &(String.contains?(&1, "LEFT_IMAGE") and String.contains?(&1, "RIGHT_IMAGE"))
           )

    Cap.clear(cap)
    Compositor.clear_image(:left)
    assert poll(cap, &String.contains?(&1, "LEFT_DEL"))
    settled(cap)

    assert Process.alive?(comp)
    refute String.contains?(Cap.dump(cap), "RIGHT_IMAGE")
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
    image_writes = Enum.filter(writes, &String.contains?(&1, "IMG"))

    assert writes |> ScreenModel.apply() |> ScreenModel.row(20) == "row6"
    assert List.last(image_writes) =~ "IMG6"
    assert length(image_writes) < 6
    assert Enum.all?(image_writes, &(not String.contains?(&1, "row")))
  end

  describe "a stored kitty image" do
    @stored %{dx: 0, dy: 0, cols: 10, rows: 4, crop: %{image: 7, width: 40, height: 32}}

    test "is placed after it is stored, and moves with a placement alone", %{cap: cap} do
      Compositor.put_image(:stored, "STORED_PIXELS", "DEL", @stored)
      Compositor.place_image(:stored, 2, 3)
      assert poll(cap, &(&1 =~ "STORED_PIXELS" and &1 =~ "\e[4;3H\e_Ga=p,i=7"))

      Cap.clear(cap)
      Compositor.place_image(:stored, 2, 6)
      assert poll(cap, &String.contains?(&1, "\e[7;3H\e_Ga=p,i=7"))
      refute settled(cap) =~ "STORED_PIXELS"
    end

    test "with a spare id, a new frame goes under the id not on screen before the old is deleted",
         %{cap: cap} do
      frame = fn n ->
        encoded = %{control: "f=32,s=1,v=1", chunks: ["FRAME#{n}"]}
        crop = %{image: 7, spare: 8, width: 40, height: 32, encoded: encoded}
        Map.merge(@stored, %{crop: crop, stamp: n})
      end

      Compositor.put_image(:swapped, "ONE", "DEL", frame.(1))
      Compositor.place_image(:swapped, 0, 0)
      assert poll(cap, &(&1 =~ "\e_Ga=p,i=7"))
      first = settled(cap)
      assert first =~ "a=t,i=7,f=32,s=1,v=1,q=2,m=0;FRAME1"
      refute first =~ "a=d"

      Cap.clear(cap)
      Compositor.put_image(:swapped, "TWO", "DEL", frame.(2))
      assert poll(cap, &(&1 =~ "a=d,d=i,i=7"))
      second = settled(cap)
      assert second =~ ~r/\e\[\?2026h.*a=t,i=8,[^;]*;FRAME2.*a=p,i=8.*a=d,d=i,i=7.*\e\[\?2026l/s

      Cap.clear(cap)
      Compositor.put_image(:swapped, "THREE", "DEL", frame.(3))
      assert poll(cap, &(&1 =~ "a=d,d=i,i=8"))
      assert settled(cap) =~ ~r/a=t,i=7,[^;]*;FRAME3.*a=p,i=7.*a=d,d=i,i=8/s
    end

    test "partly inside its window shows only the visible rows", %{cap: cap} do
      Compositor.put_image(:part, "STORED_PIXELS", "DEL", @stored)
      Compositor.place_image(:part, 0, 2, %{x: 0, y: 4, width: 80, height: 10})

      assert poll(cap, &String.contains?(&1, "\e[5;1H\e_Ga=p,i=7"))
      out = settled(cap)
      assert out =~ "c=10,r=2,x=0,y=16,w=40,h=16"
    end

    test "is taken off when it leaves its window entirely", %{cap: cap} do
      Compositor.put_image(:gone, "STORED_PIXELS", "STORED_DEL", @stored)
      Compositor.place_image(:gone, 0, 2)
      assert poll(cap, &String.contains?(&1, "STORED_PIXELS"))

      Cap.clear(cap)
      Compositor.place_image(:gone, 0, 2, %{x: 0, y: 10, width: 80, height: 10})
      assert poll(cap, &String.contains?(&1, "STORED_DEL"))
    end
  end

  test "an image without a stored copy is taken off when only part of it is inside its window",
       %{cap: cap} do
    region = %{dx: 0, dy: 0, cols: 6, rows: 4}
    Compositor.put_image(:whole_only, "WHOLE_PIXELS", "WHOLE_DEL", region)
    Compositor.place_image(:whole_only, 0, 2, %{x: 0, y: 0, width: 80, height: 20})
    assert poll(cap, &String.contains?(&1, "WHOLE_PIXELS"))

    Cap.clear(cap)
    Compositor.place_image(:whole_only, 0, 2, %{x: 0, y: 4, width: 80, height: 20})
    assert poll(cap, &String.contains?(&1, "WHOLE_DEL"))
    refute settled(cap) =~ "WHOLE_PIXELS"
  end
end
