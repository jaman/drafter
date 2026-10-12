defmodule Drafter.Widget.Chart.MultiSeries do
  @moduledoc false

  import Bitwise

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.{Line, Pixels, Step}

  @multi_series_default_colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100}
  ]

  def render(data_series, width, height, opts \\ []) do
    bg = Keyword.get(opts, :bg, {20, 20, 30})
    colors = Keyword.get(opts, :colors, @multi_series_default_colors)
    smooth = Keyword.get(opts, :smooth, false)
    thickness = Keyword.get(opts, :line_thickness, 1)
    connect = Keyword.get(opts, :connect_lines, false)
    raw_data = Keyword.get(opts, :raw_data, false)
    step = Keyword.get(opts, :step, false)
    {min_val, max_val} = resolve_multi_series_range(opts, data_series)
    range = max_val - min_val
    pixel_height = height * 4
    pixel_width = width * 2
    colors_tuple = List.to_tuple(colors)
    color_count = tuple_size(colors_tuple)

    all_pixels =
      data_series
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, series_idx} ->
        color = elem(colors_tuple, rem(series_idx, color_count))

        cond do
          raw_data ->
            series_to_raw_pixels(
              series,
              color,
              min_val,
              range,
              pixel_width,
              pixel_height,
              thickness
            )

          step ->
            series_to_step_pixels(series, color, min_val, range, pixel_height, thickness)

          connect ->
            series_to_line_pixels(series, color, min_val, range, pixel_height, smooth, thickness)

          true ->
            series_to_pixels(series, color, min_val, range, pixel_height)
        end
      end)

    pixels_by_char = Enum.group_by(all_pixels, fn {{cx, cy}, _, _} -> {cx, cy} end)

    for row <- 0..(height - 1)//1 do
      segments =
        for col <- 0..(width - 1)//1 do
          multi_series_segment(Map.get(pixels_by_char, {col, row}, []), hd(colors), bg)
        end

      Strip.new(segments)
    end
  end

  def series_to_raw_pixels(series, color, min_val, range, pixel_width, pixel_height, thickness) do
    len = length(series)

    if len == 0 or range == 0 do
      []
    else
      stride = pixel_width / len

      series
      |> runs(fn value, idx ->
        {round(idx * stride), pixel_y(value, min_val, range, pixel_height)}
      end)
      |> Enum.flat_map(&connect_raw_points/1)
      |> apply_thickness(thickness)
      |> Enum.map(&dot(&1, color))
    end
  end

  defp connect_raw_points([single]), do: [single]

  defp connect_raw_points(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{x1, y1}, {x2, y2}] ->
      Line.bresenham_line(x1, y1, x2, y2)
    end)
  end

  def series_to_step_pixels(series, color, min_val, range, pixel_height, thickness) do
    series
    |> runs(fn value, x -> {x, pixel_y(value, min_val, range, pixel_height)} end)
    |> Enum.flat_map(&Step.step_lines/1)
    |> apply_thickness(thickness)
    |> Enum.map(&dot(&1, color))
  end

  def series_to_line_pixels(series, color, min_val, range, pixel_height, smooth, thickness) do
    series
    |> runs(fn value, x -> {x, pixel_y(value, min_val, range, pixel_height)} end)
    |> Enum.flat_map(&run_line(&1, smooth))
    |> apply_thickness(thickness)
    |> Enum.map(&dot(&1, color))
  end

  defp run_line([single], _smooth), do: [single]
  defp run_line(points, true), do: Line.catmull_rom_lines(points)
  defp run_line(points, false), do: Line.bresenham_lines(points)

  defp runs(series, to_point) do
    series
    |> Enum.with_index()
    |> Enum.chunk_by(fn {value, _x} -> is_nil(value) end)
    |> Enum.reject(fn [{value, _x} | _] -> is_nil(value) end)
    |> Enum.map(fn run -> Enum.map(run, fn {value, x} -> to_point.(value, x) end) end)
  end

  defp pixel_y(value, min_val, range, pixel_height),
    do: round((1 - (value - min_val) / range) * (pixel_height - 1))

  defp dot({x, y}, color), do: {{div(x, 2), div(y, 4)}, {rem(x, 2), rem(y, 4)}, color}

  defp apply_thickness(pixels, thickness) when thickness <= 1, do: pixels

  defp apply_thickness(pixels, thickness) do
    spread = div(thickness - 1, 2)

    pixels
    |> Enum.flat_map(fn {x, y} -> thicken_point(x, y, spread) end)
    |> Enum.uniq()
  end

  defp thicken_point(x, y, spread) do
    for dy <- -spread..spread, do: {x, y + dy}
  end

  def resolve_multi_series_range(opts, data_series) do
    {data_min, data_max} =
      data_series |> List.flatten() |> Enum.reject(&is_nil/1) |> value_bounds()

    {Keyword.get(opts, :min) || data_min, Keyword.get(opts, :max) || data_max}
  end

  defp value_bounds([]), do: {0, 1}
  defp value_bounds(values), do: Enum.min_max(values)

  def series_to_pixels(series, color, min_val, range, pixel_height) do
    series
    |> runs(fn value, x -> {x, pixel_y(value, min_val, range, pixel_height)} end)
    |> Enum.concat()
    |> Enum.map(&dot(&1, color))
  end

  def multi_series_segment([], _fallback_color, bg), do: Segment.new(" ", %{bg: bg})

  def multi_series_segment(char_pixels, fallback_color, bg) do
    braille_dot_offsets = Pixels.braille_dot_offsets()

    {bits, color} =
      Enum.reduce(char_pixels, {0, nil}, fn {_, {lx, ly}, c}, {b, _} ->
        bit = Map.get(braille_dot_offsets, {lx, ly}, 0)
        {b ||| bit, c}
      end)

    Segment.new(Pixels.braille_char(bits), %{fg: color || fallback_color, bg: bg})
  end
end
