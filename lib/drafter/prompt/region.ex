defmodule Drafter.Prompt.Region do
  @moduledoc """
  Redraws a few lines in place below the shell prompt, without the alternate screen.

  A region remembers how many lines it last drew and which of them holds the terminal
  cursor. Every function returns the bytes to write and the region to keep; nothing
  here writes to a terminal.

      {bytes, region} = Drafter.Prompt.Region.draw(%Drafter.Prompt.Region{}, frame, {80, 24})
      {bytes, region} = Drafter.Prompt.Region.leave(region)

  The cursor must be at the start of an empty line before the first `draw/3`. Lines
  are cut to one column less than the terminal's width and the frame to one line less
  than its height, so a frame never wraps or scrolls past the top of the screen.
  Every line break written is `\\r\\n`.
  """

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.Frame
  alias Drafter.Terminal.ANSI

  defstruct cursor_row: 0, height: 0

  @type t :: %__MODULE__{cursor_row: non_neg_integer(), height: non_neg_integer()}
  @type size :: {pos_integer(), pos_integer()}

  @doc """
  Draw `frame` over whatever the region drew last.

  Lines left over from a taller previous frame are erased. The cursor is shown at the
  frame's cursor position, or hidden at the end of the last line when the frame has
  none.
  """
  @spec draw(t(), Frame.t(), size()) :: {iodata(), t()}
  def draw(%__MODULE__{} = region, %Frame{} = frame, {cols, rows}) do
    width = max(cols - 1, 1)
    lines = frame.lines |> Enum.take(max(rows - 1, 1)) |> at_least_one_line()
    count = length(lines)

    body =
      lines
      |> Enum.map(&[&1 |> Strip.crop(width) |> Strip.to_ansi(), "\e[K"])
      |> Enum.intersperse("\r\n")

    {row, placement} = place(frame.cursor, count, width)

    bytes = [
      ANSI.sync_start(),
      ANSI.hide_cursor(),
      up(region.cursor_row),
      "\r",
      body,
      ANSI.clear_to_end(),
      placement,
      ANSI.sync_end()
    ]

    {bytes, %__MODULE__{cursor_row: row, height: count}}
  end

  @doc """
  Move the cursor to the start of the line below the frame and show it.

  The frame stays on screen. The returned region is empty, so the next `draw/3` starts
  a new frame there.
  """
  @spec leave(t()) :: {iodata(), t()}
  def leave(%__MODULE__{height: 0}), do: {ANSI.show_cursor(), %__MODULE__{}}

  def leave(%__MODULE__{} = region) do
    {[down(region.height - 1 - region.cursor_row), "\r\n", ANSI.show_cursor()], %__MODULE__{}}
  end

  @doc """
  Erase the frame and leave the cursor where its first line was.

  The returned region is empty.
  """
  @spec clear(t()) :: {iodata(), t()}
  def clear(%__MODULE__{} = region) do
    {[up(region.cursor_row), "\r", ANSI.clear_to_end()], %__MODULE__{}}
  end

  defp at_least_one_line([]), do: [Strip.empty()]
  defp at_least_one_line(lines), do: lines

  defp place(nil, count, _width), do: {count - 1, []}

  defp place({row, column}, count, width) when is_integer(column) and is_integer(width) do
    row = min(row, count - 1)
    {row, [up(count - 1 - row), "\r", right(min(column, width)), ANSI.show_cursor()]}
  end

  defp up(0), do: []
  defp up(lines), do: "\e[#{lines}A"

  defp down(0), do: []
  defp down(lines), do: "\e[#{lines}B"

  defp right(0), do: []
  defp right(columns), do: "\e[#{columns}C"
end
