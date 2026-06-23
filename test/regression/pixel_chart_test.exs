defmodule Drafter.Regression.PixelChartTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.Widget.{Chart, Gauge, PieChart}
  alias Drafter.Widget.Chart.Pixel

  test "image/2 produces image bytes for an explicit pixel protocol" do
    state =
      Chart.mount(%{
        data: [1, 3, 2, 5, 4, 6, 3, 7, 5, 8],
        chart_type: :line,
        renderer: :iterm2,
        color: {120, 200, 255}
      })

    bytes = Chart.image(state, %{x: 0, y: 0, width: 24, height: 10})
    assert is_binary(bytes) or is_list(bytes)
    assert IO.iodata_length(bytes) > 0
  end

  test "image/2 returns nil for the default text renderer" do
    state = Chart.mount(%{data: [1, 2, 3], chart_type: :line})
    assert Chart.image(state, %{x: 0, y: 0, width: 10, height: 4}) == nil
  end

  test "renderer: :braille falls back to braille strips (no image)" do
    state = Chart.mount(%{data: [1, 5, 2, 8, 3, 9, 4], chart_type: :line, renderer: :braille})
    rect = %{x: 0, y: 0, width: 16, height: 6}

    strips = Chart.render(state, rect)
    assert length(strips) == 6
    text = Enum.map_join(strips, "", &Strip.to_plain_text/1)
    assert String.match?(text, ~r/[\x{2800}-\x{28FF}]/u)

    assert Chart.image(state, rect) == nil
  end

  test "every supported chart type rasterizes to image bytes and braille strips" do
    rect = %{x: 0, y: 0, width: 24, height: 10}

    cases = [
      {:line, [1, 3, 2, 5, 4, 6]},
      {:area, [1, 3, 2, 5, 4, 6]},
      {:braille_area, [1, 3, 2, 5, 4, 6]},
      {:bar, [3, 7, 2, 9, 5]},
      {:scatter, [[0, 1], [1, 4], [2, 2], [3, 6], [4, 3]]},
      {:candlestick, [[1, 4, 0.5, 3], [3, 5, 2, 2], [2, 6, 1, 5]]}
    ]

    for {type, data} <- cases do
      pixel = Chart.mount(%{data: data, chart_type: type, renderer: :iterm2})
      bytes = Chart.image(pixel, rect)
      assert (is_binary(bytes) or is_list(bytes)) and IO.iodata_length(bytes) > 0,
             "no image bytes for #{type}"

      braille = Chart.mount(%{data: data, chart_type: type, renderer: :braille})
      strips = Chart.render(braille, rect)
      assert length(strips) == 10, "wrong strip count for #{type}"
    end
  end

  test "every supported type rasterizes via the Pixel module (image + braille)" do
    base = %{
      color: {120, 200, 255, 255},
      colors: [{120, 200, 255}, {255, 150, 80}, {120, 230, 150}],
      smooth: false,
      fill_opacity: 0.5
    }

    specs = [
      Map.merge(base, %{type: :line, data: [1, 3, 2, 5, 4]}),
      Map.merge(base, %{type: :line, data: [[1, 3, 2, 5], [2, 1, 4, 3]]}),
      Map.merge(base, %{type: :step, data: [1, 3, 2, 5]}),
      Map.merge(base, %{type: :area, data: [1, 3, 2, 5]}),
      Map.merge(base, %{type: :braille_area, data: [[1, 3, 2], [2, 1, 4]]}),
      Map.merge(base, %{type: :stacked_area, data: [[1, 3, 2, 5], [2, 1, 4, 3], [1, 2, 1, 2]]}),
      Map.merge(base, %{type: :bar, data: [3, 7, 2, 9]}),
      Map.merge(base, %{type: :clustered_bar, data: [[3, 7, 2], [5, 4, 8]]}),
      Map.merge(base, %{type: :stacked_bar, data: [[3, 7, 2], [5, 4, 8]]}),
      Map.merge(base, %{type: :range_bar, data: [[1, 4], [2, 6], [0, 3]]}),
      Map.merge(base, %{type: :histogram, data: [1, 2, 2, 3, 3, 3, 4]}),
      Map.merge(base, %{type: :scatter, data: [[0, 1], [1, 4], [2, 2]]}),
      Map.merge(base, %{type: :scatter, data: [[[0, 1], [1, 2]], [[0, 3], [1, 1]]]}),
      Map.merge(base, %{type: :bubble, data: [[10, 20, 5], [30, 40, 12]]}),
      Map.merge(base, %{type: :candlestick, data: [[1, 4, 0.5, 3], [3, 5, 2, 2]]}),
      Map.merge(base, %{type: :heatmap, data: [[1, 2, 3], [4, 5, 6]]}),
      %{type: :pie, slices: [{30, {120, 200, 255, 255}}, {70, {255, 150, 80, 255}}]}
    ]

    for spec <- specs do
      img = Pixel.image(spec, :iterm2, {24, 10})
      assert img && IO.iodata_length(img) > 0, "no image bytes for #{spec.type}"

      strips = Pixel.braille_strips(spec, {24, 10})
      assert strips && length(strips) == 10, "no braille strips for #{spec.type}"
    end
  end

  test "pie chart rasterizes to a positioned (sub-rect) image, text by default" do
    state = PieChart.mount(%{data: [{"A", 30}, {"B", 50}, {"C", 20}], renderer: :iterm2})
    rect = %{x: 0, y: 0, width: 40, height: 12}

    assert {bytes, %{dx: 0, dy: 0, cols: cols, rows: 12}} = PieChart.image(state, rect)
    assert (is_binary(bytes) or is_list(bytes)) and IO.iodata_length(bytes) > 0
    assert cols <= 40

    assert PieChart.image(PieChart.mount(%{data: [{"A", 1}]}), rect) == nil
  end

  test "gauge renders a positioned pixel arc below its label, text by default" do
    state = Gauge.mount(%{value: 0.7, label: "CPU", renderer: :iterm2})
    rect = %{x: 0, y: 0, width: 20, height: 6}

    assert {bytes, %{dx: 0, dy: 1, cols: 20, rows: 4}} = Gauge.image(state, rect)
    assert IO.iodata_length(bytes) > 0

    assert Gauge.image(Gauge.mount(%{value: 0.5}), rect) == nil
  end
end
