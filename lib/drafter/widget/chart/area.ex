defmodule Drafter.Widget.Chart.Area do
  @moduledoc false

  alias Drafter.Widget.Chart.{Line, MultiSeries, Pixels, Shared}

  @area_default_colors [
    {100, 200, 255},
    {255, 130, 80},
    {80, 255, 150},
    {255, 100, 180},
    {200, 180, 60},
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
    colors = if state.colors != [], do: state.colors, else: @area_default_colors

    MultiSeries.render(data, width, height,
      bg: bg,
      colors: colors,
      min: state.min_value,
      max: state.max_value
    )
  end

  defp render_single_series(state, data_src, width, height, bg, fg, animation_offset) do
    range = state.max_value - state.min_value
    pixel_height = height * 4
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2

    {_start_index, viewport_data} =
      Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, viewport_width)

    normalized = Shared.normalize_data(viewport_data, state.min_value, range, pixel_height)
    shifted = Line.apply_animation_shift(normalized, animation_offset)

    pixels =
      shifted
      |> Enum.with_index()
      |> Enum.flat_map(fn {y, x} -> area_fill_pixels(x, y, pixel_height, state.area_fill) end)

    Pixels.render_braille_pixels(pixels, width, height, bg, fg)
  end

  def area_fill_pixels(x, y, pixel_height, :inverted) do
    flipped = pixel_height - 1 - y
    for yi <- flipped..(pixel_height - 1), do: {x, yi}
  end

  def area_fill_pixels(x, y, _pixel_height, _fill) do
    for yi <- 0..y, do: {x, yi}
  end
end
