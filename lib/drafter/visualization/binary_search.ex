defmodule Drafter.Visualization.BinarySearch do
  @moduledoc """
  Binary search utilities for sorted numeric data.

  Provides O(log n) range lookups on sorted lists, useful for viewport
  slicing in scroll-based widgets.
  """

  @doc """
  Returns `{start_index, end_index}` for the range of elements within
  `[min_val, max_val]` in a sorted numeric list.

  Uses binary search for O(log n) performance. Returns `{0, -1}` when
  no elements fall within the range or the list is empty.
  """
  @spec find_range([number()], number(), number()) :: {integer(), integer()}
  def find_range([], _min_val, _max_val), do: {0, -1}

  def find_range(_sorted_list, min_val, max_val) when min_val > max_val, do: {0, -1}

  def find_range(sorted_list, min_val, max_val) do
    arr = :array.from_list(sorted_list)
    size = :array.size(arr)

    start_idx = lower_bound(arr, size, min_val)
    end_idx = upper_bound(arr, size, max_val)

    if start_idx > end_idx do
      {0, -1}
    else
      {start_idx, end_idx}
    end
  end

  defp lower_bound(_arr, 0, _target), do: 0

  defp lower_bound(arr, size, target) do
    do_lower_bound(arr, 0, size - 1, target)
  end

  defp do_lower_bound(_arr, low, high, _target) when low > high, do: low

  defp do_lower_bound(arr, low, high, target) do
    mid = div(low + high, 2)
    val = :array.get(mid, arr)

    if val < target do
      do_lower_bound(arr, mid + 1, high, target)
    else
      do_lower_bound(arr, low, mid - 1, target)
    end
  end

  defp upper_bound(_arr, 0, _target), do: -1

  defp upper_bound(arr, size, target) do
    do_upper_bound(arr, 0, size - 1, target)
  end

  defp do_upper_bound(_arr, low, high, _target) when low > high, do: high

  defp do_upper_bound(arr, low, high, target) do
    mid = div(low + high, 2)
    val = :array.get(mid, arr)

    if val > target do
      do_upper_bound(arr, low, mid - 1, target)
    else
      do_upper_bound(arr, mid + 1, high, target)
    end
  end
end
