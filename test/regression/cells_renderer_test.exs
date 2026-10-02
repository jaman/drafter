defmodule Drafter.Regression.CellsRendererTest do
  @moduledoc """
  A chart or slider given a block-character set as its renderer draws that set's glyphs.
  """

  use ExUnit.Case, async: false

  alias Drafter.Widget.{Chart, Slider}
  alias Drafter.Widget.Chart.Pixel

  @rect %{x: 0, y: 0, width: 24, height: 6}
  @data Enum.map(0..47, fn i -> :math.sin(i * 0.3) * 40 + 50 end)

  setup do
    case Drafter.ThemeManager.start_link() do
      {:ok, pid} -> Process.put(:drafter_theme_manager, pid)
      {:error, {:already_started, pid}} -> Process.put(:drafter_theme_manager, pid)
    end

    :ok
  end

  test "the glyph sets resolve to cell modes and parse from DRAFTER_MODE" do
    for set <- Pixel.cell_sets() do
      assert Pixel.mode(set, :line) == {:cells, set}
      assert Slider.Pixel.mode(set) == {:cells, set}
    end

    assert Pixel.mode(:braille, :line) == :braille
  end

  test "a sextant chart is made of sextant cells" do
    strips =
      Chart.render(Chart.mount(%{data: @data, chart_type: :line, renderer: :sextant}), @rect)

    assert length(strips) == @rect.height
    assert Enum.any?(glyphs(strips), &sextant?/1)
    refute Enum.any?(glyphs(strips), &braille?/1)
  end

  test "an octant slider is made of octant cells" do
    strips = Slider.render(Slider.mount(%{value: 0.6, renderer: :octant}), @rect)
    assert Enum.any?(glyphs(strips), &octant?/1)
  end

  defp glyphs(strips) do
    for strip <- strips,
        segment <- strip.segments,
        <<code::utf8>> <- String.graphemes(segment.text),
        do: code
  end

  defp sextant?(code), do: code in 0x1FB00..0x1FB3B or code in [0x258C, 0x2590, 0x2588]
  defp octant?(code), do: code in 0x1CD00..0x1CDE5
  defp braille?(code), do: code in 0x2800..0x28FF
end
