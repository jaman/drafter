defmodule Drafter.Visualization.Reduce do
  @moduledoc """
  Reduces long series to the number of columns a plot can show, keeping peaks.

  Items are split into `columns` buckets of consecutive items, in order. Each
  function decides what a bucket keeps:

    * `peaks/3` — one item per bucket, the one furthest from zero
    * `min_max/3` — the smallest and largest item per bucket, in their original order
    * `m4/2` — first, smallest, largest and last `{x, y}` point per bucket, in x order

  Items come back unchanged, so tuples such as `{value, weight}` survive when a
  `value_fun` extracts the number. Lists no longer than `columns` are returned as-is.

  A `nil` item is a gap and is never passed to `value_fun`. A bucket holding only
  gaps keeps a gap in place of its items; otherwise its gaps are ignored.
  """

  @type value_fun :: (term() -> number())

  @doc """
  Keeps one item per bucket: the one whose value has the largest magnitude.

  Returns at most `columns` items.

  ## Examples

      iex> Drafter.Visualization.Reduce.peaks([1, 9, 2, 3, -7, 1], 3)
      [9, 3, -7]

      iex> Drafter.Visualization.Reduce.peaks([{1, 0.5}, {4, 1.0}], 1, &elem(&1, 0))
      [{4, 1.0}]

      iex> Drafter.Visualization.Reduce.peaks([nil, nil, 3, nil], 2)
      [nil, 3]

  """
  @spec peaks([term()], pos_integer(), value_fun()) :: [term()]
  def peaks(items, columns, value_fun \\ & &1) do
    reduce_buckets(items, columns, fn
      [] -> [nil]
      bucket -> [Enum.max_by(bucket, &abs(value_fun.(&1)))]
    end)
  end

  @doc """
  Reduces several series at the same indices, so stacked layers stay aligned.

  Each index is a column of one item per series; the column kept per bucket is the
  one whose summed magnitude is largest. Series are cut to the length of the
  shortest. Returns one list per input series.

  ## Examples

      iex> Drafter.Visualization.Reduce.aligned_peaks([[1, 5, 1, 1], [1, 1, 1, 9]], 2)
      [[5, 1], [1, 9]]

  """
  @spec aligned_peaks([[term()]], pos_integer(), value_fun()) :: [[term()]]
  def aligned_peaks(series, columns, value_fun \\ & &1) do
    series
    |> Enum.zip_with(&List.to_tuple/1)
    |> peaks(columns, &column_magnitude(&1, value_fun))
    |> unzip_columns(length(series))
  end

  @doc """
  Keeps the smallest and the largest item per bucket, in their original order.

  Returns exactly `2 * columns` items when the list is longer than `columns`, so
  series reduced to the same `columns` line up index for index. A bucket whose
  minimum and maximum are the same item contributes it twice.

  ## Examples

      iex> Drafter.Visualization.Reduce.min_max([5, 1, 9, 2, 8, 3], 2)
      [1, 9, 2, 8]

      iex> Drafter.Visualization.Reduce.min_max([4, 4, 4], 1)
      [4, 4]

  """
  @spec min_max([term()], pos_integer(), value_fun()) :: [term()]
  def min_max(items, columns, value_fun \\ & &1) do
    reduce_buckets(items, columns, fn
      [] ->
        [nil, nil]

      bucket ->
        min_max_pair(bucket, value_fun)
    end)
  end

  defp min_max_pair(bucket, value_fun) do
    indexed = Enum.with_index(bucket)
    {low, low_index} = Enum.min_by(indexed, fn {item, _} -> value_fun.(item) end)
    {high, high_index} = Enum.max_by(indexed, fn {item, _} -> value_fun.(item) end)
    ordered_pair(low, low_index, high, high_index)
  end

  @doc """
  M4 reduction of `{x, y}` points: first, minimum, maximum and last per bucket.

  Points must be sorted by x. Returns at most `4 * columns` points, in x order,
  with duplicates within a bucket removed. A line drawn through the result covers
  the same pixels as a line through every input point at `columns` pixels wide.

  ## Examples

      iex> Drafter.Visualization.Reduce.m4([{0, 1}, {1, 7}, {2, 0}, {3, 4}], 1)
      [{0, 1}, {1, 7}, {2, 0}, {3, 4}]

      iex> Drafter.Visualization.Reduce.m4([{0, 1}, {1, 7}, {2, 0}, {3, 4}, {4, 2}, {5, 3}], 1)
      [{0, 1}, {1, 7}, {2, 0}, {5, 3}]

  """
  @spec m4([{number(), number()}], pos_integer()) :: [{number(), number()}]
  def m4(points, columns) when length(points) <= columns * 4, do: points

  def m4(points, columns) do
    {first_x, _} = hd(points)
    {last_x, _} = List.last(points)
    span = max(last_x - first_x, 1.0e-12)

    points
    |> Enum.chunk_by(fn {x, _} -> min(trunc((x - first_x) / span * columns), columns - 1) end)
    |> Enum.flat_map(&m4_bucket/1)
  end

  defp m4_bucket(bucket) do
    first = hd(bucket)
    last = List.last(bucket)
    low = Enum.min_by(bucket, &elem(&1, 1))
    high = Enum.max_by(bucket, &elem(&1, 1))

    [first, low, high, last]
    |> Enum.uniq()
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp reduce_buckets(items, columns, keep) do
    count = length(items)

    if count <= columns do
      items
    else
      items
      |> Stream.with_index()
      |> Stream.chunk_by(fn {_item, index} -> div(index * columns, count) end)
      |> Enum.flat_map(fn chunk ->
        chunk |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1) |> keep.()
      end)
    end
  end

  defp column_magnitude(column, value_fun) do
    column
    |> Tuple.to_list()
    |> Enum.reduce(0, fn
      nil, sum -> sum
      item, sum -> sum + abs(value_fun.(item))
    end)
  end

  defp unzip_columns([], series_count), do: List.duplicate([], series_count)

  defp unzip_columns(columns, _series_count),
    do: Enum.zip_with(Enum.map(columns, &Tuple.to_list/1), & &1)

  defp ordered_pair(low, low_index, high, high_index) when low_index <= high_index,
    do: [low, high]

  defp ordered_pair(low, _low_index, high, _high_index), do: [high, low]
end
