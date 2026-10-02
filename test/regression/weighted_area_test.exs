defmodule Drafter.WeightedAreaTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Chart.Pixel

  defp area_spec(data) do
    %{
      type: :braille_area,
      data: data,
      color: {80, 200, 100, 255},
      smooth: false,
      fill_opacity: 0.6,
      colors: [{80, 200, 100}, {100, 140, 255}]
    }
  end

  test "single series of {value, weight} tuples rasterises (weight ignored)" do
    data = [{1.0, 0.5}, {3.0, 0.4}, {2.0, 0.6}, {4.0, 0.2}]
    assert Pixel.braille_strips(area_spec(data), {20, 8}) != nil
  end

  test "multi series of {value, weight} tuples rasterises" do
    data = [
      [{1.0, 0.5}, {3.0, 0.4}, {2.0, 0.6}],
      [{2.0, 0.3}, {1.0, 0.7}, {4.0, 0.2}]
    ]

    assert Pixel.braille_strips(area_spec(data), {20, 8}) != nil
  end
end
