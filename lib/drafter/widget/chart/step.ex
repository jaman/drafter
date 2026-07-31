defmodule Drafter.Widget.Chart.Step do
  @moduledoc false

  alias Drafter.Visualization.LTTB
  alias Drafter.Widget.Chart.{Line, MultiSeries, Pixels, Shared}

  @default_series_colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 180, 100},
    {180, 100, 255}
  ]

  def render(state, width, height, bg, fg, animation_offset) do
    data = state.data
    data_src = state._internal.data_tuple || data

    cond do
      Shared.tuple_size_or_length(data_src) < 2 ->
        Shared.empty_strips(height, bg)

      is_list(data) and is_list(hd(data)) ->
        render_multi_series(state, data, width, height, bg)

      true ->
        render_single_series(state, data_src, width, height, bg, fg, animation_offset)
    end
  end

  defp render_multi_series(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    raw_data = Map.get(state._internal, :raw_data, false)

    prepared_series =
      Enum.map(data, fn series ->
        {_start, slice} =
          Drafter.ScrollMath.end_anchored_slice(series, scroll_offset, viewport_width)

        if raw_data do
          slice
        else
          LTTB.downsample_series(slice, viewport_width)
        end
      end)

    MultiSeries.render(prepared_series, width, height,
      bg: bg,
      colors: colors,
      min: state.min_value,
      max: state.max_value,
      smooth: false,
      line_thickness: Map.get(state._internal, :line_thickness, 1),
      connect_lines: Map.get(state._internal, :connect_lines, false),
      raw_data: raw_data,
      step: true
    )
  end

  defp render_single_series(state, data_src, width, height, bg, fg, animation_offset) do
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2

    {_start_index, viewport_data} =
      Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, viewport_width)

    downsampled = LTTB.downsample_series(viewport_data, viewport_width)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    normalized = Shared.normalize_data(downsampled, state.min_value, range, pixel_height)
    shifted = Line.apply_animation_shift(normalized, animation_offset)
    points = Enum.with_index(shifted) |> Enum.map(fn {y, x} -> {x, y} end)
    line_pixels = step_lines(points)
    thickness = Map.get(state._internal, :line_thickness, 1)
    thickened = if thickness > 1, do: thicken_line(line_pixels, thickness), else: line_pixels

    case state.pixel_style do
      :quadrant -> Pixels.render_quadrant_pixels(thickened, width, height, bg, fg)
      _ -> Pixels.render_braille_pixels(thickened, width, height, bg, fg)
    end
  end

  def step_lines([]), do: []
  def step_lines([_single]), do: []

  def step_lines([{x1, y1} | rest]) do
    case rest do
      [{x2, y2} | _] ->
        horizontal = Line.bresenham_line(x1, y1, x2, y1)
        vertical = Line.bresenham_line(x2, y1, x2, y2)
        horizontal ++ vertical ++ step_lines(rest)

      [] ->
        []
    end
  end

  defp thicken_line(pixels, thickness) do
    spread = div(thickness - 1, 2)

    pixels
    |> Enum.flat_map(fn {x, y} ->
      for dy <- -spread..spread, do: {x, y + dy}
    end)
    |> Enum.uniq()
  end
end
