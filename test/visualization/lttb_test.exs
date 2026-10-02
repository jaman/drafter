defmodule Drafter.Visualization.LTTBTest do
  use ExUnit.Case, async: true

  alias Drafter.Visualization.LTTB

  describe "downsample/2" do
    test "returns points unchanged when equal to target" do
      points = [{0, 1}, {1, 2}, {2, 3}]
      assert LTTB.downsample(points, 3) == points
    end

    test "preserves first and last points" do
      points = Enum.map(0..99, fn x -> {x, :math.sin(x / 10)} end)
      result = LTTB.downsample(points, 10)

      assert hd(result) == hd(points)
      assert List.last(result) == List.last(points)
    end

    test "reduces point count to target" do
      points = Enum.map(0..99, fn x -> {x, x * x} end)
      result = LTTB.downsample(points, 20)

      assert length(result) == 20
    end
  end

  describe "downsample_series/2" do
    test "works with integer values" do
      values = Enum.to_list(1..50)
      result = LTTB.downsample_series(values, 10)

      assert length(result) == 10
      assert hd(result) == 1
      assert List.last(result) == 50
    end
  end
end
