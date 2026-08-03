defmodule Drafter.LayerCompositorTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor

  describe "LayerCompositor.composite/2" do
    test "creates canvas with correct size" do
      viewport = %{width: 10, height: 3}
      result = LayerCompositor.composite([], viewport)

      assert length(result) == 3

      Enum.each(result, fn strip ->
        assert length(strip.segments) == 1
        segment = hd(strip.segments)
        assert String.length(segment.text) == 10
        assert segment.text == "          "
      end)
    end

    test "places single layer content at correct position" do
      viewport = %{width: 10, height: 3}

      layer_strips = [Strip.new([Segment.new("Hello", %{fg: {255, 0, 0}})])]
      layer = LayerCompositor.background_layer(layer_strips, %{x: 2, y: 1, width: 5, height: 1})

      result = LayerCompositor.composite([layer], viewport)

      assert hd(Enum.at(result, 0).segments).text == "          "

      row1_segments = Enum.at(result, 1).segments
      assert length(row1_segments) == 3

      [before_seg, content_seg, after_seg] = row1_segments
      assert before_seg.text == "  "
      assert content_seg.text == "Hello"
      assert after_seg.text == "   "

      assert hd(Enum.at(result, 2).segments).text == "          "
    end

    test "handles multiple layers with z-index ordering" do
      viewport = %{width: 10, height: 2}

      bg_strips = [Strip.new([Segment.new("AAAAAAAAAA", %{bg: {100, 100, 100}})])]

      bg_layer =
        LayerCompositor.create_layer(:bg, bg_strips, %{x: 0, y: 0, width: 10, height: 1}, 0)

      fg_strips = [Strip.new([Segment.new("FG", %{fg: {255, 0, 0}})])]

      fg_layer =
        LayerCompositor.create_layer(:fg, fg_strips, %{x: 3, y: 0, width: 2, height: 1}, 10)

      result = LayerCompositor.composite([bg_layer, fg_layer], viewport)

      row0_segments = Enum.at(result, 0).segments
      assert length(row0_segments) == 3

      [before_seg, fg_seg, after_seg] = row0_segments
      assert before_seg.text == "AAA"
      assert fg_seg.text == "FG"
      assert after_seg.text == "AAAAA"
    end
  end

  describe "LayerCompositor helper functions" do
    test "background_layer creates layer with correct z-index" do
      strips = [Strip.new([Segment.new("test", %{})])]
      bounds = %{x: 0, y: 0, width: 4, height: 1}

      layer = LayerCompositor.background_layer(strips, bounds)

      assert layer.id == :background
      assert layer.z_index == 0
      assert layer.strips == strips
      assert layer.bounds == bounds
    end

    test "widget_layer creates layer with correct z-index" do
      strips = [Strip.new([Segment.new("widget", %{})])]
      bounds = %{x: 0, y: 0, width: 6, height: 1}

      layer = LayerCompositor.widget_layer(:my_widget, strips, bounds)

      assert layer.id == :my_widget
      assert layer.z_index == 20
      assert layer.strips == strips
      assert layer.bounds == bounds
    end
  end
end
