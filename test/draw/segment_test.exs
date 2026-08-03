defmodule Drafter.Draw.SegmentTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Segment

  describe "width" do
    test "ascii width equals byte size" do
      assert Segment.new("hello world").width == 11
    end

    test "wide characters count two columns" do
      assert Segment.new("あい").width == 4
      assert Segment.new("a あ b").width == 6
    end

    test "combining marks add no columns" do
      assert Segment.new("שָׁלוֹם").width == 4
    end

    test "embedded ansi is excluded from width" do
      assert Segment.new("\e[31mred\e[0m").width == 3
      assert Segment.new("\e[38;2;1;2;3mxy\e[0m").width == 2
    end

    test "empty segment has zero width" do
      assert Segment.new("").width == 0
    end
  end

  describe "crop" do
    test "cropping beyond width is a no-op" do
      seg = Segment.new("abc")
      assert Segment.crop(seg, 10) == seg
    end

    test "cropping to zero empties the segment" do
      assert Segment.crop(Segment.new("abc"), 0).text == ""
    end

    test "ascii crops to exact width" do
      seg = Segment.crop(Segment.new("abcdef"), 3)
      assert seg.text == "abc"
      assert seg.width == 3
    end

    test "wide characters are not split across the crop boundary" do
      seg = Segment.crop(Segment.new("あい"), 3)
      assert seg.text == "あ"
      assert seg.width == 2
    end

    test "cropping preserves style" do
      seg = Segment.crop(Segment.new("abcdef", %{bold: true}), 2)
      assert seg.style.bold
    end

    test "ansi codes survive cropping of the visible text" do
      seg = Segment.crop(Segment.new("\e[31mabcdef"), 3)
      assert seg.width == 3
      assert String.contains?(seg.text, "\e[31m")
    end
  end

  describe "pad" do
    test "pads to the target width" do
      seg = Segment.pad(Segment.new("ab"), 5)
      assert seg.width == 5
      assert seg.text == "ab   "
    end

    test "does not shrink" do
      seg = Segment.new("abcdef")
      assert Segment.pad(seg, 2) == seg
    end
  end

  describe "style normalisation" do
    test "hex colours normalise to rgb tuples" do
      seg = Segment.new("x", %{fg: "#ff0000"})
      assert seg.style.fg == {255, 0, 0}
    end
  end

  describe "to_ansi" do
    test "unstyled text emits no escape codes" do
      assert Segment.to_ansi(Segment.new("abc")) == "abc"
    end

    test "styled text is wrapped and reset" do
      out = Segment.to_ansi(Segment.new("abc", %{fg: {1, 2, 3}}))
      assert out == "\e[38;2;1;2;3mabc\e[0m"
    end
  end
end
