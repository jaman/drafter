defmodule Drafter.Render.RowDamage do
  @moduledoc """
  Which cells of a terminal row changed since it was last written, as runs to rewrite
  instead of the whole row.

      Drafter.Render.RowDamage.runs(previous_strip, strip)
      #=> [{4, 3}, {40, 12}]

  A run is `{first_column, width}`. Runs closer than `:gap` columns apart (default `4`)
  are joined, since rewriting a few unchanged cells costs less than moving the cursor
  again. Where the runs would cover more than `:whole` of the row (default `0.6`), or the
  two rows differ in width, the answer is `:whole` and the row is written as it is. A
  wide character is never split: a run that would start or end inside one takes all of
  it.
  """

  alias Drafter.CharacterWidth
  alias Drafter.Draw.Strip

  @type run :: {non_neg_integer(), pos_integer()}

  @doc "The runs that changed from `previous` to `current`, `[]` when none did, or `:whole`."
  @spec runs(Strip.t(), Strip.t(), keyword()) :: [run()] | :whole
  def runs(previous, current, opts \\ [])

  def runs(%Strip{width: width} = previous, %Strip{width: width} = current, opts) do
    gap = Keyword.get(opts, :gap, 4)
    whole = Keyword.get(opts, :whole, 0.6)
    before = cells(previous)
    now = cells(current)

    runs =
      before
      |> Enum.zip(now)
      |> Enum.with_index()
      |> Enum.reject(fn {{a, b}, _column} -> a == b end)
      |> Enum.map(&elem(&1, 1))
      |> join(gap)
      |> Enum.map(&widen(&1, List.to_tuple(now)))
      |> merge()

    if Enum.sum(Enum.map(runs, &elem(&1, 1))) > whole * max(width, 1), do: :whole, else: runs
  end

  def runs(_previous, _current, _opts), do: :whole

  defp cells(%Strip{segments: segments}) do
    Enum.flat_map(segments, fn segment ->
      segment.text |> String.graphemes() |> Enum.flat_map(&cell(&1, segment.style))
    end)
  end

  defp cell(grapheme, style) do
    case CharacterWidth.grapheme(grapheme) do
      0 -> []
      1 -> [{grapheme, style}]
      wide -> [{grapheme, style} | List.duplicate(:continued, wide - 1)]
    end
  end

  defp join([], _gap), do: []

  defp join([first | rest], gap) do
    {runs, current} =
      Enum.reduce(rest, {[], {first, first}}, fn column, {runs, {start, last}} ->
        if column - last <= gap,
          do: {runs, {start, column}},
          else: {[{start, last} | runs], {column, column}}
      end)

    Enum.reverse([current | runs])
  end

  defp widen({start, last}, cells) do
    start = back_to_char(cells, start)
    last = forward_to_end(cells, last)
    {start, last - start + 1}
  end

  defp back_to_char(cells, column) when column > 0 do
    if elem(cells, column) == :continued, do: back_to_char(cells, column - 1), else: column
  end

  defp back_to_char(_cells, column), do: column

  defp forward_to_end(cells, column) do
    if column + 1 < tuple_size(cells) and elem(cells, column + 1) == :continued,
      do: forward_to_end(cells, column + 1),
      else: column
  end

  defp merge(runs) do
    runs
    |> Enum.reduce([], fn
      {start, width}, [{previous, previous_width} | rest]
      when start <= previous + previous_width ->
        [{previous, max(previous_width, start + width - previous)} | rest]

      run, acc ->
        [run | acc]
    end)
    |> Enum.reverse()
  end
end
