defmodule Drafter.Regression.CompositeFastpathTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor

  defp layer(id, strips, bounds, z), do: LayerCompositor.create_layer(id, strips, bounds, z)
  defp ansi(strips), do: Enum.map(strips, &Strip.to_ansi/1)

  test "a full-width opaque layer fully replaces the canvas and renders intact" do
    viewport = %{width: 10, height: 1}

    bg =
      layer(
        :bg,
        [Strip.new([Segment.new("XXXXXXXXXX", %{fg: {1, 1, 1}})])],
        %{x: 0, y: 0, width: 10, height: 1},
        0
      )

    fg_strip =
      Strip.new([
        Segment.new("ABCDE", %{fg: {255, 0, 0}}),
        Segment.new("FGHIJ", %{fg: {0, 255, 0}})
      ])

    fg = layer(:fg, [fg_strip], %{x: 0, y: 0, width: 10, height: 1}, 5)

    [row] = LayerCompositor.composite([bg, fg], viewport)
    assert Strip.to_plain_text(row) == "ABCDEFGHIJ"
    assert Strip.to_ansi(row) == Strip.to_ansi(fg_strip)
  end

  test "a wider-than-viewport layer is cropped to the viewport" do
    viewport = %{width: 5, height: 1}
    wide = Strip.new([Segment.new("ABCDEFGHIJ", %{fg: {10, 20, 30}})])
    lyr = layer(:w, [wide], %{x: 0, y: 0, width: 10, height: 1}, 0)

    [row] = LayerCompositor.composite([lyr], viewport)
    assert Strip.to_plain_text(row) == "ABCDE"
  end

  test "partial-width overlay still composites the underlying canvas through" do
    viewport = %{width: 10, height: 1}

    bg =
      layer(
        :bg,
        [Strip.new([Segment.new("..........", %{fg: {5, 5, 5}})])],
        %{x: 0, y: 0, width: 10, height: 1},
        0
      )

    fg =
      layer(
        :fg,
        [Strip.new([Segment.new("MID", %{fg: {255, 0, 0}})])],
        %{x: 3, y: 0, width: 3, height: 1},
        5
      )

    [row] = LayerCompositor.composite([bg, fg], viewport)
    assert Strip.to_plain_text(row) == "...MID...."
  end

  test "incremental composite agrees with full composite for a full-width dashboard" do
    viewport = %{width: 12, height: 6}

    layers =
      for i <- 0..5 do
        strip = Strip.new([Segment.new(String.duplicate("#{i}", 12), %{fg: {i * 10, 0, 0}})])
        layer(:"w#{i}", [strip], %{x: 0, y: i, width: 12, height: 1}, i)
      end

    full = LayerCompositor.composite(layers, viewport)
    inc = LayerCompositor.composite_incremental(layers, viewport, full, MapSet.new([1, 3, 4]))

    assert ansi(full) == ansi(inc)
  end

  test "incremental keeps previous rows verbatim outside the dirty set" do
    viewport = %{width: 8, height: 4}
    base = for r <- 0..3, do: Strip.new([Segment.new("row#{r}--", %{})])
    layers = [layer(:w, base, %{x: 0, y: 0, width: 8, height: 4}, 0)]

    prev = LayerCompositor.composite(layers, viewport)

    changed = for r <- 0..3, do: Strip.new([Segment.new("NEW#{r}--", %{})])
    changed_layers = [layer(:w, changed, %{x: 0, y: 0, width: 8, height: 4}, 0)]

    inc = LayerCompositor.composite_incremental(changed_layers, viewport, prev, MapSet.new([2]))

    assert Strip.to_plain_text(Enum.at(inc, 0)) == "row0--  "
    assert Strip.to_plain_text(Enum.at(inc, 2)) == "NEW2--  "
  end
end
