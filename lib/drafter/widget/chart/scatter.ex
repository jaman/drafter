defmodule Drafter.Widget.Chart.Scatter do
  @moduledoc false

  alias Drafter.Visualization.LTTB
  alias Drafter.Widget.Chart.{Pixels, Shared}

  @default_series_colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 180, 100},
    {180, 100, 255}
  ]

  def render(state, width, height, bg, fg) do
    data = state.data

    cond do
      data == [] ->
        Shared.empty_strips(height, bg)

      is_list(hd(data)) and hd(data) != [] and is_list(hd(hd(data))) ->
        colors = if state.colors != [], do: state.colors, else: @default_series_colors
        scroll = state._internal.scroll_offset || 0

        render_multi_series_scatter(
          data,
          width,
          height,
          bg,
          colors,
          state.min_value,
          state.max_value,
          scroll
        )

      true ->
        render_single_series(state, data, width, height, bg, fg)
    end
  end

  defp render_single_series(state, data, width, height, bg, fg) do
    points = normalize_scatter_points(data) |> downsample_scatter_points(width * 2)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
    end_x = max_x - scroll_offset
    start_x = max(0, end_x - viewport_width)

    has_weights = Enum.any?(points, fn [_, _, w] -> w != 1.0 end)

    if has_weights do
      colored_pixels =
        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.flat_map(fn [x, y, w] ->
          py = round((y - state.min_value) / range * pixel_height)
          expand_weighted_point(x - start_x, pixel_height - py - 1, w, weight_color(fg, bg, w))
        end)

      Pixels.render_braille_pixels_colored(colored_pixels, width, height, bg)
    else
      pixels =
        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.map(fn [x, y, _w] ->
          pixel_y = round((y - state.min_value) / range * pixel_height)
          {x - start_x, pixel_height - pixel_y - 1}
        end)

      case state.pixel_style do
        :quadrant -> Pixels.render_quadrant_pixels(pixels, width, height, bg, fg)
        _ -> Pixels.render_braille_pixels(pixels, width, height, bg, fg)
      end
    end
  end

  defp render_multi_series_scatter(
         data,
         width,
         height,
         bg,
         colors,
         min_val,
         max_val,
         scroll_offset
       ) do
    range = max_val - min_val
    pixel_height = height * 4
    viewport_width = width * 2

    all_pixels =
      data
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, idx} ->
        color = Enum.at(colors, idx, hd(colors))
        points = normalize_scatter_points(series) |> downsample_scatter_points(viewport_width)
        max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
        end_x = max_x - scroll_offset
        start_x = max(0, end_x - viewport_width)

        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.flat_map(fn [x, y, w] ->
          py = round((y - min_val) / range * pixel_height)
          expand_weighted_point(x - start_x, pixel_height - py - 1, w, weight_color(color, bg, w))
        end)
      end)

    Pixels.render_braille_pixels_colored(all_pixels, width, height, bg)
  end

  def normalize_scatter_points(series) do
    cond do
      series == [] ->
        []

      match?([_, _, _], hd(series)) and is_number(hd(hd(series))) ->
        series

      is_list(hd(series)) and length(hd(series)) == 2 ->
        Enum.map(series, fn [x, y] -> [x, y, 1.0] end)

      match?({_, _, _}, hd(series)) ->
        Enum.map(series, fn {x, y, w} -> [x, y, w] end)

      is_tuple(hd(series)) ->
        Enum.map(series, fn {x, y} -> [x, y, 1.0] end)

      true ->
        series |> Enum.with_index() |> Enum.map(fn {y, x} -> [x, y, 1.0] end)
    end
  end

  def expand_weighted_point(px, py, weight, color) when weight >= 0.7 do
    for dx <- -1..1, dy <- -1..1, abs(dx) + abs(dy) <= 1 do
      {px + dx, py + dy, color}
    end
  end

  def expand_weighted_point(px, py, weight, color) when weight >= 0.4 do
    [{px, py, color}, {px, py - 1, color}, {px, py + 1, color}]
  end

  def expand_weighted_point(px, py, _weight, color) do
    [{px, py, color}]
  end

  def weight_color({fr, fg, fb}, {br, bg_g, bb}, weight) do
    w = min(1.0, max(0.0, weight))
    {round(br + (fr - br) * w), round(bg_g + (fg - bg_g) * w), round(bb + (fb - bb) * w)}
  end

  def downsample_scatter_points(points, target) do
    xy_points = Enum.map(points, fn [x, y | _] -> {x, y} end)
    downsampled = LTTB.downsample(xy_points, target)
    downsampled_set = MapSet.new(downsampled)

    Enum.filter(points, fn [x, y | _] -> MapSet.member?(downsampled_set, {x, y}) end)
  end
end
