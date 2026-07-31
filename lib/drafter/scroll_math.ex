defmodule Drafter.ScrollMath do
  @moduledoc """
  Scroll offset and viewport calculations for list-like widgets.

  ## Examples

      iex> Drafter.ScrollMath.clamp(50, 10, 4)
      6

      iex> Drafter.ScrollMath.ensure_visible(0, 7, 5)
      3

      iex> Drafter.ScrollMath.end_anchored_slice([1, 2, 3, 4, 5], 0, 3)
      {2, [3, 4, 5]}

  """

  @doc """
  Returns `{start_index, slice}` for the visible portion of `data`.

  Anchors the viewport to the *end* of the data and scrolls left from there,
  matching the chart/timeline convention where new data arrives at the right.
  """
  @spec end_anchored_slice(list() | tuple(), non_neg_integer(), pos_integer()) ::
          {non_neg_integer(), list()}
  def end_anchored_slice(data, scroll_offset, viewport_size) when is_list(data) do
    total = length(data)
    {start, len} = end_anchored_range(total, scroll_offset, viewport_size)
    {start, Enum.slice(data, start, len)}
  end

  def end_anchored_slice(data, scroll_offset, viewport_size) when is_tuple(data) do
    total = tuple_size(data)
    {start, len} = end_anchored_range(total, scroll_offset, viewport_size)
    slice = for i <- start..(start + len - 1), i < total, do: elem(data, i)
    {start, slice}
  end

  @doc """
  Returns the adjusted scroll offset that keeps `target_index` visible within
  a viewport of `viewport_size` rows starting at the current `scroll_offset`.
  """
  @spec ensure_visible(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          non_neg_integer()
  def ensure_visible(scroll_offset, target_index, viewport_size) do
    cond do
      target_index < scroll_offset ->
        target_index

      target_index >= scroll_offset + viewport_size ->
        max(0, target_index - viewport_size + 1)

      true ->
        scroll_offset
    end
  end

  @doc """
  Clamps `offset` so it never exceeds `max(0, content_size - viewport_size)`.
  """
  @spec clamp(integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def clamp(offset, content_size, viewport_size) do
    max_offset = max(0, content_size - viewport_size)
    offset |> max(0) |> min(max_offset)
  end

  @doc """
  Converts a drag ratio (0.0–1.0) to a clamped scroll offset.
  """
  @spec from_ratio(float(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def from_ratio(ratio, content_size, viewport_size) do
    max_offset = max(0, content_size - viewport_size)
    round(ratio * max_offset) |> max(0) |> min(max_offset)
  end

  defp end_anchored_range(total, scroll_offset, viewport_size) do
    end_index = total - scroll_offset
    start_index = max(0, end_index - viewport_size)
    len = max(0, end_index - start_index)
    {start_index, len}
  end
end
