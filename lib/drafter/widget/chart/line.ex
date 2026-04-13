defmodule Drafter.Widget.Chart.Line do
  @moduledoc false

  alias Drafter.Visualization.LTTB
  alias Drafter.Widget.Chart.{MultiSeries, Pixels, Shared}

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

  def render_braille(state, width, height, bg, fg, animation_offset) do
    render(%{state | chart_type: :line}, width, height, bg, fg, animation_offset)
  end

  defp render_multi_series(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    raw_data = Map.get(state._internal, :raw_data, false)

    prepared_series =
      Enum.map(data, fn series ->
        {_start, slice} = Drafter.ScrollMath.end_anchored_slice(series, scroll_offset, viewport_width)

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
      smooth: Map.get(state._internal, :smooth, false),
      line_thickness: Map.get(state._internal, :line_thickness, 1),
      connect_lines: Map.get(state._internal, :connect_lines, false),
      raw_data: raw_data
    )
  end

  defp render_single_series(state, data_src, width, height, bg, fg, animation_offset) do
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    {_start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, viewport_width)
    downsampled = LTTB.downsample_series(viewport_data, viewport_width)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    normalized = Shared.normalize_data(downsampled, state.min_value, range, pixel_height)
    shifted = apply_animation_shift(normalized, animation_offset)
    points = Enum.with_index(shifted) |> Enum.map(fn {y, x} -> {x, y} end)
    smooth = Map.get(state._internal, :smooth, false)
    line_pixels = if smooth, do: catmull_rom_lines(points), else: bresenham_lines(points)
    thickness = Map.get(state._internal, :line_thickness, 1)
    thickened = if thickness > 1, do: thicken_line(line_pixels, thickness), else: line_pixels

    case state.pixel_style do
      :quadrant -> Pixels.render_quadrant_pixels(thickened, width, height, bg, fg)
      _ -> Pixels.render_braille_pixels(thickened, width, height, bg, fg)
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

  def apply_animation_shift(normalized, animation_offset) when animation_offset > 0 do
    shift = rem(animation_offset, length(normalized))
    Enum.drop(normalized, shift) ++ Enum.take(normalized, shift)
  end

  def apply_animation_shift(normalized, _animation_offset), do: normalized

  def normalize_data(data, min_val, range, pixel_height) do
    Shared.normalize_data(data, min_val, range, pixel_height)
  end

  def bresenham_lines([]), do: []
  def bresenham_lines([_single]), do: []

  def bresenham_lines([{x1, y1} | rest]) do
    case rest do
      [{x2, y2} | _] -> bresenham_line(x1, y1, x2, y2) ++ bresenham_lines(rest)
      [] -> []
    end
  end

  def bresenham_line(x1, y1, x2, y2) do
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)
    ctx = {x2, y2, if(x1 < x2, do: 1, else: -1), if(y1 < y2, do: 1, else: -1), dx, dy}
    bresenham_loop(x1, y1, dx - dy, ctx, [])
  end

  def bresenham_loop(x, y, _err, {x2, y2, _sx, _sy, _dx, _dy}, acc) when x == x2 and y == y2 do
    Enum.reverse([{x, y} | acc])
  end

  def bresenham_loop(x, y, err, {_x2, _y2, sx, sy, dx, dy} = ctx, acc) do
    e2 = 2 * err
    {new_x, new_err} = if e2 > -dy, do: {x + sx, err - dy}, else: {x, err}
    {new_y, final_err} = if e2 < dx, do: {y + sy, new_err + dx}, else: {y, new_err}
    bresenham_loop(new_x, new_y, final_err, ctx, [{x, y} | acc])
  end

  def catmull_rom_lines(points) when length(points) < 3, do: bresenham_lines(points)

  def catmull_rom_lines(points) do
    padded = [hd(points)] ++ points ++ [List.last(points)]
    segments = Enum.chunk_every(padded, 4, 1, :discard)

    Enum.flat_map(segments, fn [p0, p1, p2, p3] ->
      interpolate_segment(p0, p1, p2, p3, 8)
    end)
    |> Enum.uniq()
  end

  defp interpolate_segment({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, steps) do
    for i <- 0..steps do
      t = i / steps
      t2 = t * t
      t3 = t2 * t

      x =
        0.5 *
          (2.0 * x1 + (-x0 + x2) * t + (2.0 * x0 - 5.0 * x1 + 4.0 * x2 - x3) * t2 +
             (-x0 + 3.0 * x1 - 3.0 * x2 + x3) * t3)

      y =
        0.5 *
          (2.0 * y1 + (-y0 + y2) * t + (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * t2 +
             (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * t3)

      {round(x), round(y)}
    end
  end
end
