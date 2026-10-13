defmodule Drafter.Widget.Chart.Scene.Bars do
  @moduledoc false

  alias Drafter.Visualization
  alias Drafter.Widget.Chart.Scene
  alias Drafter.Widget.Chart.Scene.Data

  @label_color {170, 170, 185, 255}

  def build(spec, grid) do
    case bars(spec.type, spec) do
      {[], _slots, _range} -> nil
      {bars, slot_count, range} -> layout(bars, slot_count, range, spec, grid)
    end
  end

  defp bars(:bar, spec) do
    case Data.classify(spec.data) do
      {:single, items} -> single_bars(Enum.map(items, &(Data.value(&1) || 0)), spec)
      {:multi, series} -> bars(:clustered_bar, %{spec | data: series})
      :empty -> {[], 0, {0, 1}}
    end
  end

  defp bars(:clustered_bar, spec) do
    series = zero_filled(spec.data)
    groups = series |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    colors = Scene.colors(spec)
    parts = length(series)

    bars =
      for {values, si} <- Enum.with_index(series),
          {value, group} <- Enum.with_index(values) do
        %{slot: group, part: {si, parts}, from: 0, to: value, color: Scene.color_at(colors, si)}
      end

    {bars, groups, bar_range(List.flatten(series), spec)}
  end

  defp bars(:stacked_bar, spec) do
    series = zero_filled(spec.data)
    groups = series |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    colors = Scene.colors(spec)

    {bars, totals} =
      Enum.reduce(0..(groups - 1)//1, {[], []}, fn group, {acc, totals} ->
        {stacked, pos, neg} = stack_group(series, group, colors)
        {stacked ++ acc, [pos, neg | totals]}
      end)

    {bars, groups, stacked_range(totals, spec)}
  end

  defp bars(:range_bar, spec) do
    pairs = Data.ranges(spec.data)
    color = Scene.rgba(Map.get(spec, :color))

    bars =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{low, high}, index} ->
        %{slot: index, part: {0, 1}, from: low, to: high, color: color}
      end)

    {bars, length(pairs), Scene.range(Enum.flat_map(pairs, &Tuple.to_list/1), spec)}
  end

  defp bars(:histogram, spec) do
    values = Data.numbers(spec.data)
    bins = values |> length() |> min(40) |> max(5)
    {lo, hi} = Scene.bounds(values)
    counts = histogram_counts(values, lo, hi, bins)
    color = Scene.rgba(Map.get(spec, :color))

    bars =
      counts
      |> Enum.with_index()
      |> Enum.map(fn {count, index} ->
        %{slot: index, part: {0, 1}, from: 0, to: count, color: color}
      end)

    {if(values == [], do: [], else: bars), bins, {0, Enum.max([1 | counts])}}
  end

  defp single_bars(values, spec) do
    color = Scene.rgba(Map.get(spec, :color))

    bars =
      values
      |> Enum.with_index()
      |> Enum.map(fn {value, index} ->
        %{slot: index, part: {0, 1}, from: 0, to: value, color: color}
      end)

    {bars, length(values), bar_range(values, spec)}
  end

  defp zero_filled(data) do
    data
    |> Data.series()
    |> Enum.map(fn items -> Enum.map(items, &(Data.value(&1) || 0)) end)
  end

  defp stack_group(series, group, colors) do
    series
    |> Enum.with_index()
    |> Enum.reduce({[], 0, 0}, fn {values, si}, {acc, pos, neg} ->
      value = Enum.at(values, group) || 0
      color = Scene.color_at(colors, si)

      if value >= 0,
        do:
          {[%{slot: group, part: {0, 1}, from: pos, to: pos + value, color: color} | acc],
           pos + value, neg},
        else:
          {[%{slot: group, part: {0, 1}, from: neg, to: neg + value, color: color} | acc], pos,
           neg + value}
    end)
  end

  defp bar_range(values, spec) do
    case {Map.get(spec, :min), Map.get(spec, :max)} do
      {lo, hi} when is_number(lo) and is_number(hi) -> Scene.widen(lo, hi)
      _ -> Scene.widen(min(0, Enum.min(values, fn -> 0 end)), Enum.max(values, fn -> 1 end))
    end
  end

  defp stacked_range(totals, spec) do
    lo = Map.get(spec, :fixed_min) || min(0, Enum.min(totals, fn -> 0 end))
    hi = Map.get(spec, :fixed_max) || Enum.max([1 | totals])
    Scene.widen(lo, hi)
  end

  defp histogram_counts(values, lo, hi, bins) do
    width = (hi - lo) / bins

    Enum.reduce(values, List.duplicate(0, bins), fn value, acc ->
      index = if width == 0, do: 0, else: min(bins - 1, trunc((value - lo) / width))
      List.update_at(acc, index, &(&1 + 1))
    end)
  end

  defp layout(bars, slot_count, range, spec, grid) do
    horizontal? = Map.get(spec, :orientation) == :horizontal
    capacity = if horizontal?, do: grid.rows, else: grid.cols
    first = max(0, slot_count - capacity)
    visible = slot_count - first
    shown = for bar <- bars, bar.slot >= first, do: %{bar | slot: bar.slot - first}
    labels = Enum.slice(List.wrap(Map.get(spec, :bar_labels)), first, visible)
    plot = plot_area(horizontal?, labels, shown, spec, grid)

    rects =
      shown
      |> Enum.map(&project(&1, visible, plot, range, horizontal?, spec))
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Enum.map(fn {color, boxes} -> {:rects, boxes, color} end)

    %Scene{
      shapes: rects,
      labels: label_cells(horizontal?, labels, shown, visible, plot, spec, grid),
      range: range
    }
  end

  defp plot_area(false, labels, _bars, spec, grid) do
    label_row = if Map.get(spec, :show_labels) == true and labels != [], do: 1, else: 0
    %{x: 0, y: 0, w: grid.cols, h: max(1, grid.rows - label_row), label_w: 0, value_w: 0}
  end

  defp plot_area(true, labels, bars, spec, grid) do
    label_w =
      if Map.get(spec, :show_labels) == true and labels != [],
        do: labels |> Enum.map(&String.length/1) |> Enum.max() |> max(1),
        else: 0

    value_w =
      if Map.get(spec, :show_values) == true,
        do:
          bars |> Enum.map(&String.length(format(&1.to))) |> Enum.max(fn -> 0 end) |> Kernel.+(1),
        else: 0

    w = max(1, grid.cols - label_w - value_w)
    %{x: label_w, y: 0, w: w, h: grid.rows, label_w: label_w, value_w: value_w}
  end

  defp project(bar, slots, plot, range, horizontal?, spec) do
    span = if horizontal?, do: plot.h, else: plot.w
    slot = span / max(1, slots)
    gap = gap(slot, Map.get(spec, :bar_gap) || 0)
    {part, parts} = bar.part
    width = (slot - gap) / parts
    a = slot * bar.slot + gap / 2 + part * width
    b = a + width
    {box(horizontal?, a, b, bar, plot, range), bar.color}
  end

  defp box(false, a, b, bar, plot, range) do
    y0 = Scene.y_of(bar.to, range, plot.y, plot.h)
    y1 = Scene.y_of(bar.from, range, plot.y, plot.h)
    {plot.x + a, min(y0, y1), plot.x + b, max(y0, y1)}
  end

  defp box(true, a, b, bar, plot, range) do
    x0 = Scene.x_of(bar.from, range, plot.x, plot.w)
    x1 = Scene.x_of(bar.to, range, plot.x, plot.w)
    {min(x0, x1), plot.y + a, max(x0, x1), plot.y + b}
  end

  defp gap(_slot, bar_gap) when bar_gap > 0, do: bar_gap
  defp gap(slot, _bar_gap) when slot >= 2, do: slot * 0.2
  defp gap(slot, _bar_gap), do: slot * 0.25

  defp label_cells(false, labels, _bars, slots, plot, spec, grid) do
    if Map.get(spec, :show_labels) == true and labels != [] do
      slot = plot.w / max(1, slots)

      labels
      |> Enum.with_index()
      |> Enum.map(fn {text, index} ->
        {floor(index * slot), grid.rows - 1, String.slice(text, 0, max(1, floor(slot))),
         @label_color}
      end)
    else
      []
    end
  end

  defp label_cells(true, labels, bars, slots, plot, _spec, _grid) do
    slot = plot.h / max(1, slots)
    row_of = fn index -> min(plot.h - 1, floor(index * slot + slot / 2)) end

    names =
      for {text, index} <- Enum.with_index(labels),
          plot.label_w > 0,
          do: {0, row_of.(index), text, @label_color}

    values =
      for bar <- bars, plot.value_w > 0 do
        {plot.x + plot.w + 1, row_of.(bar.slot), format(bar.to), @label_color}
      end

    names ++ values
  end

  defp format(value), do: Visualization.format_number(value)
end
