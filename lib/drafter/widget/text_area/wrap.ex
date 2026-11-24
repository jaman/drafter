defmodule Drafter.Widget.TextArea.Wrap do
  @moduledoc """
  The rows a `Drafter.Widget.TextArea` with `wrap: :word` draws its lines in,
  and the mapping between a cursor position and a row.

  A row is `{line, start, stop}`: columns `start..stop - 1` of line `line`.
  A line no wider than the wrap width is one row. A longer line breaks after
  the last space that fits, the space staying at the end of its row, or at
  the wrap width when the row has no space; an empty line is one empty row.

      iex> Drafter.Widget.TextArea.Wrap.rows(["one two three", ""], 6)
      [{0, 0, 4}, {0, 4, 8}, {0, 8, 13}, {1, 0, 0}]
  """

  alias Drafter.Widget.TextArea

  @type row :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  The rows `lines` are drawn in within a content area of `width` columns and
  `height` rows, and the columns left for text: one column is kept for the
  cursor after a full row, and one more for the scrollbar when the rows
  outnumber `height`.
  """
  @spec layout([String.t()], pos_integer(), pos_integer()) :: {[row()], pos_integer()}
  def layout(lines, width, height) do
    rows = rows(lines, max(1, width - 1))

    if length(rows) > height,
      do: {rows(lines, max(1, width - 2)), max(1, width - 1)},
      else: {rows, width}
  end

  @doc """
  The `layout/3` of a `Drafter.Widget.TextArea` state: its lines in the
  content area its `:width`, `:height`, border and gutter leave.
  """
  @spec state_layout(map()) :: {[row()], pos_integer()}
  def state_layout(state) do
    chrome = TextArea.chrome(state)

    layout(
      state.lines,
      max(1, state.width - 2 * chrome - state.gutter_width),
      max(1, state.height - 2 * chrome)
    )
  end

  @doc "The rows of `lines` at `width` columns, in order."
  @spec rows([String.t()], pos_integer()) :: [row()]
  def rows(lines, width) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      line |> breaks(width) |> Enum.map(fn {start, stop} -> {index, start, stop} end)
    end)
  end

  @doc """
  The row index and the column within it of the cursor at `line`, `col`.
  A column at a break belongs to the row it starts; the end of a line to its
  last row.

      iex> rows = Drafter.Widget.TextArea.Wrap.rows(["one two three"], 6)
      iex> Drafter.Widget.TextArea.Wrap.position(rows, 0, 4)
      {1, 0}
      iex> Drafter.Widget.TextArea.Wrap.position(rows, 0, 13)
      {2, 5}
  """
  @spec position([row()], non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def position(rows, line, col) do
    rows
    |> Enum.with_index()
    |> Enum.filter(fn {{row_line, start, _stop}, _index} -> row_line == line and start <= col end)
    |> List.last()
    |> case do
      {{_line, start, _stop}, index} -> {index, col - start}
      nil -> {0, 0}
    end
  end

  @doc """
  The cursor position of column `column` in row `index`: the column is
  clamped to the row, before its last character on a row the line continues
  after, so that the cursor stays on that row.

      iex> rows = Drafter.Widget.TextArea.Wrap.rows(["one two three"], 6)
      iex> Drafter.Widget.TextArea.Wrap.at(rows, 0, 9)
      {0, 3}
      iex> Drafter.Widget.TextArea.Wrap.at(rows, 2, 9)
      {0, 13}
  """
  @spec at([row()], non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def at(rows, index, column) do
    {line, start, stop} = Enum.at(rows, index)
    continues? = match?({^line, _start, _stop}, Enum.at(rows, index + 1))
    last = if continues? and stop > start, do: stop - 1, else: stop
    {line, min(start + column, last)}
  end

  defp breaks(line, width) do
    length = String.length(line)
    if length <= width, do: [{0, length}], else: split(line, 0, length, width, [])
  end

  defp split(_line, start, length, width, acc) when length - start <= width,
    do: Enum.reverse([{start, length} | acc])

  defp split(line, start, length, width, acc) do
    stop = break_at(String.slice(line, start, width), start, width)
    split(line, stop, length, width, [{start, stop} | acc])
  end

  defp break_at(window, start, width) do
    case last_space(window) do
      nil -> start + width
      index -> start + index + 1
    end
  end

  defp last_space(window) do
    window
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {char, _index} -> char == " " end)
    |> List.last()
    |> case do
      {_space, index} -> index
      nil -> nil
    end
  end
end
