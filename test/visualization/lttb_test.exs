defmodule Drafter.Visualization.LTTBTest do
  use ExUnit.Case, async: true

  alias Drafter.Visualization.LTTB

  describe "downsample/2" do
    test "returns points unchanged when fewer than target" do
      points = [{0, 1}, {1, 2}, {2, 3}]
      assert LTTB.downsample(points, 5) == points
    end

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

    test "works with [x, y] list format" do
      points = Enum.map(0..49, fn x -> [x, :math.sin(x / 5)] end)
      result = LTTB.downsample(points, 10)

      assert length(result) == 10
      assert hd(result) == hd(points)
      assert List.last(result) == List.last(points)
    end

    test "handles flat data" do
      points = Enum.map(0..49, fn x -> {x, 5.0} end)
      result = LTTB.downsample(points, 10)

      assert length(result) == 10
    end

    test "handles ascending data" do
      points = Enum.map(0..99, fn x -> {x, x * 1.0} end)
      result = LTTB.downsample(points, 15)

      assert length(result) == 15
    end

    test "handles sine wave data" do
      points = Enum.map(0..199, fn x -> {x, :math.sin(x / 20)} end)
      result = LTTB.downsample(points, 25)

      assert length(result) == 25
      assert hd(result) == hd(points)
      assert List.last(result) == List.last(points)
    end

    test "returns empty list for empty input" do
      assert LTTB.downsample([], 10) == []
    end

    test "returns single point for single-element input" do
      assert LTTB.downsample([{0, 1}], 10) == [{0, 1}]
    end
  end

  describe "downsample_series/2" do
    test "returns values unchanged when fewer than target" do
      values = [1, 2, 3]
      assert LTTB.downsample_series(values, 5) == values
    end

    test "reduces value count to target" do
      values = Enum.to_list(1..100)
      result = LTTB.downsample_series(values, 20)

      assert length(result) == 20
    end

    test "preserves first and last values" do
      values = Enum.map(0..99, fn x -> :math.sin(x / 10) end)
      result = LTTB.downsample_series(values, 10)

      assert hd(result) == hd(values)
      assert List.last(result) == List.last(values)
    end

    test "returns empty list for empty input" do
      assert LTTB.downsample_series([], 10) == []
    end

    test "works with integer values" do
      values = Enum.to_list(1..50)
      result = LTTB.downsample_series(values, 10)

      assert length(result) == 10
      assert hd(result) == 1
      assert List.last(result) == 50
    end
  end
end
