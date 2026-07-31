defmodule Drafter.Widget.Chart.BrailleArea do
  @moduledoc false

  import Bitwise

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Visualization.LTTB
  alias Drafter.Widget.Chart.{Pixels, Shared}

  def render(state, width, height, bg) do
    raw = state.data

    series =
      cond do
        raw == [] -> []
        is_number(hd(raw)) -> [raw]
        match?({_, _}, hd(raw)) -> [raw]
        true -> raw
      end

    case series do
      [] -> {Shared.empty_strips(height, bg), state}
      _ -> render_stacked(series, state, width, height, bg)
    end
  end

  defp render_stacked(series, state, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: [{80, 200, 80}, {200, 180, 40}]
    num_series = length(series)
    pixel_h = height * 4
    pixel_w = width * 2

    downsampled_series = Enum.map(series, &downsample_weighted_series(&1, pixel_w))
    stacked = slice_and_stack(downsampled_series, pixel_w, state._internal.scroll_offset || 0)

    range_result = compute_stack_range(stacked, state.zero_center)

    base = %{
      stacked: stacked,
      colors: colors,
      num_series: num_series,
      pixel_h: pixel_h,
      pixel_w: pixel_w,
      char_w: width,
      fill_opacity: state.fill_opacity || 0.6,
      grid: :atomics.new(width * height, signed: false),
      color_grid: Enum.map(0..(width * height - 1)//1, fn _ -> :atomics.new(3, signed: true) end)
    }

    build_braille_area(range_result, base, state, width, height, bg)
  end

  defp build_braille_area({neg_min, pos_max, :split}, base, state, width, height, bg) do
    ctx =
      Map.merge(base, %{
        pos_max: pos_max,
        neg_min: neg_min,
        zero_py: div(base.pixel_h, 2),
        mode: :split
      })

    fill_braille_area_grid(ctx)
    baseline_row = div(div(base.pixel_h, 2), 4)
    strips = render_braille_grid(width, height, base, baseline_row, bg)
    {strips, %{state | min_value: neg_min, max_value: pos_max}}
  end

  defp build_braille_area({stack_min, range, mode}, base, state, width, height, bg) do
    ctx = Map.merge(base, %{range: range, stack_min: stack_min, mode: mode})
    fill_braille_area_grid(ctx)
    baseline_row = compute_baseline_row(state, base.pixel_h, stack_min, range)
    strips = render_braille_grid(width, height, base, baseline_row, bg)
    {strips, %{state | min_value: stack_min, max_value: stack_min + range}}
  end

  defp render_braille_grid(width, height, base, baseline_row, bg) do
    for row <- 0..(height - 1)//1 do
      segments =
        for col <- 0..(width - 1)//1 do
          braille_area_cell(row, col, width, base.grid, base.color_grid, baseline_row, bg)
        end

      Strip.new(segments)
    end
  end

  defp slice_and_stack(series, pixel_w, scroll_offset) do
    normalized = Enum.map(series, &normalize_weighted_series/1)
    max_len = normalized |> Enum.map(&length/1) |> Enum.max()
    end_idx = max(0, max_len - scroll_offset)
    start_idx = max(0, end_idx - pixel_w)
    visible_count = end_idx - start_idx

    sliced = Enum.map(normalized, fn s -> Enum.slice(s, start_idx, visible_count) end)
    build_stacked_columns(sliced, length(series))
  end

  defp normalize_weighted_series(series) do
    Enum.map(series, fn
      {val, weight} when is_number(val) and is_number(weight) -> {val, weight}
      val when is_number(val) -> {val, 1.0}
    end)
  end

  defp compute_stack_range(stacked, zero_center) do
    all_values =
      Enum.flat_map(stacked, fn col ->
        Enum.flat_map(col, fn
          {bottom, top, _weight} -> [bottom, top]
          {bottom, top} -> [bottom, top]
        end)
      end)

    case all_values do
      [] -> {0, 1, :positive}
      vals -> classify_stack_range(Enum.min(vals), Enum.max(vals), zero_center)
    end
  end

  defp classify_stack_range(data_min, data_max, _zc) when data_min >= 0 do
    {0, max(1, data_max), :positive}
  end

  defp classify_stack_range(data_min, data_max, _zc) when data_max <= 0 do
    {data_min, max(1, abs(data_min)), :negative}
  end

  defp classify_stack_range(data_min, data_max, :independent) do
    {min(data_min, -0.001), max(data_max, 0.001), :split}
  end

  defp classify_stack_range(data_min, data_max, _zc) do
    extreme = max(abs(data_min), abs(data_max))
    {-extreme, extreme * 2, :symmetric}
  end

  defp compute_baseline_row(state, pixel_h, stack_min, range) do
    if state.show_baseline do
      baseline_py = pixel_h - 1 - round((0 - stack_min) / range * (pixel_h - 1))
      div(max(0, min(baseline_py, pixel_h - 1)), 4)
    else
      nil
    end
  end

  defp braille_area_cell(row, col, width, grid, color_grid, baseline_row, bg) do
    idx = row * width + col
    bits = :atomics.get(grid, idx + 1)

    if bits == 0 do
      braille_empty_cell(row, baseline_row, bg)
    else
      braille_colored_cell(bits, Enum.at(color_grid, idx), bg)
    end
  end

  defp braille_empty_cell(row, row, bg), do: Segment.new("⠒", %{fg: {60, 60, 60}, bg: bg})
  defp braille_empty_cell(_row, _baseline, bg), do: Segment.new(Pixels.braille_char(0), %{bg: bg})

  defp braille_colored_cell(bits, color_ref, bg) do
    fg_color =
      {:atomics.get(color_ref, 1), :atomics.get(color_ref, 2), :atomics.get(color_ref, 3)}

    Segment.new(Pixels.braille_char(bits), %{fg: fg_color, bg: bg})
  end

  defp build_stacked_columns(sliced, num_series) do
    max_len = sliced |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    for col_idx <- 0..(max_len - 1)//1 do
      Enum.reduce(0..(num_series - 1)//1, {0, 0, []}, fn si, acc ->
        {val, weight} = sliced |> Enum.at(si) |> Enum.at(col_idx, {0, 1.0})
        stack_value(val, weight, acc)
      end)
      |> elem(2)
      |> Enum.reverse()
    end
  end

  defp stack_value(val, weight, {pos_running, neg_running, acc}) when val >= 0 do
    new_top = pos_running + val
    {new_top, neg_running, [{pos_running, new_top, weight} | acc]}
  end

  defp stack_value(val, weight, {pos_running, neg_running, acc}) do
    new_bottom = neg_running + val
    {pos_running, new_bottom, [{new_bottom, neg_running, weight} | acc]}
  end

  defp fill_braille_area_grid(ctx) do
    ctx.stacked
    |> Enum.with_index()
    |> Enum.each(fn {col_layers, col_idx} ->
      if col_idx < ctx.pixel_w do
        fill_braille_column(col_layers, col_idx, ctx)
      end
    end)
  end

  defp fill_braille_column(col_layers, col_idx, ctx) do
    char_col = div(col_idx, 2)
    local_x = rem(col_idx, 2)

    Enum.each(0..(ctx.num_series - 1)//1, fn si ->
      {bottom, top, weight} = extract_layer(Enum.at(col_layers, si))

      if bottom != top do
        series_color = Enum.at(ctx.colors, rem(si, length(ctx.colors)))
        color = weight_modulate(series_color, weight)
        {lo_py, hi_py, top_py} = compute_pixel_range(bottom, top, ctx)
        paint_column_span(lo_py, hi_py, top_py, local_x, char_col, color, ctx)
      end
    end)
  end

  defp paint_column_span(lo_py, hi_py, top_py, local_x, char_col, color, ctx) do
    floor = Map.get(ctx, :fill_opacity, 0.6)
    span = hi_py - lo_py

    Enum.each(lo_py..hi_py, fn py ->
      dot_color = dim_by_depth(color, py, top_py, span, floor)
      paint_braille_dot(py, local_x, char_col, dot_color, ctx)
    end)
  end

  defp dim_by_depth(color, py, top_py, _span, _floor) when py == top_py, do: color

  defp dim_by_depth({r, g, b}, py, top_py, span, floor) when span > 0 do
    depth = abs(py - top_py) / span
    brightness = 1.0 - depth * (1.0 - max(0.5, floor))
    {round(r * brightness), round(g * brightness), round(b * brightness)}
  end

  defp dim_by_depth(color, _py, _top_py, _span, _floor), do: color

  defp weight_modulate(color, 1.0), do: color

  defp weight_modulate({r, g, b}, weight) do
    w = min(1.0, max(0.5, weight))
    {round(r * w), round(g * w), round(b * w)}
  end

  defp extract_layer({bottom, top, weight}), do: {bottom, top, weight}
  defp extract_layer({bottom, top}), do: {bottom, top, 1.0}

  defp compute_pixel_range(bottom, top, %{mode: :split} = ctx) do
    bottom_py = value_to_pixel_split(bottom, ctx)
    top_py = value_to_pixel_split(top, ctx)
    lo_py = max(0, min(top_py, ctx.pixel_h - 1))
    hi_py = max(0, min(bottom_py, ctx.pixel_h - 1))
    {lo_py, hi_py, top_py}
  end

  defp compute_pixel_range(bottom, top, ctx) do
    bottom_py = ctx.pixel_h - 1 - round((bottom - ctx.stack_min) / ctx.range * (ctx.pixel_h - 1))
    top_py = ctx.pixel_h - 1 - round((top - ctx.stack_min) / ctx.range * (ctx.pixel_h - 1))
    lo_py = max(0, min(top_py, ctx.pixel_h - 1))
    hi_py = max(0, min(bottom_py, ctx.pixel_h - 1))
    {lo_py, hi_py, top_py}
  end

  defp value_to_pixel_split(value, ctx) when value >= 0 do
    ctx.zero_py - 1 - round(value / ctx.pos_max * (ctx.zero_py - 1))
  end

  defp value_to_pixel_split(value, ctx) do
    ctx.zero_py + round(value / ctx.neg_min * (ctx.pixel_h - ctx.zero_py - 1))
  end

  defp paint_braille_dot(py, local_x, char_col, color, ctx) do
    braille_dot_offsets = Pixels.braille_dot_offsets()
    local_y = rem(py, 4)
    char_row = div(py, 4)
    bit = Map.get(braille_dot_offsets, {local_x, local_y}, 0)
    idx = char_row * ctx.char_w + char_col + 1
    max_idx = ctx.char_w * div(ctx.pixel_h, 4)

    if idx >= 1 and idx <= max_idx do
      old_bits = :atomics.get(ctx.grid, idx)
      :atomics.put(ctx.grid, idx, old_bits ||| bit)
      set_cell_color(Enum.at(ctx.color_grid, idx - 1), color)
    end
  end

  defp set_cell_color(color_ref, {r, g, b}) do
    :atomics.put(color_ref, 1, r)
    :atomics.put(color_ref, 2, g)
    :atomics.put(color_ref, 3, b)
  end

  def downsample_weighted_series(series, target) when length(series) <= target, do: series

  def downsample_weighted_series(series, target) do
    values =
      Enum.map(series, fn
        {val, _weight} when is_number(val) -> val
        val when is_number(val) -> val
      end)

    points = values |> Enum.with_index() |> Enum.map(fn {y, x} -> {x, y} end)
    downsampled = LTTB.downsample(points, target)
    indices = MapSet.new(Enum.map(downsampled, fn {x, _y} -> round(x) end))

    series
    |> Enum.with_index()
    |> Enum.filter(fn {_elem, idx} -> MapSet.member?(indices, idx) end)
    |> Enum.map(fn {elem, _idx} -> elem end)
  end
end
