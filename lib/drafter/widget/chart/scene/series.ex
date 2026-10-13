defmodule Drafter.Widget.Chart.Scene.Series do
  @moduledoc false

  alias Drafter.Visualization.Reduce
  alias Drafter.Widget.Chart.Scene
  alias Drafter.Widget.Chart.Scene.Data

  @baseline_color {70, 70, 80, 255}

  def build(spec, grid) do
    case Data.series(spec.data) do
      [] -> nil
      series -> draw(spec.type, series, spec, grid)
    end
  end

  defp draw(:braille_area, series, spec, grid) do
    if Map.get(spec, :stacked, true),
      do: layered(series, spec, grid, &stack_column/1),
      else: layered(series, spec, grid, &overlay_column/1)
  end

  defp draw(:stacked_area, series, spec, grid) do
    zero_filled = Enum.map(series, fn items -> Enum.map(items, &(Data.value(&1) || 0)) end)
    layered(zero_filled, Map.put(spec, :zero_center, :linear), grid, &stack_column/1)
  end

  defp draw(type, series, spec, grid) do
    width = grid.cols * grid.sx
    fitted = Enum.map(series, &fit_line(Data.values(&1), width))
    range = Scene.range(List.flatten(fitted), spec)
    colors = Scene.colors(spec)

    shapes =
      fitted
      |> Enum.with_index()
      |> Enum.flat_map(fn {values, si} ->
        series_shapes(type, values, range, Scene.color_at(colors, si), spec, grid)
      end)

    %Scene{shapes: shapes, range: range}
  end

  defp fit_line(values, width) when length(values) > width * 2,
    do: Reduce.min_max(values, width)

  defp fit_line(values, _width), do: values

  defp series_shapes(:area, values, range, color, spec, grid) do
    runs = values |> points(range, grid) |> Scene.runs()
    fill = Scene.mix(color, Map.get(spec, :bg), Map.get(spec, :fill_opacity) || 0.4)
    edge = if Map.get(spec, :area_fill) == :inverted, do: 0, else: grid.rows

    bands =
      Enum.map(runs, fn run -> {:band, Enum.map(run, fn {x, y} -> {x, y, edge} end), fill} end)

    bands ++ lines(runs, color, spec, grid)
  end

  defp series_shapes(:step, values, range, color, spec, grid) do
    values
    |> points(range, grid)
    |> Scene.runs()
    |> Enum.map(&step_points/1)
    |> lines(color, Map.put(spec, :smooth, false), grid)
  end

  defp series_shapes(_line, values, range, color, spec, grid) do
    runs = values |> points(range, grid) |> Scene.runs()

    if Map.get(spec, :connect_lines, true),
      do: lines(runs, color, spec, grid),
      else: [
        {:dots, Enum.concat(runs), color, Scene.line_px(Map.get(spec, :line_thickness), grid) / 2}
      ]
  end

  defp lines(runs, color, spec, grid) do
    width = Scene.line_px(Map.get(spec, :line_thickness), grid)
    Enum.map(runs, &{:polyline, &1, color, width, Map.get(spec, :smooth, false)})
  end

  defp points(values, range, grid) do
    count = length(values)

    values
    |> Enum.with_index()
    |> Enum.map(fn
      {nil, _index} ->
        nil

      {value, index} ->
        {Scene.index_x(index, count, grid.cols), Scene.y_of(value, range, 0, grid.rows)}
    end)
  end

  defp step_points([]), do: []

  defp step_points([first | rest]) do
    rest
    |> Enum.reduce({[first], first}, fn {x, y}, {acc, {_px, py}} ->
      {[{x, y}, {x, py} | acc], {x, y}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp layered(series, spec, grid, column_fun) do
    width = grid.cols * grid.sx
    weighted = Enum.map(series, &normalize_items/1)
    longest = weighted |> Enum.map(&length/1) |> Enum.max()

    columns =
      weighted
      |> Enum.map(&(&1 ++ List.duplicate(nil, longest - length(&1))))
      |> Reduce.aligned_peaks(width, &elem(&1, 0))
      |> Enum.zip_with(column_fun)

    scale = stack_scale(columns, spec)
    count = length(columns)
    colors = Scene.colors(spec)

    layer_shapes = layers(columns, length(series), count, scale, colors, spec, grid)

    %Scene{
      shapes: baseline(scale, spec, grid) ++ layer_shapes,
      range: scale_range(scale)
    }
  end

  defp normalize_items(items) do
    Enum.map(items, fn
      {value, weight} when is_number(value) and is_number(weight) -> {value, weight}
      value when is_number(value) -> {value, 1.0}
      _gap -> nil
    end)
  end

  defp stack_column(layers) do
    layers
    |> Enum.reduce({0, 0, []}, fn
      nil, {pos, neg, acc} ->
        {pos, neg, [nil | acc]}

      {value, weight}, {pos, neg, acc} when value >= 0 ->
        {pos + value, neg, [{pos, pos + value, weight} | acc]}

      {value, weight}, {pos, neg, acc} ->
        {pos, neg + value, [{neg + value, neg, weight} | acc]}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  defp overlay_column(layers) do
    Enum.map(layers, fn
      nil -> nil
      {value, weight} when value >= 0 -> {0, value, weight}
      {value, weight} -> {value, 0, weight}
    end)
  end

  defp layers(columns, layer_count, count, scale, colors, spec, grid) do
    for si <- 0..(layer_count - 1)//1,
        run <- layer_runs(columns, si, count, scale, grid),
        shape <- layer_shapes(run, Scene.color_at(colors, si), spec, grid) do
      shape
    end
  end

  defp layer_runs(columns, si, count, scale, grid) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {column, ci} ->
      case Enum.at(column, si) do
        nil ->
          nil

        {bottom, top, weight} ->
          x = Scene.index_x(ci, count, grid.cols)
          {x, stack_y(top, scale, grid), stack_y(bottom, scale, grid), weight}
      end
    end)
    |> Scene.runs()
  end

  defp layer_shapes(run, color, spec, grid) do
    weight = run |> Enum.map(&elem(&1, 3)) |> Enum.max()
    edge = weighted_color(color, weight)
    fill = Scene.mix(edge, Map.get(spec, :bg), Map.get(spec, :fill_opacity) || 0.6)
    band = Enum.map(run, fn {x, top, bottom, _w} -> {x, top, bottom} end)
    top = Enum.map(run, fn {x, top, _bottom, _w} -> {x, top} end)

    [
      {:band, band, fill},
      {:polyline, top, edge, Scene.line_px(Map.get(spec, :line_thickness), grid), false}
    ]
  end

  defp weighted_color(color, weight) when weight >= 1.0, do: color
  defp weighted_color(color, weight), do: Scene.mix(color, {0, 0, 0}, max(0.5, weight))

  defp stack_scale(columns, spec) do
    values = for column <- columns, {bottom, top, _w} <- column, value <- [bottom, top], do: value

    case {Map.get(spec, :fixed_min), Map.get(spec, :fixed_max), values} do
      {lo, hi, _values} when is_number(lo) and is_number(hi) ->
        {:linear, Scene.widen(lo, hi)}

      {_lo, _hi, []} ->
        {:linear, {0, 1}}

      {_lo, _hi, values} ->
        classify(Enum.min(values), Enum.max(values), Map.get(spec, :zero_center))
    end
  end

  defp classify(lo, hi, _mode) when lo >= 0, do: {:linear, {0, max(1, hi)}}
  defp classify(lo, hi, _mode) when hi <= 0, do: {:linear, {min(-1, lo), 0}}
  defp classify(lo, hi, :linear), do: {:linear, {lo, hi}}
  defp classify(lo, hi, :independent), do: {:split, min(lo, -0.001), max(hi, 0.001)}

  defp classify(lo, hi, _symmetric) do
    extreme = max(abs(lo), abs(hi))
    {:linear, {-extreme, extreme}}
  end

  defp stack_y(value, {:linear, range}, grid), do: Scene.y_of(value, range, 0, grid.rows)

  defp stack_y(value, {:split, _neg, pos}, grid) when value >= 0,
    do: grid.rows / 2 * (1 - value / pos)

  defp stack_y(value, {:split, neg, _pos}, grid), do: grid.rows / 2 * (1 + value / neg)

  defp scale_range({:linear, range}), do: range
  defp scale_range({:split, neg, pos}), do: {neg, pos}

  defp baseline(scale, %{show_baseline: true} = spec, grid) do
    y = stack_y(0, scale, grid)

    [
      {:polyline, [{0, y}, {grid.cols, y}], @baseline_color,
       Scene.line_px(Map.get(spec, :line_thickness), grid), false}
    ]
  end

  defp baseline(_scale, _spec, _grid), do: []
end
