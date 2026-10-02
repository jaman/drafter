defmodule Drafter.Widget.Slider.ScaleTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Slider.Scale

  describe "clamp/3" do
    test "pulls a value below the range up to the minimum" do
      assert Scale.clamp(-3.0, 0.0, 1.0) == 0.0
    end
  end

  describe "fraction/3" do
    test "maps the midpoint of an offset range to a half" do
      assert Scale.fraction(50, 0, 100) == 0.5
      assert Scale.fraction(0, -10, 10) == 0.5
    end

    test "clamps values outside the range" do
      assert Scale.fraction(-5, 0, 10) == 0.0
      assert Scale.fraction(50, 0, 10) == 1.0
    end
  end

  describe "step_size/3" do
    test "defaults to whole numbers for an integer range" do
      assert Scale.step_size(0, 100, nil) == 1
      assert Scale.step_size(0, 3, nil) == 1
      assert Scale.step_size(0, 1000, nil) == 10
    end
  end

  describe "snap/4" do
    test "leaves a continuous value alone apart from clamping" do
      assert Scale.snap(0.37, 0.0, 1.0, nil) == 0.37
      assert Scale.snap(1.4, 0.0, 1.0, nil) == 1.0
    end

    test "rounds to the nearest step from the minimum" do
      assert Scale.snap(0.37, 0.0, 1.0, 0.25) == 0.25
      assert Scale.snap(0.4, 0.0, 1.0, 0.25) == 0.5
    end

    test "steps from the minimum rather than from zero" do
      assert Scale.snap(5.6, 1.0, 10.0, 2.0) == 5.0
    end

    test "does not accumulate float error" do
      assert Scale.snap(0.30000000000000004, 0.0, 1.0, 0.1) == 0.3
    end
  end

  describe "value_at/4" do
    test "clamps a fraction outside zero and one" do
      assert Scale.value_at(-1.0, 0.0, 1.0, nil) == 0.0
      assert Scale.value_at(2.0, 0.0, 1.0, nil) == 1.0
    end
  end

  describe "nudge/5" do
    test "moves by several steps at once" do
      assert Scale.nudge(0.5, 0.0, 1.0, 0.1, 10) == 1.0
    end

    test "uses the default step when none is given" do
      assert Scale.nudge(0.5, 0.0, 1.0, nil, 1) == 0.51
    end
  end

  describe "decimals/1" do
    test "counts the decimals a step needs" do
      assert Scale.decimals(1) == 0
      assert Scale.decimals(1.0) == 0
      assert Scale.decimals(0.5) == 1
      assert Scale.decimals(0.25) == 2
      assert Scale.decimals(0.01) == 2
      assert Scale.decimals(0.001) == 3
    end

    test "caps the count for a step with no short decimal form" do
      assert Scale.decimals(1 / 3) == 6
    end
  end

  describe "integral?/3" do
    test "is true only when every bound is an integer" do
      assert Scale.integral?(0, 10, 1)
      assert Scale.integral?(0, 10, nil)
      refute Scale.integral?(0.0, 10, 1)
      refute Scale.integral?(0, 10, 0.5)
    end
  end
end
