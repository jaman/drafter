defmodule Drafter.Widget.Chart.Scene do
  @moduledoc false

  alias Drafter.Widget.Chart.Scene.{Bars, Marks, Series}

  @type color :: {byte(), byte(), byte(), byte()}
  @type grid :: %{cols: pos_integer(), rows: pos_integer(), sx: pos_integer(), sy: pos_integer()}
  @type point :: {number(), number()}
  @type shape ::
          {:polyline, [point()], color(), pos_integer(), boolean()}
          | {:dots, [point()], color(), number()}
          | {:band, [{number(), number(), number()}], color()}
          | {:rects, [{number(), number(), number(), number()}], color()}
          | {:pie, [{float(), float(), color()}]}
          | {:gauge, float(), color(), color()}
          | {:cells, [{integer(), integer(), String.t(), color(), color() | nil}]}
  @type label :: {non_neg_integer(), non_neg_integer(), String.t(), color()}
  @type t :: %__MODULE__{shapes: [shape()], labels: [label()], range: {number(), number()}}

  defstruct shapes: [], labels: [], range: {0.0, 1.0}

  @series_types [:line, :braille, :step, :area, :braille_area, :stacked_area]
  @bar_types [:bar, :clustered_bar, :stacked_bar, :range_bar, :histogram]
  @mark_types [:scatter, :bubble, :candlestick, :heatmap, :pie, :gauge]

  @palette [
    {120, 200, 255, 255},
    {255, 150, 80, 255},
    {120, 230, 150, 255},
    {220, 130, 230, 255},
    {255, 215, 90, 255},
    {130, 220, 220, 255}
  ]

  @spec build(map(), grid()) :: t() | nil
  def build(%{type: type} = spec, grid) when type in @bar_types, do: Bars.build(spec, grid)
  def build(%{type: type} = spec, grid) when type in @mark_types, do: Marks.build(spec, grid)
  def build(%{type: type} = spec, grid) when type in @series_types, do: Series.build(spec, grid)
  def build(spec, grid), do: Series.build(Map.put(spec, :type, :line), grid)

  def colors(spec) do
    case Map.get(spec, :colors) do
      [_ | _] = list -> Enum.map(list, &rgba/1)
      _ -> [rgba(Map.get(spec, :color)) | tl(@palette)]
    end
  end

  def color_at(colors, index), do: Enum.at(colors, rem(index, length(colors)))

  def rgba({r, g, b}), do: {r, g, b, 255}
  def rgba({r, g, b, a}), do: {r, g, b, a}
  def rgba(_other), do: hd(@palette)

  def mix({r, g, b, a}, background, amount) do
    {br, bg, bb, _} = rgba(background || {0, 0, 0})
    t = amount |> max(0.0) |> min(1.0)
    {round(br + (r - br) * t), round(bg + (g - bg) * t), round(bb + (b - bb) * t), a}
  end

  def range(values, spec) do
    present = Enum.reject(values, &is_nil/1)
    lo = Map.get(spec, :min) || Enum.min(present, fn -> 0.0 end)
    hi = Map.get(spec, :max) || Enum.max(present, fn -> 1.0 end)
    widen(lo, hi)
  end

  def shown_range(values, spec) do
    {lo, hi} = bounds(values)
    pad = (hi - lo) * 0.05
    {Map.get(spec, :fixed_min) || lo - pad, Map.get(spec, :fixed_max) || hi + pad}
  end

  def bounds([]), do: {0.0, 1.0}
  def bounds(values), do: values |> Enum.min_max() |> then(fn {lo, hi} -> widen(lo, hi) end)

  def widen(lo, hi) when hi == lo, do: {lo, lo + 1}
  def widen(lo, hi), do: {lo, hi}

  def y_of(value, {lo, hi}, top, height), do: top + (hi - value) / (hi - lo) * height
  def x_of(value, {lo, hi}, left, width), do: left + (value - lo) / (hi - lo) * width

  def index_x(_index, 1, cols), do: cols / 2
  def index_x(index, count, cols), do: index * cols / (count - 1)

  def line_px(thickness, grid), do: max(1, thickness || 1) * max(1, round(grid.sy / 18))

  def runs(points) do
    points
    |> Enum.chunk_by(&is_nil/1)
    |> Enum.reject(&(hd(&1) == nil))
  end

  def clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
