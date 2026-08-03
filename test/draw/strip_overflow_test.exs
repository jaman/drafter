defmodule Drafter.Draw.StripOverflowTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}

  defp strip(text, style \\ %{}), do: Strip.new([Segment.new(text, style)])
  defp text(s), do: Strip.to_plain_text(s)

  test "a strip that fits is untouched in either mode" do
    s = strip("abc")
    assert Strip.overflow(s, 10, :clip) == s
    assert Strip.overflow(s, 10, :ellipsis) == s
    assert Strip.overflow(s, 3, :ellipsis) == s
  end

  test "clip cuts at the boundary" do
    assert text(Strip.overflow(strip("abcdefgh"), 4, :clip)) == "abcd"
  end

  test "ellipsis marks the truncation and respects the width" do
    result = Strip.overflow(strip("abcdefgh"), 4, :ellipsis)
    assert text(result) == "abc…"
    assert result.width == 4
  end

  test "the default mode is clip" do
    assert text(Strip.overflow(strip("abcdefgh"), 4)) == "abcd"
  end

  test "a width of one leaves only the marker" do
    assert text(Strip.overflow(strip("abcdefgh"), 1, :ellipsis)) == "…"
  end

  test "zero width empties the strip" do
    assert text(Strip.overflow(strip("abcdefgh"), 0, :ellipsis)) == ""
  end

  test "the marker inherits the style of the text it replaces" do
    result = Strip.overflow(strip("abcdefgh", %{fg: {1, 2, 3}}), 4, :ellipsis)
    assert List.last(result.segments).style.fg == {1, 2, 3}
  end

  test "wide characters are not split by the marker" do
    result = Strip.overflow(strip("ああああ"), 5, :ellipsis)
    assert result.width <= 5
    assert String.ends_with?(text(result), "…")
  end

  test "multi-segment strips truncate across the boundary" do
    s = Strip.new([Segment.new("abc", %{bold: true}), Segment.new("defgh", %{})])
    result = Strip.overflow(s, 5, :ellipsis)
    assert text(result) == "abcd…"
    assert result.width == 5
  end

  test "an empty strip stays empty" do
    assert text(Strip.overflow(Strip.empty(), 5, :ellipsis)) == ""
  end
end
