defmodule Drafter.Widget.Chart.Shared do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}

  def empty_strips(height, bg) do
    for _ <- 1..height do
      Strip.new([Segment.new("", %{bg: bg})])
    end
  end

  def normalize_data(data, min_val, range, pixel_height) do
    data
    |> Enum.map(fn value ->
      normalized = (value - min_val) / range

      round(normalized * pixel_height)
      |> min(pixel_height - 1)
      |> max(0)
    end)
  end

  def tuple_size_or_length(tuple) when is_tuple(tuple), do: tuple_size(tuple)
  def tuple_size_or_length(list), do: length(list)
end
