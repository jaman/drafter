defmodule Drafter.Widget.Chart.Scene.Data do
  @moduledoc false

  def classify(data) do
    cond do
      not is_list(data) or data == [] -> :empty
      value_list?(data) -> {:single, data}
      Enum.any?(data, &value_list?/1) -> {:multi, Enum.filter(data, &value_list?/1)}
      true -> :empty
    end
  end

  def series(data) do
    case classify(data) do
      {:single, values} -> [values]
      {:multi, series} -> series
      :empty -> []
    end
  end

  def value(n) when is_number(n), do: n
  def value({v, _weight}) when is_number(v), do: v
  def value(_other), do: nil

  def weight({_v, weight}) when is_number(weight), do: weight
  def weight(_other), do: 1.0

  def values(list), do: Enum.map(list, &value/1)

  def series_weight(items) do
    items |> Enum.map(&weight/1) |> Enum.max(fn -> 1.0 end)
  end

  def numbers(data) when is_list(data), do: Enum.filter(data, &is_number/1)
  def numbers(_data), do: []

  def ranges(data) when is_list(data),
    do: data |> Enum.map(&range_pair/1) |> Enum.reject(&is_nil/1)

  def ranges(_data), do: []

  def grid(data) when is_list(data), do: Enum.filter(data, &number_list?/1)
  def grid(_data), do: []

  def candles(data) when is_list(data),
    do: data |> Enum.map(&candle/1) |> Enum.reject(&is_nil/1)

  def candles(_data), do: []

  def scatter_series(data) when not is_list(data), do: []
  def scatter_series([]), do: []

  def scatter_series([first | _] = data) do
    cond do
      point?(first) -> [points(data)]
      is_number(first) -> [indexed_points(data)]
      is_list(first) -> nested_series(first, data)
      true -> []
    end
  end

  def points(data) when is_list(data), do: Enum.filter(data, &point?/1)
  def points(_data), do: []

  def point_x(%{x: x}), do: x
  def point_x([x, _y | _]), do: x
  def point_x({x, _y}), do: x
  def point_x({x, _y, _w}), do: x

  def point_y(%{y: y}), do: y
  def point_y([_x, y | _]), do: y
  def point_y({_x, y}), do: y
  def point_y({_x, y, _w}), do: y

  def point_weight(%{weight: weight}), do: weight
  def point_weight([_x, _y, weight | _]), do: weight
  def point_weight({_x, _y, weight}), do: weight
  def point_weight(_other), do: 1

  defp value_list?([_ | _] = list),
    do: Enum.all?(list, &(is_nil(&1) or value?(&1))) and Enum.any?(list, &value?/1)

  defp value_list?(_other), do: false

  defp value?(n) when is_number(n), do: true
  defp value?({v, _weight}) when is_number(v), do: true
  defp value?(_other), do: false

  defp number_list?([n | _]) when is_number(n), do: true
  defp number_list?(_other), do: false

  defp range_pair([lo, hi]) when is_number(lo) and is_number(hi), do: {lo, hi}
  defp range_pair({lo, hi}) when is_number(lo) and is_number(hi), do: {lo, hi}
  defp range_pair(_other), do: nil

  defp candle([o, h, l, c]) when is_number(o), do: {o, h, l, c}
  defp candle(%{open: o, high: h, low: l, close: c}), do: {o, h, l, c}
  defp candle(_other), do: nil

  defp nested_series(first, data) do
    cond do
      Enum.any?(first, &point?/1) -> Enum.map(data, &points/1)
      Enum.all?(first, &is_number/1) -> Enum.map(data, &indexed_points/1)
      true -> []
    end
  end

  defp indexed_points(values) do
    values
    |> Enum.filter(&is_number/1)
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> {index, value} end)
  end

  defp point?([x, y | _]) when is_number(x) and is_number(y), do: true
  defp point?(%{x: x, y: y}) when is_number(x) and is_number(y), do: true
  defp point?({x, y}) when is_number(x) and is_number(y), do: true
  defp point?({x, y, _w}) when is_number(x) and is_number(y), do: true
  defp point?(_other), do: false
end
