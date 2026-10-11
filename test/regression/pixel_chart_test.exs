defmodule Drafter.Regression.PixelChartTest do
  # not async: these pin the terminal environment, which picks the kitty dialect
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip
  alias Drafter.Render.Picture
  alias Drafter.Widget.{Chart, Gauge, PieChart}
  alias Drafter.Widget.Chart.Pixel

  test "image_raster/2 encodes to paint/clear bytes for an explicit pixel protocol" do
    state =
      Chart.mount(%{
        data: [1, 3, 2, 5, 4, 6, 3, 7, 5, 8],
        chart_type: :line,
        renderer: :iterm2,
        color: {120, 200, 255}
      })

    assert {paint, clear, %{dx: 0, dy: 0, cols: 24, rows: 10}} =
             state
             |> Chart.image_raster(%{x: 0, y: 0, width: 24, height: 10})
             |> Picture.encode(:chart_a, nil)

    assert is_binary(paint) or is_list(paint)
    assert IO.iodata_length(paint) > 0
    assert clear == ""
  end

  test "image_raster/2 returns nil for the default text renderer" do
    state = Chart.mount(%{data: [1, 2, 3], chart_type: :line})
    assert Chart.image_raster(state, %{x: 0, y: 0, width: 10, height: 4}) == nil
  end

  test "renderer: :braille falls back to braille strips (no image)" do
    state = Chart.mount(%{data: [1, 5, 2, 8, 3, 9, 4], chart_type: :line, renderer: :braille})
    rect = %{x: 0, y: 0, width: 16, height: 6}

    strips = Chart.render(state, rect)
    assert length(strips) == 6
    text = Enum.map_join(strips, "", &Strip.to_plain_text/1)
    assert String.match?(text, ~r/[\x{2800}-\x{28FF}]/u)

    assert Chart.image_raster(state, rect) == nil
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

      assert {paint, "", %{cols: _, rows: _}} =
               pixel |> Chart.image_raster(rect) |> Picture.encode(type, nil)

      assert (is_binary(paint) or is_list(paint)) and IO.iodata_length(paint) > 0,
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
      assert {img, "", _region} =
               spec |> Pixel.picture(:iterm2, {24, 10}) |> Picture.encode(spec.type, nil)

      assert IO.iodata_length(img) > 0, "no image bytes for #{spec.type}"

      strips = Pixel.braille_strips(spec, {24, 10})
      assert strips && length(strips) == 10, "no braille strips for #{spec.type}"
    end
  end

  defp line_spec do
    %{
      type: :line,
      data: [1, 3, 2, 5, 4],
      color: {120, 200, 255, 255},
      smooth: false,
      fill_opacity: 0.5
    }
  end

  defp with_env(vars, fun) do
    kept = Map.new(vars, fn {name, _value} -> {name, System.get_env(name)} end)

    Enum.each(vars, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)

    try do
      fun.()
    after
      Enum.each(kept, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  @real_kitty %{
    "TERM" => "xterm-kitty",
    "TERM_PROGRAM" => nil,
    "TERM_PROGRAM_VERSION" => nil,
    "LC_TERMINAL" => nil,
    "LC_TERMINAL_VERSION" => nil
  }
  @iterm %{
    "TERM" => "xterm-256color",
    "KITTY_WINDOW_ID" => nil,
    "TERM_PROGRAM" => "iTerm.app",
    "TERM_PROGRAM_VERSION" => "3.5.0",
    "FRENCH_CURVE_ITERM2" => nil
  }

  test "on a terminal that keeps images, kitty stores the image by id and leaves placing to the compositor" do
    with_env(@real_kitty, fn ->
      picture = Pixel.picture(line_spec(), :kitty, {24, 10})
      assert {paint, clear, region} = Picture.encode(picture, :w_kitty, nil)
      paint = IO.iodata_to_binary(paint)
      clear = IO.iodata_to_binary(clear)

      assert paint =~ "a=t,i="
      refute paint =~ "a=p,i="
      assert clear =~ "a=d,d=i,i="
      assert %{image: image, width: width, height: height} = region.crop
      assert image == FrenchCurve.image_id(:w_kitty)
      assert {width, height} == FrenchCurve.Raster.dimensions(picture.raster)
      refute Picture.window_dependent?(picture)

      assert {other_paint, _, _} = Picture.encode(picture, :w_other, nil)
      refute IO.iodata_to_binary(other_paint) == paint
    end)
  end

  test "on iTerm forced to kitty, which keeps none, a frame is one transmit-and-display" do
    with_env(Map.put(@iterm, "FRENCH_CURVE_ITERM2", "kitty"), fn ->
      assert Pixel.protocol(:auto) == :kitty

      picture = Pixel.picture(line_spec(), Pixel.protocol(:auto), {24, 10})
      assert {paint, clear, region} = Picture.encode(picture, :w_iterm, nil)
      paint = IO.iodata_to_binary(paint)
      refute Map.has_key?(region, :crop)
      assert Picture.window_dependent?(picture)

      assert paint =~ "a=T,", "sent and shown together"
      refute paint =~ "a=t,i=", "storing it would leave iTerm holding a picture it never draws"
      refute paint =~ "a=p", "and a placement means nothing there"
      assert IO.iodata_to_binary(clear) =~ "a=d,d=i,i="
    end)
  end

  test "on iTerm it is an inline image with nothing to clear" do
    with_env(@iterm, fn ->
      assert Pixel.protocol(:auto) == :iterm2

      assert {paint, clear, _region} =
               line_spec()
               |> Pixel.picture(Pixel.protocol(:auto), {24, 10})
               |> Picture.encode(:w_iterm, nil)

      assert IO.iodata_to_binary(paint) =~ "\e]1337;File=inline=1"
      assert IO.iodata_to_binary(clear) == ""
    end)
  end

  test "pie chart rasterizes to a positioned (sub-rect) image, text by default" do
    state = PieChart.mount(%{data: [{"A", 30}, {"B", 50}, {"C", 20}], renderer: :iterm2})
    rect = %{x: 0, y: 0, width: 40, height: 12}

    assert {paint, "", %{dx: 0, dy: 0, cols: cols, rows: 12}} =
             state |> PieChart.image_raster(rect) |> Picture.encode(:pie_a, nil)

    assert (is_binary(paint) or is_list(paint)) and IO.iodata_length(paint) > 0
    assert cols <= 40

    assert PieChart.image_raster(PieChart.mount(%{data: [{"A", 1}]}), rect) == nil
  end

  test "gauge renders a positioned pixel arc below its label, text by default" do
    state = Gauge.mount(%{value: 0.7, label: "CPU", renderer: :iterm2})
    rect = %{x: 0, y: 0, width: 20, height: 6}

    assert {paint, "", %{dx: 0, dy: 1, cols: 20, rows: 4}} =
             state |> Gauge.image_raster(rect) |> Picture.encode(:gauge_a, nil)

    assert IO.iodata_length(paint) > 0

    assert Gauge.image_raster(Gauge.mount(%{value: 0.5}), rect) == nil
  end
end
