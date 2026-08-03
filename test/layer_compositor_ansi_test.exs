defmodule Drafter.LayerCompositorANSITest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor

  defp composite_over_blank(text) do
    viewport = %{width: 8, height: 1}

    layers = [
      %{
        id: :bg,
        z_index: 0,
        strips: [Strip.new([Segment.new("        ", %{bg: {0, 0, 0}})])],
        bounds: %{x: 0, y: 0, width: 8, height: 1}
      },
      %{
        id: :fg,
        z_index: 10,
        strips: [Strip.new([Segment.new(text, %{})])],
        bounds: %{x: 2, y: 0, width: 4, height: 1}
      }
    ]

    [row] = LayerCompositor.composite(layers, viewport)
    row
  end

  defp styles_of(strip), do: Enum.map(strip.segments, & &1.style)

  test "truecolor foreground is recovered" do
    styles = styles_of(composite_over_blank("\e[38;2;10;20;30mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {10, 20, 30}))
  end

  test "truecolor background is recovered" do
    styles = styles_of(composite_over_blank("\e[48;2;40;50;60mab\e[0m"))
    assert Enum.any?(styles, &(&1[:bg] == {40, 50, 60}))
  end

  test "standard foreground colours are recovered" do
    styles = styles_of(composite_over_blank("\e[31mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {205, 49, 49}))
  end

  test "standard background colours are recovered" do
    styles = styles_of(composite_over_blank("\e[44mab\e[0m"))
    assert Enum.any?(styles, &(&1[:bg] == {36, 114, 200}))
  end

  test "bright foreground colours are recovered" do
    styles = styles_of(composite_over_blank("\e[91mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {241, 76, 76}))
  end

  test "bright background colours are recovered" do
    styles = styles_of(composite_over_blank("\e[101mab\e[0m"))
    assert Enum.any?(styles, &(&1[:bg] == {241, 76, 76}))
  end

  test "256-colour cube entries are recovered" do
    styles = styles_of(composite_over_blank("\e[38;5;196mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {255, 0, 0}))
  end

  test "256-colour greyscale ramp entries are recovered" do
    styles = styles_of(composite_over_blank("\e[38;5;244mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {128, 128, 128}))
  end

  test "256-colour indexes below 16 map to the base palette" do
    styles = styles_of(composite_over_blank("\e[38;5;1mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {205, 49, 49}))
  end

  test "combined attribute and colour codes both apply" do
    styles = styles_of(composite_over_blank("\e[1;31mab\e[0m"))
    assert Enum.any?(styles, &(&1[:fg] == {205, 49, 49} and &1[:bold] == true))
  end

  test "default-colour codes clear the colour without clearing attributes" do
    styles = styles_of(composite_over_blank("\e[1;31m\e[39mab\e[0m"))
    assert Enum.any?(styles, &(&1[:bold] == true and is_nil(&1[:fg])))
  end

  test "an unknown code is ignored rather than crashing" do
    styles = styles_of(composite_over_blank("\e[73mab\e[0m"))
    assert is_list(styles)
  end
end
