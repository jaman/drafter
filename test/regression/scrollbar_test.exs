defmodule Drafter.ScrollbarTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Scrollbar

  test "no scrollbar when content fits the viewport" do
    assert Scrollbar.thumb_rows(0, 10, 10) == nil
    assert Scrollbar.thumb_rows(0, 3, 10) == nil
  end

  test "thumb sits at the top when scrolled to the start" do
    assert Scrollbar.thumb_rows(0, 20, 10) == 0..4
  end

  test "thumb sits at the bottom when scrolled to the end" do
    assert Scrollbar.thumb_rows(10, 20, 10) == 5..9
  end

  test "thumb stays within the viewport for any offset" do
    for offset <- 0..10 do
      first..last//_ = Scrollbar.thumb_rows(offset, 20, 10)
      assert first >= 0
      assert last <= 9
      assert last >= first
    end
  end

  test "segment styles the thumb and track from the theme and uses distinct glyphs" do
    styles = Scrollbar.styles(%{primary: {1, 2, 3}, text_muted: {4, 5, 6}, surface: {7, 8, 9}})
    thumb = Scrollbar.thumb_rows(0, 20, 10)

    thumb_seg = Scrollbar.segment(0, thumb, styles)
    track_seg = Scrollbar.segment(9, thumb, styles)

    assert thumb_seg.style == %{fg: {1, 2, 3}, bg: {1, 2, 3}}
    assert track_seg.style == %{fg: {4, 5, 6}, bg: {7, 8, 9}}
    refute thumb_seg.text == track_seg.text
  end
end
