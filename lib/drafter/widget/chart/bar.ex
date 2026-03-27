defmodule Drafter.Widget.Chart.Bar do
  @moduledoc false

  alias Drafter.{CharacterSet, Visualization}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Shared

  @default_series_colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 180, 100},
    {180, 100, 255}
  ]

  def render_bar_chart_v(state, width, height, bg, fg) do
    data_src = state._internal.data_tuple || state.data

    if Shared.tuple_size_or_length(data_src) == 0 do
      Shared.empty_strips(height, bg)
    else
      render_bar_chart_v_data(state, data_src, width, height, bg, fg)
    end
  end

  defp render_bar_chart_v_data(state, data_src, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    levels = CharacterSet.sparkline_levels_v()
    label_row? = state.show_labels and state.bar_labels != []
    bar_height = if label_row?, do: max(1, height - 1), else: height
    {start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, width)
    viewport_labels = Enum.slice(state.bar_labels, start_index, width)
    bars = build_v_bars(state, viewport_data, viewport_labels, levels)
    bar_strips = build_v_bar_strips(bars, bar_height, width, bg, fg)
    maybe_append_label_row(bar_strips, bars, label_row?, width, bg, fg)
  end

  defp build_v_bars(state, viewport_data, viewport_labels, levels) do
    viewport_data
    |> Enum.with_index()
    |> Enum.map(fn {value, i} ->
      normalized = Visualization.normalize(value, state.min_value, state.max_value)
      idx = Visualization.level_index(normalized, levels)
      char = Enum.at(levels, idx)
      value_str = if state.show_values, do: Visualization.format_number(value), else: nil
      label = if state.show_labels, do: Enum.at(viewport_labels, i, ""), else: nil
      {char, value_str, label}
    end)
  end

  defp build_v_bar_strips(bars, bar_height, width, bg, fg) do
    for _row <- 1..bar_height do
      segs = Enum.map(bars, fn {char, _val, _lbl} -> Segment.new(char, %{fg: fg, bg: bg}) end)
      padding_count = max(0, width - length(segs))
      Strip.new(segs ++ List.duplicate(Segment.new(" ", %{bg: bg}), padding_count))
    end
  end

  defp maybe_append_label_row(bar_strips, bars, true, width, bg, fg) do
    label_segs =
      Enum.map(bars, fn {_, _, lbl} ->
        Segment.new(String.slice(lbl || "", 0, 1), %{fg: fg, bg: bg})
      end)

    padding_count = max(0, width - length(label_segs))
    label_strip = Strip.new(label_segs ++ List.duplicate(Segment.new(" ", %{bg: bg}), padding_count))
    bar_strips ++ [label_strip]
  end

  defp maybe_append_label_row(bar_strips, _bars, false, _width, _bg, _fg), do: bar_strips

  def render_bar_chart_h(state, width, height, bg, fg) do
    data_src = state._internal.data_tuple || state.data

    if Shared.tuple_size_or_length(data_src) == 0 do
      Shared.empty_strips(height, bg)
    else
      render_bar_chart_h_data(state, data_src, width, height, bg, fg)
    end
  end

  defp render_bar_chart_h_data(state, data_src, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    {start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, height)
    viewport_labels = Enum.slice(state.bar_labels, start_index, height)
    label_width = h_label_width(state, viewport_labels)
    value_width = h_value_width(state, viewport_data)
    bar_width = max(1, width - label_width - value_width)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1
    full_char = CharacterSet.fill(:full)

    ctx = %{
      state: state,
      levels: levels,
      level_count: level_count,
      full_char: full_char,
      bar_width: bar_width,
      label_width: label_width,
      value_width: value_width,
      viewport_labels: viewport_labels,
      fg: fg,
      bg: bg
    }

    viewport_data
    |> Enum.with_index()
    |> Enum.map(fn {value, i} -> build_h_bar_strip(value, i, ctx) end)
  end

  def h_label_width(state, viewport_labels) do
    if state.show_labels and state.bar_labels != [] do
      viewport_labels |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end) |> max(1)
    else
      0
    end
  end

  def h_value_width(state, viewport_data) do
    if state.show_values do
      viewport_data
      |> Enum.map(fn v -> String.length(Visualization.format_number(v)) end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)
    else
      0
    end
  end

  defp build_h_bar_strip(value, i, %{state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, fg: fg, bg: bg}) do
    normalized = Visualization.normalize(value, state.min_value, state.max_value)
    total_steps = round(normalized * bar_width * level_count)
    full_blocks = div(total_steps, level_count)
    partial_idx = rem(total_steps, level_count)
    full_str = Visualization.safe_duplicate(full_char, full_blocks)
    partial_str = if partial_idx > 0 and full_blocks < bar_width, do: Enum.at(levels, partial_idx, ""), else: ""
    bar_used = full_blocks + if(partial_idx > 0 and full_blocks < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", bar_width - bar_used)
    label_style = %{fg: fg, bg: bg}

    segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, i, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, label_style)]
      else
        []
      end

    segs = segs ++ [Segment.new(IO.iodata_to_binary([full_str, partial_str, padding]), %{fg: fg, bg: bg})]

    segs =
      if value_width > 0 do
        val_str = IO.iodata_to_binary([" ", Visualization.format_number(value)])
        segs ++ [Segment.new(String.pad_trailing(val_str, value_width), label_style)]
      else
        segs
      end

    Strip.new(segs)
  end

  def render_clustered_bar(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> Shared.empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_v(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_clustered_bar_data(state, data, width, height, bg)
    end
  end

  defp render_clustered_bar_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_groups = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    group_width = num_series + gap
    scroll_offset = state._internal.scroll_offset || 0
    viewport_groups = div(width, max(1, group_width))
    end_g = num_groups - scroll_offset
    start_g = max(0, end_g - viewport_groups)
    actual_groups = min(end_g, num_groups) - start_g
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_g, actual_groups) end)
    range = state.max_value - state.min_value
    total_px = height * 2
    zero_pb = round((0 - state.min_value) / range * total_px) |> max(0) |> min(total_px)

    bars =
      for g <- 0..(actual_groups - 1) do
        for s <- 0..(num_series - 1) do
          val = sliced |> Enum.at(s, []) |> Enum.at(g, 0) || 0
          bar_pb = round((val - state.min_value) / range * total_px) |> max(0) |> min(total_px)
          {zero_pb, bar_pb, Enum.at(colors, s, hd(colors))}
        end
      end

    gap_seg = Segment.new(String.duplicate(" ", gap), %{bg: bg})

    ctx = %{
      actual_groups: actual_groups,
      num_series: num_series,
      group_width: group_width,
      width: width,
      bars: bars,
      height: height,
      total_px: total_px,
      gap: gap,
      gap_seg: gap_seg,
      bg: bg
    }

    for row <- 0..(height - 1) do
      segments = build_clustered_row_segments(row, ctx)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  defp build_clustered_row_segments(row, %{actual_groups: actual_groups, num_series: num_series, group_width: group_width, width: width, bars: bars, height: height, total_px: total_px, gap: gap, gap_seg: gap_seg, bg: bg}) do
    Enum.flat_map(0..(actual_groups - 1), fn g ->
      bar_segs =
        0..(num_series - 1)
        |> Enum.filter(fn s -> g * group_width + s < width end)
        |> Enum.map(fn s ->
          {zpb, bpb, color} = bars |> Enum.at(g) |> Enum.at(s)
          half_block_bar_char(row, height, zpb, bpb, total_px, color, bg)
        end)

      if gap > 0 and g < actual_groups - 1, do: bar_segs ++ [gap_seg], else: bar_segs
    end)
  end

  def render_stacked_bar(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> Shared.empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_v(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_stacked_bar_data(state, data, width, height, bg)
    end
  end

  defp render_stacked_bar_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_positions = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    bar_width = 1 + gap
    scroll_offset = state._internal.scroll_offset || 0
    end_p = num_positions - scroll_offset
    start_p = max(0, end_p - div(width, max(1, bar_width)))
    actual = min(end_p, num_positions) - start_p
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_p, actual) end)
    range = state.max_value - state.min_value
    total_px = height * 2
    zero_pb = round((0 - state.min_value) / range * total_px) |> max(0) |> min(total_px)
    stacks = build_stacks(actual, num_series, sliced, colors, zero_pb, range, total_px)
    gap_seg = Segment.new(String.duplicate(" ", gap), %{bg: bg})

    for row <- 0..(height - 1) do
      segments = build_stacked_bar_row(row, height, actual, stacks, total_px, gap, gap_seg, bg)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  defp build_stacked_bar_row(row, height, actual, stacks, total_px, gap, gap_seg, bg) do
    Enum.flat_map(0..(actual - 1), fn p ->
      seg = stacked_bar_char(row, height, Enum.at(stacks, p, []), total_px, bg)
      if gap > 0 and p < actual - 1, do: [seg, gap_seg], else: [seg]
    end)
  end

  defp build_stacks(actual, num_series, sliced, colors, zero_pb, range, total_px) do
    for p <- 0..(actual - 1) do
      Enum.reduce(0..(num_series - 1), {zero_pb, zero_pb, []}, fn s, {pos_top, neg_top, segs} ->
        val = sliced |> Enum.at(s, []) |> Enum.at(p, 0) || 0
        px = round(abs(val) / range * total_px)
        color = Enum.at(colors, s, hd(colors))
        accumulate_stack_segment(val, px, color, pos_top, neg_top, segs)
      end)
      |> elem(2)
      |> Enum.reverse()
    end
  end

  defp accumulate_stack_segment(val, px, color, pos_top, neg_top, segs) when val >= 0 do
    new_top = pos_top + px
    {new_top, neg_top, [{pos_top, new_top, color} | segs]}
  end

  defp accumulate_stack_segment(_val, px, color, pos_top, neg_top, segs) do
    new_bot = neg_top - px
    {pos_top, new_bot, [{new_bot, neg_top, color} | segs]}
  end

  def render_clustered_bar_h(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> Shared.empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_h(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_clustered_bar_h_data(state, data, width, height, bg)
    end
  end

  defp render_clustered_bar_h_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_groups = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    scroll_offset = state._internal.scroll_offset || 0
    viewport_groups = div(height, max(1, num_series + gap))
    end_g = num_groups - scroll_offset
    start_g = max(0, end_g - viewport_groups)
    actual_groups = min(end_g, num_groups) - start_g
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_g, actual_groups) end)
    viewport_labels = Enum.slice(state.bar_labels, start_g, actual_groups)
    label_width = h_label_width(state, viewport_labels)
    value_width = if state.show_values, do: data |> List.flatten() |> Enum.map(fn v -> String.length(Visualization.format_number(v)) end) |> Enum.max(fn -> 0 end) |> Kernel.+(1), else: 0
    bar_width = max(1, width - label_width - value_width)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1
    full_char = CharacterSet.fill(:full)
    gap_strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: bg})])

    strips =
      for g <- 0..(actual_groups - 1) do
        h_ctx = %{
          sliced: sliced,
          colors: colors,
          state: state,
          levels: levels,
          level_count: level_count,
          full_char: full_char,
          bar_width: bar_width,
          label_width: label_width,
          value_width: value_width,
          viewport_labels: viewport_labels,
          bg: bg
        }

        group_strips =
          for s <- 0..(num_series - 1) do
            build_clustered_h_series_strip(s, g, h_ctx)
          end

        if gap > 0 and g < actual_groups - 1,
          do: group_strips ++ List.duplicate(gap_strip, gap),
          else: group_strips
      end
      |> List.flatten()

    Enum.take(strips, height)
  end

  defp build_clustered_h_series_strip(s, g, %{sliced: sliced, colors: colors, state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, bg: bg}) do
    val = sliced |> Enum.at(s, []) |> Enum.at(g, 0) || 0
    color = Enum.at(colors, s, hd(colors))
    normalized = Visualization.normalize(val, state.min_value, state.max_value)
    total_steps = round(normalized * bar_width * level_count)
    full_blocks = div(total_steps, level_count)
    partial_idx = rem(total_steps, level_count)
    full_str = Visualization.safe_duplicate(full_char, full_blocks)
    partial_str = if partial_idx > 0 and full_blocks < bar_width, do: Enum.at(levels, partial_idx, ""), else: ""
    bar_used = full_blocks + if(partial_idx > 0 and full_blocks < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", bar_width - bar_used)

    segs =
      if label_width > 0 do
        lbl = if s == 0, do: Enum.at(viewport_labels, g, "") |> String.pad_trailing(label_width), else: String.duplicate(" ", label_width)
        [Segment.new(lbl, %{fg: color, bg: bg})]
      else
        []
      end

    segs = segs ++ [Segment.new(IO.iodata_to_binary([full_str, partial_str, padding]), %{fg: color, bg: bg})]

    segs =
      if value_width > 0 do
        val_str = IO.iodata_to_binary([" ", Visualization.format_number(val)])
        segs ++ [Segment.new(String.pad_trailing(val_str, value_width), %{fg: color, bg: bg})]
      else
        segs
      end

    Strip.new(segs)
  end

  def render_stacked_bar_h(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> Shared.empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_h(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_stacked_bar_h_data(state, data, width, height, bg)
    end
  end

  defp render_stacked_bar_h_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_positions = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    scroll_offset = state._internal.scroll_offset || 0
    end_p = num_positions - scroll_offset
    start_p = max(0, end_p - (height - gap * max(0, num_positions - 1)))
    actual = min(end_p, num_positions) - start_p
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_p, actual) end)
    viewport_labels = Enum.slice(state.bar_labels, start_p, actual)
    label_width = h_label_width(state, viewport_labels)
    bar_width = max(1, width - label_width)
    range = state.max_value - state.min_value
    full_char = CharacterSet.fill(:full)
    gap_strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: bg})])

    sh_ctx = %{
      sliced: sliced,
      colors: colors,
      num_series: num_series,
      range: range,
      bar_width: bar_width,
      full_char: full_char,
      label_width: label_width,
      viewport_labels: viewport_labels,
      bg: bg
    }

    strips =
      for p <- 0..(actual - 1) do
        strip = build_stacked_h_strip(p, sh_ctx)
        if gap > 0 and p < actual - 1, do: [strip | List.duplicate(gap_strip, gap)], else: [strip]
      end
      |> List.flatten()

    Enum.take(strips, height)
  end

  defp build_stacked_h_strip(p, %{sliced: sliced, colors: colors, num_series: num_series, range: range, bar_width: bar_width, full_char: full_char, label_width: label_width, viewport_labels: viewport_labels, bg: bg}) do
    label_segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, p, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, %{fg: hd(colors), bg: bg})]
      else
        []
      end

    bar_segs =
      for s <- 0..(num_series - 1) do
        val = sliced |> Enum.at(s, []) |> Enum.at(p, 0) || 0
        color = Enum.at(colors, s, hd(colors))
        seg_width = round(abs(val) / range * bar_width)
        Segment.new(Visualization.safe_duplicate(full_char, seg_width), %{fg: color, bg: bg})
      end

    used = Enum.reduce(bar_segs, 0, fn seg, acc -> acc + String.length(seg.text) end)
    padding = Visualization.safe_duplicate(" ", max(0, bar_width - used))
    Strip.new(label_segs ++ bar_segs ++ [Segment.new(padding, %{bg: bg})])
  end

  def render_range_bar(state, _width, height, bg, _fg) when state.data == [], do: Shared.empty_strips(height, bg)

  def render_range_bar(state, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    total = length(state.data)
    end_i = total - scroll_offset
    start_i = max(0, end_i - width)
    viewport = Enum.slice(state.data, start_i, width)
    range = state.max_value - state.min_value
    total_px = height * 2
    bars = render_range_bar_bars(viewport, state, range, total_px)
    render_range_bar_rows(bars, height, width, total_px, fg, bg)
  end

  defp render_range_bar_bars(viewport, state, range, total_px) do
    Enum.map(viewport, fn item ->
      {lo, hi} = extract_range_item(item, state)
      lo_pb = round((lo - state.min_value) / range * total_px) |> max(0) |> min(total_px)
      hi_pb = round((hi - state.min_value) / range * total_px) |> max(0) |> min(total_px)
      {lo_pb, hi_pb}
    end)
  end

  defp render_range_bar_rows(bars, height, width, total_px, fg, bg) do
    for row <- 0..(height - 1) do
      segments = Enum.map(bars, fn {lo_pb, hi_pb} -> half_block_bar_char(row, height, lo_pb, hi_pb, total_px, fg, bg) end)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  def render_range_bar_h(state, width, height, bg, fg) do
    data = state.data

    if data == [] do
      Shared.empty_strips(height, bg)
    else
      render_range_bar_h_data(state, data, width, height, bg, fg)
    end
  end

  defp render_range_bar_h_data(state, data, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    total = length(data)
    end_i = total - scroll_offset
    start_i = max(0, end_i - height)
    viewport = Enum.slice(data, start_i, height)
    viewport_labels = Enum.slice(state.bar_labels, start_i, height)
    label_width = h_label_width(state, viewport_labels)
    value_width = range_bar_value_width(state, viewport)
    bar_width = max(1, width - label_width - value_width)
    full_char = CharacterSet.fill(:full)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1

    rb_ctx = %{
      state: state,
      levels: levels,
      level_count: level_count,
      full_char: full_char,
      bar_width: bar_width,
      label_width: label_width,
      value_width: value_width,
      viewport_labels: viewport_labels,
      fg: fg,
      bg: bg
    }

    viewport
    |> Enum.with_index()
    |> Enum.map(fn {item, i} -> build_range_bar_h_strip(item, i, rb_ctx) end)
  end

  defp range_bar_value_width(state, viewport) do
    if state.show_values do
      viewport
      |> Enum.flat_map(fn item ->
        {lo, hi} = extract_range_item(item, state)
        [String.length(Visualization.format_number(lo)), String.length(Visualization.format_number(hi))]
      end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)
    else
      0
    end
  end

  defp build_range_bar_h_strip(item, i, %{state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, fg: fg, bg: bg}) do
    {lo, hi} = extract_range_item(item, state)
    lo_norm = Visualization.normalize(lo, state.min_value, state.max_value)
    hi_norm = Visualization.normalize(hi, state.min_value, state.max_value)
    lo_steps = round(lo_norm * bar_width * level_count)
    hi_steps = round(hi_norm * bar_width * level_count)
    lo_full = div(lo_steps, level_count)
    hi_full = div(hi_steps, level_count)
    hi_partial = rem(hi_steps, level_count)
    empty_before = Visualization.safe_duplicate(" ", lo_full)
    bar_fill = Visualization.safe_duplicate(full_char, max(0, hi_full - lo_full))
    partial_str = if hi_partial > 0 and hi_full < bar_width, do: Enum.at(levels, hi_partial, ""), else: ""
    used = lo_full + max(0, hi_full - lo_full) + if(hi_partial > 0 and hi_full < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", max(0, bar_width - used))

    segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, i, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, %{fg: fg, bg: bg})]
      else
        []
      end

    segs = segs ++ [Segment.new(IO.iodata_to_binary([empty_before, bar_fill, partial_str, padding]), %{fg: fg, bg: bg})]

    segs =
      if value_width > 0 do
        hi_str = IO.iodata_to_binary([" ", Visualization.format_number(hi)])
        segs ++ [Segment.new(String.pad_trailing(hi_str, value_width), %{fg: fg, bg: bg})]
      else
        segs
      end

    Strip.new(segs)
  end

  def extract_range_item(item, state) do
    case item do
      [l, h | _] -> {l, h}
      {l, h} -> {l, h}
      _ -> {state.min_value, state.min_value}
    end
  end

  def half_block_bar_char(row, height, zero_pb, bar_pb, total_px, color, bg) do
    top_pb = total_px - 1 - 2 * row
    bot_pb = total_px - 2 - 2 * row

    lo = min(zero_pb, bar_pb)
    hi = max(zero_pb, bar_pb) - 1

    if lo > hi do
      Segment.new(" ", %{bg: bg})
    else
      top_filled = lo <= top_pb and top_pb <= hi
      bot_filled = lo <= bot_pb and bot_pb <= hi
      _ = height

      cond do
        top_filled and bot_filled -> Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})
        top_filled -> Segment.new(CharacterSet.fill(:upper_half), %{fg: color, bg: bg})
        bot_filled -> Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})
        true -> Segment.new(" ", %{bg: bg})
      end
    end
  end

  def stacked_bar_char(row, _height, segs, total_px, bg) do
    top_pb = total_px - 1 - 2 * row
    bot_pb = total_px - 2 - 2 * row
    top_hit = Enum.find(segs, fn {lo, hi, _} -> lo <= top_pb and top_pb <= hi - 1 end)
    bot_hit = Enum.find(segs, fn {lo, hi, _} -> lo <= bot_pb and bot_pb <= hi - 1 end)
    stacked_bar_segment(top_hit, bot_hit, bg)
  end

  def stacked_bar_segment(nil, nil, bg), do: Segment.new(" ", %{bg: bg})

  def stacked_bar_segment({_lo, _hi, color}, {_lo2, _hi2, color}, bg),
    do: Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})

  def stacked_bar_segment({_lo, _hi, color}, nil, bg),
    do: Segment.new(CharacterSet.fill(:upper_half), %{fg: color, bg: bg})

  def stacked_bar_segment(nil, {_lo, _hi, color}, bg),
    do: Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})

  def stacked_bar_segment({_lo, _hi, top_color}, {_lo2, _hi2, _bot_color}, bg),
    do: Segment.new(CharacterSet.fill(:upper_half), %{fg: top_color, bg: bg})

  def render_tall_bar_chart(data, height, opts \\ []) do
    min_val = Keyword.get(opts, :min, 0)
    max_val = Keyword.get(opts, :max, 100)
    color = Keyword.get(opts, :color, {100, 200, 100})
    bg = Keyword.get(opts, :bg, {20, 20, 30})

    range = max_val - min_val

    bars =
      data
      |> Enum.map(fn value ->
        normalized = (value - min_val) / range
        {normalized, value}
      end)

    pixel_height = height * 2

    for row <- 0..(height - 1) do
      row_top = (height - 1 - row) * 2
      row_bottom = row_top + 1

      segments =
        Enum.map(bars, fn {normalized, _value} ->
          bar_pixel = round(normalized * pixel_height)
          tall_bar_segment(bar_pixel, row_top, row_bottom, color, bg)
        end)

      Strip.new(segments)
    end
  end

  defp tall_bar_segment(bar_pixel, row_top, _row_bottom, _color, bg) when bar_pixel <= row_top, do: Segment.new(" ", %{bg: bg})
  defp tall_bar_segment(bar_pixel, _row_top, row_bottom, color, bg) when bar_pixel >= row_bottom + 1, do: Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})
  defp tall_bar_segment(bar_pixel, row_top, _row_bottom, color, bg) when bar_pixel == row_top + 1, do: Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})
  defp tall_bar_segment(_bar_pixel, _row_top, _row_bottom, _color, bg), do: Segment.new(" ", %{bg: bg})
end
