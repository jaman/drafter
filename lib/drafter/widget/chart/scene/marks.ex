defmodule Drafter.Widget.Chart.Scene.Marks do
  @moduledoc false

  alias Drafter.Widget.Chart.Scene
  alias Drafter.Widget.Chart.Scene.Data

  @up_color {90, 200, 130, 255}
  @down_color {220, 90, 90, 255}

  def build(%{type: :scatter} = spec, grid) do
    case Data.scatter_series(spec.data) do
      [] -> nil
      series -> scatter(series, spec, grid)
    end
  end

  def build(%{type: :bubble} = spec, grid) do
    case Data.points(spec.data) do
      [] -> nil
      points -> bubbles(points, spec, grid)
    end
  end

  def build(%{type: :candlestick} = spec, grid) do
    case Data.candles(spec.data) do
      [] -> nil
      candles -> candlesticks(Enum.take(candles, -grid.cols), spec, grid)
    end
  end

  def build(%{type: :heatmap} = spec, grid) do
    case Data.grid(spec.data) do
      [] -> nil
      rows -> heatmap(rows, grid)
    end
  end

  def build(%{type: :pie, slices: [_ | _] = slices}, _grid) do
    total = slices |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> max(1) |> Kernel.*(1.0)
    %Scene{shapes: [{:pie, pie_ranges(slices, total)}]}
  end

  def build(%{type: :gauge, value: value, fill: fill, track: track}, _grid) do
    %Scene{
      shapes: [{:gauge, Scene.clamp(value * 1.0, 0.0, 1.0), Scene.rgba(fill), Scene.rgba(track)}]
    }
  end

  def build(_spec, _grid), do: nil

  defp scatter(series, spec, grid) do
    all = Enum.concat(series)
    x_range = Scene.bounds(Enum.map(all, &Data.point_x/1))
    y_range = Scene.range(Enum.map(all, &Data.point_y/1), spec)
    colors = Scene.colors(spec)
    radius = dot_radius(grid)

    shapes =
      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {points, si} ->
        color = Scene.color_at(colors, si)

        points
        |> Enum.group_by(&weight_shade(color, Data.point_weight(&1), spec))
        |> Enum.map(fn {shade, group} ->
          {:dots, Enum.map(group, &place(&1, x_range, y_range, grid)), shade, radius}
        end)
      end)

    %Scene{shapes: shapes, range: y_range}
  end

  defp bubbles(points, spec, grid) do
    x_range = Scene.bounds(Enum.map(points, &Data.point_x/1))
    y_range = Scene.range(Enum.map(points, &Data.point_y/1), spec)
    largest = points |> Enum.map(&Data.point_weight/1) |> Enum.max() |> max(1)
    color = Scene.rgba(Map.get(spec, :color))

    shapes =
      Enum.map(points, fn point ->
        radius = max(0.25, 1.5 * Data.point_weight(point) / largest) * grid.sx
        {:dots, [place(point, x_range, y_range, grid)], color, radius}
      end)

    %Scene{shapes: shapes, range: y_range}
  end

  defp place(point, x_range, y_range, grid) do
    {Scene.x_of(Data.point_x(point), x_range, 0, grid.cols),
     Scene.y_of(Data.point_y(point), y_range, 0, grid.rows)}
  end

  defp dot_radius(grid), do: max(1, round(grid.sx / 2))

  defp weight_shade(color, weight, _spec) when weight >= 1, do: color

  defp weight_shade(color, weight, spec),
    do: Scene.mix(color, Map.get(spec, :bg), 0.35 + 0.65 * weight)

  defp candlesticks(candles, spec, grid) do
    range = Scene.shown_range(Enum.flat_map(candles, fn {_o, h, l, _c} -> [h, l] end), spec)
    slot = grid.cols / length(candles)
    body = max(slot * 0.6, 1 / grid.sx)

    shapes =
      candles
      |> Enum.with_index()
      |> Enum.flat_map(fn {{open, high, low, close}, index} ->
        color = if close >= open, do: @up_color, else: @down_color
        cx = slot * index + slot / 2
        top = Scene.y_of(max(open, close), range, 0, grid.rows)
        bottom = Scene.y_of(min(open, close), range, 0, grid.rows)

        wick = [
          {cx, Scene.y_of(high, range, 0, grid.rows)},
          {cx, Scene.y_of(low, range, 0, grid.rows)}
        ]

        [
          {:polyline, wick, color, 1, false},
          {:rects, [{cx - body / 2, top, cx + body / 2, max(bottom, top + 1 / grid.sy)}], color}
        ]
      end)

    %Scene{shapes: shapes, range: range}
  end

  defp heatmap(rows, grid) do
    {lo, hi} = Scene.bounds(List.flatten(rows))
    columns = rows |> Enum.map(&length/1) |> Enum.max()
    cell_w = grid.cols / columns
    cell_h = grid.rows / length(rows)

    shapes =
      for {row, ry} <- Enum.with_index(rows), {value, cx} <- Enum.with_index(row) do
        {:rects, [{cx * cell_w, ry * cell_h, (cx + 1) * cell_w, (ry + 1) * cell_h}],
         heat_color(value, lo, hi)}
      end

    %Scene{shapes: shapes, range: {lo, hi}}
  end

  defp heat_color(value, lo, hi) do
    t = if hi == lo, do: 0.0, else: (value - lo) / (hi - lo)
    {round(40 + t * 200), round(70 + t * 60 - t * t * 50), round(150 - t * 110), 255}
  end

  defp pie_ranges(slices, total) do
    slices
    |> Enum.reduce({[], 0.0}, fn {value, color}, {acc, start} ->
      sweep = value / total * 2 * :math.pi()
      {[{start, start + sweep, Scene.rgba(color)} | acc], start + sweep}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
