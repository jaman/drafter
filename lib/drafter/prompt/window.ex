defmodule Drafter.Prompt.Window do
  @moduledoc false

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.Style

  @doc """
  The positions of a list of `count` rows to show when `limit` rows fit and the row at
  `position` must be among them. The window keeps `position` near its middle.

      iex> Drafter.Prompt.Window.range(3, 0, 7)
      0..2//1

      iex> Drafter.Prompt.Window.range(20, 10, 7)
      7..13//1

      iex> Drafter.Prompt.Window.range(20, 19, 7)
      13..19//1
  """
  @spec range(non_neg_integer(), non_neg_integer(), pos_integer()) :: Range.t()
  def range(count, _position, limit) when count <= limit, do: 0..(count - 1)//1

  def range(count, position, limit) do
    first = (position - div(limit, 2)) |> max(0) |> min(count - limit)
    first..(first + limit - 1)//1
  end

  @doc "The line that says which rows of a longer list are shown, or no line when all are."
  @spec footer(Range.t(), non_neg_integer(), Style.t()) :: [Strip.t()]
  def footer(first..last//1, count, _style) when last - first + 1 >= count, do: []

  def footer(first..last//1, count, style),
    do: [Strip.new([Style.segment(style, :muted, "  #{first + 1}-#{last + 1} of #{count}")])]
end
