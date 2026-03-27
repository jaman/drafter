defmodule Drafter.Widget.Chart.MultiSeries do
  @moduledoc false

  import Bitwise

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Pixels

  @multi_series_default_colors [{255, 100, 100}, {100, 255, 100}, {100, 100, 255}, {255, 255, 100}]

  def render(data_series, width, height, opts \\ []) do
    bg = Keyword.get(opts, :bg, {20, 20, 30})
    colors = Keyword.get(opts, :colors, @multi_series_default_colors)
    {min_val, max_val} = resolve_multi_series_range(opts, data_series)
    range = max_val - min_val
    pixel_height = height * 4
    colors_tuple = List.to_tuple(colors)
    color_count = tuple_size(colors_tuple)

    all_pixels =
      data_series
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, series_idx} ->
        color = elem(colors_tuple, rem(series_idx, color_count))
        series_to_pixels(series, color, min_val, range, pixel_height)
      end)

    pixels_by_char = Enum.group_by(all_pixels, fn {{cx, cy}, _, _} -> {cx, cy} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          multi_series_segment(Map.get(pixels_by_char, {col, row}, []), hd(colors), bg)
        end

      Strip.new(segments)
    end
  end

  def resolve_multi_series_range(opts, data_series) do
    case {Keyword.get(opts, :min), Keyword.get(opts, :max)} do
      {nil, nil} ->
        all_values = List.flatten(data_series)
        {Enum.min(all_values), Enum.max(all_values)}

      {nil, max} ->
        {data_series |> List.flatten() |> Enum.min(), max}

      {min, nil} ->
        {min, data_series |> List.flatten() |> Enum.max()}

      {min, max} ->
        {min, max}
    end
  end

  def series_to_pixels(series, color, min_val, range, pixel_height) do
    series
    |> Enum.with_index()
    |> Enum.map(fn {value, x} ->
      normalized = (value - min_val) / range
      y = round((1 - normalized) * (pixel_height - 1))
      {{div(x, 2), div(y, 4)}, {rem(x, 2), rem(y, 4)}, color}
    end)
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
