defmodule Drafter.Widget.Chart.Bubble do
  @moduledoc false

  alias Drafter.Widget.Chart.{Pixels, Shared}

  @size_chars [
    {0.0, "·"},
    {0.25, "•"},
    {0.5, "●"},
    {0.75, "⬤"}
  ]

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

        render_multi_series(
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
    points = normalize_bubble_points(data)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
    end_x = max_x - scroll_offset
    start_x = max(0, end_x - viewport_width)

    {min_size, max_size} = size_range(points)

    colored_pixels =
      points
      |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
      |> Enum.flat_map(fn [x, y, size] ->
        px = round(x - start_x)
        py = round((y - state.min_value) / range * pixel_height)
        norm_size = normalize_size(size, min_size, max_size)
        radius = size_to_radius(norm_size)
        expand_bubble(px, pixel_height - py - 1, radius, fg)
      end)

    Pixels.render_braille_pixels_colored(colored_pixels, width, height, bg)
  end

  defp render_multi_series(data, width, height, bg, colors, min_val, max_val, scroll_offset) do
    range = max_val - min_val
    pixel_height = height * 4
    viewport_width = width * 2

    all_pixels =
      data
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, idx} ->
        color = Enum.at(colors, idx, hd(colors))
        points = normalize_bubble_points(series)
        max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
        end_x = max_x - scroll_offset
        start_x = max(0, end_x - viewport_width)

        {min_size, max_size} = size_range(points)

        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.flat_map(fn [x, y, size] ->
          px = round(x - start_x)
          py = round((y - min_val) / range * pixel_height)
          norm_size = normalize_size(size, min_size, max_size)
          radius = size_to_radius(norm_size)
          expand_bubble(px, pixel_height - py - 1, radius, color)
        end)
      end)

    Pixels.render_braille_pixels_colored(all_pixels, width, height, bg)
  end

  defp normalize_bubble_points(series) do
    cond do
      series == [] ->
        []

      match?([_, _, _], hd(series)) and is_number(hd(hd(series))) ->
        series

      match?({_, _, _}, hd(series)) ->
        Enum.map(series, fn {x, y, size} -> [x, y, size] end)

      is_list(hd(series)) and length(hd(series)) == 2 ->
        Enum.map(series, fn [x, y] -> [x, y, 1.0] end)

      is_tuple(hd(series)) ->
        Enum.map(series, fn {x, y} -> [x, y, 1.0] end)

      true ->
        series |> Enum.with_index() |> Enum.map(fn {y, x} -> [x, y, 1.0] end)
    end
  end

  defp size_range(points) do
    sizes = Enum.map(points, fn [_, _, size] -> size end)

    case sizes do
      [] -> {0, 1}
      _ -> {Enum.min(sizes), Enum.max(sizes)}
    end
  end

  defp normalize_size(_size, min_size, max_size) when max_size == min_size, do: 0.5

  defp normalize_size(size, min_size, max_size) do
    (size - min_size) / (max_size - min_size)
  end

  defp size_to_radius(norm_size) when norm_size >= 0.75, do: 3
  defp size_to_radius(norm_size) when norm_size >= 0.5, do: 2
  defp size_to_radius(norm_size) when norm_size >= 0.25, do: 1
  defp size_to_radius(_norm_size), do: 0

  defp expand_bubble(px, py, 0, color) do
    [{px, py, color}]
  end

  defp expand_bubble(px, py, 1, color) do
    [{px, py, color}, {px, py - 1, color}, {px, py + 1, color}]
  end

  defp expand_bubble(px, py, 2, color) do
    for dx <- -1..1, dy <- -1..1, abs(dx) + abs(dy) <= 1 do
      {px + dx, py + dy, color}
    end
  end

  defp expand_bubble(px, py, 3, color) do
    for dx <- -1..1, dy <- -1..1, abs(dx) + abs(dy) <= 2 do
      {px + dx, py + dy, color}
    end
  end

  def size_char(norm_size) do
    @size_chars
    |> Enum.reverse()
    |> Enum.find(fn {threshold, _char} -> norm_size >= threshold end)
    |> elem(1)
  end
end
