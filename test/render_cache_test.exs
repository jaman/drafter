defmodule Drafter.RenderCacheTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.RenderCache

  describe "extract_layout_impact/1" do
    test "returns {false, nil} for empty actions" do
      assert {false, nil} = RenderCache.extract_layout_impact([])
    end

    test "returns {false, nil} for unrelated actions" do
      assert {false, nil} =
               RenderCache.extract_layout_impact([:some_action, {:app_callback, :foo, :bar}])
    end

    test "matches bare :widget_layout_needed atom with :all direction" do
      assert {true, :all} = RenderCache.extract_layout_impact([:widget_layout_needed])
    end

    test "matches {:widget_layout_needed, direction} tuple" do
      assert {true, :below} = RenderCache.extract_layout_impact([{:widget_layout_needed, :below}])
    end

    test "matches {:widget_layout_needed, :all} tuple" do
      assert {true, :all} = RenderCache.extract_layout_impact([{:widget_layout_needed, :all}])
    end

    test "extracts direction among other actions" do
      actions = [:some_action, {:widget_layout_needed, :right}, {:app_callback, :cb, :data}]
      assert {true, :right} = RenderCache.extract_layout_impact(actions)
    end
  end

  describe "compute_directional_dirty_rows/3" do
    setup do
      screen_rect = %{x: 0, y: 0, width: 80, height: 24}
      widget_bounds = %{x: 10, y: 5, width: 20, height: 3}
      %{screen_rect: screen_rect, widget_bounds: widget_bounds}
    end

    test ":self only marks widget's own rows", %{screen_rect: sr, widget_bounds: wb} do
      rows = RenderCache.compute_directional_dirty_rows(:self, wb, sr)
      assert MapSet.equal?(rows, MapSet.new([5, 6, 7]))
    end

    test ":below marks from widget to bottom of screen", %{screen_rect: sr, widget_bounds: wb} do
      rows = RenderCache.compute_directional_dirty_rows(:below, wb, sr)
      expected = MapSet.new(5..23)
      assert MapSet.equal?(rows, expected)
    end

    test ":above marks from top to widget bottom", %{screen_rect: sr, widget_bounds: wb} do
      rows = RenderCache.compute_directional_dirty_rows(:above, wb, sr)
      expected = MapSet.new(0..7)
      assert MapSet.equal?(rows, expected)
    end

    test ":all marks entire screen", %{screen_rect: sr, widget_bounds: wb} do
      rows = RenderCache.compute_directional_dirty_rows(:all, wb, sr)
      expected = MapSet.new(0..23)
      assert MapSet.equal?(rows, expected)
    end
  end

  describe "strips_fingerprint/1" do
    test "same strips produce same fingerprint" do
      strip = Strip.from_text("hello")
      assert RenderCache.strips_fingerprint([strip]) == RenderCache.strips_fingerprint([strip])
    end

    test "different strips produce different fingerprint" do
      strip_a = Strip.from_text("hello")
      strip_b = Strip.from_text("world")

      refute RenderCache.strips_fingerprint([strip_a]) ==
               RenderCache.strips_fingerprint([strip_b])
    end
  end
end
