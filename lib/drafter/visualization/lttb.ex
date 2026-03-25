defmodule Drafter.Visualization.LTTB do
  @moduledoc """
  Largest Triangle Three Buckets downsampling algorithm.

  Reduces a dataset to a target number of points while preserving the visual
  shape of the data. Operates in O(n) time with a single pass.
  """

  @doc """
  Downsamples a list of `{x, y}` tuples or `[x, y]` lists to `target_count` points.

  Always keeps the first and last points. For each intermediate bucket, selects
  the point that forms the largest triangle area with the previously selected
  point and the average of the next bucket.

  Returns points unchanged when `length(points) <= target_count`.
  """
  @spec downsample([{number(), number()} | [number()]], pos_integer()) ::
          [{number(), number()} | [number()]]
  def downsample(points, target_count) when length(points) <= target_count, do: points
  def downsample([], _target_count), do: []
  def downsample([point], _target_count), do: [point]

  def downsample(points, target_count) when target_count < 2, do: [hd(points)]

  def downsample(points, target_count) do
    total = length(points)
    bucket_size = (total - 2) / (target_count - 2)

    first = hd(points)
    last = List.last(points)

    indexed = :array.from_list(points)

    selected = do_downsample(indexed, total, bucket_size, target_count, 0, first, [first])

    Enum.reverse([last | selected])
  end

  defp do_downsample(_indexed, _total, _bucket_size, target_count, bucket_idx, _prev, acc)
       when bucket_idx >= target_count - 2 do
    acc
  end

  defp do_downsample(indexed, total, bucket_size, target_count, bucket_idx, prev_point, acc) do
    bucket_start = round(1 + bucket_idx * bucket_size)
    bucket_end = min(round(1 + (bucket_idx + 1) * bucket_size), total - 1)

    next_bucket_start = round(1 + (bucket_idx + 1) * bucket_size)
    next_bucket_end = min(round(1 + (bucket_idx + 2) * bucket_size), total - 1)

    {avg_x, avg_y} = bucket_average(indexed, next_bucket_start, next_bucket_end)

    {_x_a, _y_a} = extract_xy(prev_point)

    {best_point, _best_area} =
      Enum.reduce(bucket_start..(bucket_end - 1), {nil, -1}, fn idx, {best, best_area} ->
        point = :array.get(idx, indexed)
        {x_b, y_b} = extract_xy(point)
        {x_a, y_a} = extract_xy(prev_point)

        area = triangle_area(x_a, y_a, x_b, y_b, avg_x, avg_y)

        if area > best_area do
          {point, area}
        else
          {best, best_area}
        end
      end)

    selected = best_point || :array.get(bucket_start, indexed)

    do_downsample(indexed, total, bucket_size, target_count, bucket_idx + 1, selected, [
      selected | acc
    ])
  end

  defp bucket_average(indexed, start_idx, end_idx) when start_idx >= end_idx do
    point = :array.get(min(start_idx, :array.size(indexed) - 1), indexed)
    extract_xy(point)
  end

  defp bucket_average(indexed, start_idx, end_idx) do
    count = end_idx - start_idx

    {sum_x, sum_y} =
      Enum.reduce(start_idx..(end_idx - 1), {0, 0}, fn idx, {sx, sy} ->
        {x, y} = extract_xy(:array.get(idx, indexed))
        {sx + x, sy + y}
      end)

    {sum_x / count, sum_y / count}
  end

  defp triangle_area(x_a, y_a, x_b, y_b, x_c, y_c) do
    abs((x_a - x_c) * (y_b - y_a) - (x_a - x_b) * (y_c - y_a)) * 0.5
  end

  defp extract_xy({x, y}), do: {x, y}
  defp extract_xy([x, y | _]), do: {x, y}

  @doc """
  Downsamples a simple list of y-values to `target_count` points.

  Generates implicit x indices, applies LTTB downsampling, and returns
  only the y-values from the result.
  """
  @spec downsample_series([number()], pos_integer()) :: [number()]
  def downsample_series(values, target_count) when length(values) <= target_count, do: values
  def downsample_series([], _target_count), do: []

  def downsample_series(values, target_count) do
    points = values |> Enum.with_index() |> Enum.map(fn {y, x} -> {x, y} end)

    points
    |> downsample(target_count)
    |> Enum.map(fn {_x, y} -> y end)
  end
end
