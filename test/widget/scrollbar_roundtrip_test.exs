defmodule Drafter.Widget.ScrollbarRoundtripTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Scrollbar

  describe "offset_from_row is the inverse of thumb_rows" do
    defp track_rows(total, viewport) do
      thumb_size = max(1, min(viewport, round(viewport * viewport / total)))
      0..(viewport - thumb_size)
    end

    defp assert_row_stable(total, viewport) do
      for row <- track_rows(total, viewport) do
        offset = Scrollbar.offset_from_row(row, total, viewport)
        drawn = Scrollbar.thumb_rows(offset, total, viewport)

        assert drawn.first == row,
               "grabbed row #{row} (total #{total}, viewport #{viewport}) " <>
                 "scrolled to #{offset}, which redraws the thumb at #{drawn.first}"
      end
    end

    test "the thumb stays under the pointer when content barely overflows" do
      assert_row_stable(25, 20)
    end

    test "the thumb stays under the pointer for a very long list" do
      assert_row_stable(10_000, 10)
    end

    test "the thumb stays under the pointer across many geometries" do
      for total <- [30, 47, 128, 999], viewport <- [5, 12, 21] do
        assert_row_stable(total, viewport)
      end
    end
  end

  describe "bounds" do
    test "rows beyond the track clamp rather than overscroll" do
      assert Scrollbar.offset_from_row(999, 200, 20) == 180
      assert Scrollbar.offset_from_row(-5, 200, 20) == 0
    end

    test "a zero-height viewport is handled" do
      assert Scrollbar.offset_from_row(0, 100, 0) == 0
    end
  end

  describe "grab offset" do
    test "grabbing mid-thumb reports the distance from its top" do
      thumb = Scrollbar.thumb_rows(10, 40, 20)
      assert Range.size(thumb) > 3
      assert Scrollbar.grab_offset(thumb.first + 3, 10, 40, 20) == 3
    end

    test "dragging holds the grabbed point under the pointer" do
      total = 40
      viewport = 20
      start_offset = 10
      thumb = Scrollbar.thumb_rows(start_offset, total, viewport)
      grab = Scrollbar.grab_offset(thumb.first + 4, start_offset, total, viewport)

      for pointer <- (thumb.first + 4)..(viewport - 1) do
        offset = Scrollbar.offset_from_drag(pointer, grab, total, viewport)
        redrawn = Scrollbar.thumb_rows(offset, total, viewport)

        assert redrawn.first <= pointer and pointer <= redrawn.last,
               "pointer #{pointer} with grab #{grab} scrolled to #{offset}, " <>
                 "thumb redrew at #{inspect(redrawn)}"
      end
    end

    test "a press that does not move the pointer does not move the content" do
      total = 40
      viewport = 20
      start_offset = 10
      thumb = Scrollbar.thumb_rows(start_offset, total, viewport)
      pointer = thumb.first + 4
      grab = Scrollbar.grab_offset(pointer, start_offset, total, viewport)

      settled = Scrollbar.offset_from_drag(pointer, grab, total, viewport)
      assert settled == start_offset
    end
  end
end
