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

    scrolled_series =
      Enum.map(data, fn series ->
        {_start, slice} = Drafter.ScrollMath.end_anchored_slice(series, scroll_offset, viewport_width)
        LTTB.downsample_series(slice, viewport_width)
      end)

    MultiSeries.render(scrolled_series, width, height,
      bg: bg,
      colors: colors,
      min: state.min_value,
      max: state.max_value
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
    lines = bresenham_lines(points)

    case state.pixel_style do
      :quadrant -> Pixels.render_quadrant_pixels(lines, width, height, bg, fg)
      _ -> Pixels.render_braille_pixels(lines, width, height, bg, fg)
    end
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
end
