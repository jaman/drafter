defmodule Drafter.OpacityTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor

  @black {0, 0, 0}
  @white {255, 255, 255}

  defp over(opacity) do
    viewport = %{width: 4, height: 1}

    style =
      if opacity, do: %{fg: @white, bg: @white, opacity: opacity}, else: %{fg: @white, bg: @white}

    layers = [
      %{
        id: :bg,
        z_index: 0,
        strips: [Strip.new([Segment.new("....", %{fg: @black, bg: @black})])],
        bounds: %{x: 0, y: 0, width: 4, height: 1}
      },
      %{
        id: :fg,
        z_index: 10,
        strips: [Strip.new([Segment.new("ab", style)])],
        bounds: %{x: 1, y: 0, width: 2, height: 1}
      }
    ]

    [row] = LayerCompositor.composite(layers, viewport)
    row.segments |> Enum.flat_map(&List.duplicate(&1.style, &1.width)) |> Enum.at(1)
  end

  describe "blend_over" do
    test "a style without opacity is untouched" do
      style = %{fg: @white}
      assert LayerCompositor.blend_over(style, %{bg: @black}) == style
    end

    test "full opacity is opaque and drops the marker" do
      assert LayerCompositor.blend_over(%{fg: @white, opacity: 1.0}, %{bg: @black}) == %{
               fg: @white
             }
    end

    test "zero opacity yields what is underneath" do
      blended = LayerCompositor.blend_over(%{fg: @white, opacity: 0.0}, %{fg: @black, bg: @black})
      assert blended.fg == @black
    end

    test "half opacity lands midway" do
      blended = LayerCompositor.blend_over(%{fg: @white, opacity: 0.5}, %{fg: @black, bg: @black})
      assert blended.fg == {128, 128, 128}
    end

    test "foreground and background blend independently" do
      blended =
        LayerCompositor.blend_over(
          %{fg: @white, bg: {200, 0, 0}, opacity: 0.5},
          %{fg: @black, bg: {0, 0, 100}}
        )

      assert blended.fg == {128, 128, 128}
      assert blended.bg == {100, 0, 50}
    end

    test "out-of-range opacity is clamped" do
      assert LayerCompositor.blend_over(%{fg: @white, opacity: 5.0}, %{bg: @black}).fg == @white

      assert LayerCompositor.blend_over(%{fg: @white, opacity: -1.0}, %{fg: @black, bg: @black}).fg ==
               @black
    end

    test "the opacity marker never survives into output" do
      blended = LayerCompositor.blend_over(%{fg: @white, opacity: 0.3}, %{bg: @black})
      refute Map.has_key?(blended, :opacity)
    end
  end

  describe "layer opacity" do
    defp composite_with(layer_opacity) do
      viewport = %{width: 4, height: 1}

      layers = [
        %{
          id: :bg,
          z_index: 0,
          opacity: 1.0,
          strips: [Strip.new([Segment.new("....", %{fg: @black, bg: @black})])],
          bounds: %{x: 0, y: 0, width: 4, height: 1}
        },
        %{
          id: :fg,
          z_index: 10,
          opacity: layer_opacity,
          strips: [Strip.new([Segment.new("ab", %{fg: @white, bg: @white})])],
          bounds: %{x: 1, y: 0, width: 2, height: 1}
        }
      ]

      [row] = LayerCompositor.composite(layers, viewport)
      row.segments |> Enum.flat_map(&List.duplicate(&1.style, &1.width)) |> Enum.at(1)
    end

    test "an opaque layer paints its own colour" do
      assert composite_with(1.0).fg == @white
    end

    test "a half-translucent layer blends with what is beneath" do
      assert composite_with(0.5).fg == {128, 128, 128}
    end

    test "a fully transparent layer disappears" do
      assert composite_with(0.0).fg == @black
    end

    test "a layer without an opacity field is treated as opaque" do
      viewport = %{width: 4, height: 1}

      layers = [
        %{
          id: :bg,
          z_index: 0,
          strips: [Strip.new([Segment.new("....", %{fg: @black, bg: @black})])],
          bounds: %{x: 0, y: 0, width: 4, height: 1}
        },
        %{
          id: :fg,
          z_index: 10,
          strips: [Strip.new([Segment.new("ab", %{fg: @white, bg: @white})])],
          bounds: %{x: 1, y: 0, width: 2, height: 1}
        }
      ]

      [row] = LayerCompositor.composite(layers, viewport)
      style = row.segments |> Enum.flat_map(&List.duplicate(&1.style, &1.width)) |> Enum.at(1)
      assert style.fg == @white
    end

    test "a segment's own opacity still wins over the layer's" do
      viewport = %{width: 4, height: 1}

      layers = [
        %{
          id: :bg,
          z_index: 0,
          opacity: 1.0,
          strips: [Strip.new([Segment.new("....", %{fg: @black, bg: @black})])],
          bounds: %{x: 0, y: 0, width: 4, height: 1}
        },
        %{
          id: :fg,
          z_index: 10,
          opacity: 0.5,
          strips: [Strip.new([Segment.new("ab", %{fg: @white, bg: @white, opacity: 0.0})])],
          bounds: %{x: 1, y: 0, width: 2, height: 1}
        }
      ]

      [row] = LayerCompositor.composite(layers, viewport)
      style = row.segments |> Enum.flat_map(&List.duplicate(&1.style, &1.width)) |> Enum.at(1)
      assert style.fg == @black
    end
  end

  describe "through the compositor" do
    test "an opaque layer paints its own colour" do
      assert over(nil).fg == @white
    end

    test "a translucent layer blends with the layer beneath" do
      assert over(0.5).fg == {128, 128, 128}
    end

    test "a fully transparent layer disappears into the background" do
      assert over(0.0).fg == @black
    end
  end
end
