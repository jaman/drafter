defmodule Drafter.Draw.SegmentTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Segment

  describe "width" do
    test "embedded ansi is excluded from width" do
      assert Segment.new("\e[31mred\e[0m").width == 3
      assert Segment.new("\e[38;2;1;2;3mxy\e[0m").width == 2
    end
  end

  describe "crop" do
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
end
