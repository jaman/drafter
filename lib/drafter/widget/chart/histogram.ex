defmodule Drafter.Widget.Chart.Histogram do
  @moduledoc false

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Shared

  @spec render(struct(), pos_integer(), pos_integer(), tuple(), tuple()) :: [Strip.t()]
  def render(state, width, height, bg, fg) do
    raw_values = extract_raw_values(state.data)

    if raw_values == [] do
      Shared.empty_strips(height, bg)
    else
      render_histogram(state, raw_values, width, height, bg, fg)
    end
  end

  defp render_histogram(state, values, width, height, bg, fg) do
    {data_min, data_max} = {Enum.min(values), Enum.max(values)}

    bin_count = compute_bin_count(length(values), width)

    bins = bin_values(values, data_min, data_max, bin_count)
    bin_counts = Enum.map(bins, &elem(&1, 2))
    max_count = Enum.max(bin_counts)

    label_row? = state.show_labels
    bar_height = if label_row?, do: max(1, height - 1), else: height

    bar_width_per_bin = max(1, div(width, bin_count))
    total_used = bar_width_per_bin * bin_count

    strips = build_strips(bins, max_count, bar_height, bar_width_per_bin, total_used, width, bg, fg)

    if label_row? do
      strips ++ [build_label_strip(bins, bar_width_per_bin, total_used, width, bg, fg)]
    else
      strips
    end
  end

  defp compute_bin_count(n, width) do
    target = max(round(:math.sqrt(n) * 1.5), 10)
    min(target, width)
  end

  defp bin_values(values, data_min, data_max, bin_count) when data_min == data_max do
    for i <- 0..(bin_count - 1) do
      count = if i == 0, do: length(values), else: 0
      {data_min, data_max, count}
    end
  end

  defp bin_values(values, data_min, data_max, bin_count) do
    range = data_max - data_min
    bin_width = range / bin_count

    empty_bins =
      for i <- 0..(bin_count - 1) do
        lo = data_min + i * bin_width
        hi = data_min + (i + 1) * bin_width
        {lo, hi, 0}
      end

    Enum.reduce(values, empty_bins, fn val, bins ->
      idx = floor((val - data_min) / bin_width)
      idx = idx |> max(0) |> min(bin_count - 1)

      List.update_at(bins, idx, fn {lo, hi, count} -> {lo, hi, count + 1} end)
    end)
  end

  defp build_strips(bins, max_count, bar_height, bar_width_per_bin, total_used, width, bg, fg) do
    total_px = bar_height * 2

    for row <- 0..(bar_height - 1) do
      top_pb = total_px - 1 - 2 * row
      bot_pb = total_px - 2 - 2 * row

      bar_segs =
        Enum.flat_map(bins, fn {_lo, _hi, count} ->
          bin_to_segments(count, max_count, total_px, top_pb, bot_pb, bar_width_per_bin, fg, bg)
        end)

      padding_count = max(0, width - total_used)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), padding_count)
      Strip.new(bar_segs ++ padding)
    end
  end

  defp bin_to_segments(count, max_count, total_px, top_pb, bot_pb, bar_width_per_bin, fg, bg) do
    filled_px = if max_count > 0, do: round(count / max_count * total_px), else: 0
    {char, style} = bin_cell_char(filled_px, top_pb, bot_pb, fg, bg)
    List.duplicate(Segment.new(char, style), bar_width_per_bin)
  end

  defp bin_cell_char(filled_px, top_pb, bot_pb, fg, bg) when filled_px > top_pb and filled_px > bot_pb do
    {CharacterSet.fill(:full), %{fg: fg, bg: bg}}
  end

  defp bin_cell_char(filled_px, _top_pb, bot_pb, fg, bg) when filled_px > bot_pb do
    {CharacterSet.fill(:lower_half), %{fg: fg, bg: bg}}
  end

  defp bin_cell_char(_filled_px, _top_pb, _bot_pb, _fg, bg) do
    {" ", %{bg: bg}}
  end

  defp build_label_strip(bins, bar_width_per_bin, total_used, width, bg, fg) do
    label_segs =
      Enum.flat_map(bins, fn {lo, _hi, _count} ->
        label = format_bin_label(lo)
        truncated = String.slice(label, 0, bar_width_per_bin)
        padded = String.pad_trailing(truncated, bar_width_per_bin)
        [Segment.new(padded, %{fg: fg, bg: bg})]
      end)

    padding_count = max(0, width - total_used)
    padding = List.duplicate(Segment.new(" ", %{bg: bg}), padding_count)
    Strip.new(label_segs ++ padding)
  end

  defp format_bin_label(val) when is_float(val) do
    cond do
      abs(val) >= 1_000_000 -> :erlang.float_to_binary(val / 1_000_000, decimals: 1) <> "M"
      abs(val) >= 1_000 -> :erlang.float_to_binary(val / 1_000, decimals: 1) <> "K"
      abs(val) < 0.01 and val != 0.0 -> :erlang.float_to_binary(val, decimals: 3)
      true -> :erlang.float_to_binary(val, decimals: 1)
    end
  end

  defp format_bin_label(val) when is_integer(val), do: Integer.to_string(val)
  defp format_bin_label(val), do: to_string(val)

  defp extract_raw_values(data) when is_list(data) do
    Enum.filter(data, &is_number/1)
  end

  defp extract_raw_values(_), do: []
end
