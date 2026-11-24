defmodule Drafter.Widget.TextArea.Cursor do
  @moduledoc false

  alias Drafter.Widget.TextArea
  alias Drafter.Widget.TextArea.Wrap

  @spec move_row(map(), integer()) :: map()
  def move_row(state, delta) do
    {rows, _width} = Wrap.state_layout(state)
    {row, column} = Wrap.position(rows, state.cursor_line, state.cursor_col)
    target = min(max(row + delta, 0), length(rows) - 1)

    if target == row do
      state
    else
      {line, col} = Wrap.at(rows, target, column)
      %{state | cursor_line: line, cursor_col: col}
    end
  end

  @spec at_edge?(map(), :up | :down) :: boolean()
  def at_edge?(%{appearance: %{wrap: :word}} = state, direction) do
    {rows, _width} = Wrap.state_layout(state)
    {row, _column} = Wrap.position(rows, state.cursor_line, state.cursor_col)
    if direction == :up, do: row == 0, else: row == length(rows) - 1
  end

  def at_edge?(state, :up), do: state.cursor_line == 0
  def at_edge?(state, :down), do: state.cursor_line >= length(state.lines) - 1

  @spec move_up(map()) :: map()
  def move_up(%{appearance: %{wrap: :word}} = state), do: move_row(state, -1)

  def move_up(state) do
    if state.cursor_line > 0 do
      new_line = state.cursor_line - 1
      line_length = String.length(Enum.at(state.lines, new_line, ""))
      %{state | cursor_line: new_line, cursor_col: min(state.cursor_col, line_length)}
    else
      state
    end
  end

  @spec move_down(map()) :: map()
  def move_down(%{appearance: %{wrap: :word}} = state), do: move_row(state, 1)

  def move_down(state) do
    if state.cursor_line < length(state.lines) - 1 do
      new_line = state.cursor_line + 1
      line_length = String.length(Enum.at(state.lines, new_line, ""))
      %{state | cursor_line: new_line, cursor_col: min(state.cursor_col, line_length)}
    else
      state
    end
  end

  @spec move_left(map()) :: map()
  def move_left(state) do
    if state.cursor_col > 0 do
      %{state | cursor_col: state.cursor_col - 1}
    else
      if state.cursor_line > 0 do
        prev_line = Enum.at(state.lines, state.cursor_line - 1, "")
        %{state | cursor_line: state.cursor_line - 1, cursor_col: String.length(prev_line)}
      else
        state
      end
    end
  end

  @spec move_right(map()) :: map()
  def move_right(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")

    if state.cursor_col < String.length(current_line) do
      %{state | cursor_col: state.cursor_col + 1}
    else
      if state.cursor_line < length(state.lines) - 1 do
        %{state | cursor_line: state.cursor_line + 1, cursor_col: 0}
      else
        state
      end
    end
  end

  @spec word_left([String.t()], non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def word_left(lines, row, 0) when row > 0 do
    prev_line = Enum.at(lines, row - 1, "")
    {row - 1, String.length(prev_line)}
  end

  def word_left(_lines, row, 0), do: {row, 0}

  def word_left(lines, row, col) do
    line = Enum.at(lines, row, "")
    chars = line |> String.slice(0, col) |> String.graphemes() |> Enum.reverse()
    {skipped_word, remaining} = take_while_count(chars, &word_char?/1)
    {skipped_non_word, _} = take_while_count(remaining, &(not word_char?(&1)))
    new_col = col - skipped_word - skipped_non_word
    {row, max(0, new_col)}
  end

  @spec word_right([String.t()], non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def word_right(lines, row, col) do
    line = Enum.at(lines, row, "")
    line_len = String.length(line)

    if col >= line_len and row < length(lines) - 1 do
      {row + 1, 0}
    else
      chars = line |> String.slice(col, line_len - col) |> String.graphemes()
      {skipped_non_word, remaining} = take_while_count(chars, &(not word_char?(&1)))
      {skipped_word, _} = take_while_count(remaining, &word_char?/1)
      new_col = col + skipped_non_word + skipped_word
      {row, min(new_col, line_len)}
    end
  end

  @spec adjust_scroll(map()) :: map()
  def adjust_scroll(state) do
    state |> adjust_v_scroll() |> adjust_h_scroll()
  end

  defp adjust_v_scroll(state) do
    content_height = state.height - 2 * TextArea.chrome(state)
    row = cursor_row(state)

    cond do
      row < state.scroll_offset ->
        %{state | scroll_offset: row}

      row >= state.scroll_offset + content_height ->
        %{state | scroll_offset: row - content_height + 1}

      true ->
        state
    end
  end

  defp cursor_row(%{appearance: %{wrap: :word}} = state) do
    {rows, _width} = Wrap.state_layout(state)
    {row, _column} = Wrap.position(rows, state.cursor_line, state.cursor_col)
    row
  end

  defp cursor_row(state), do: state.cursor_line

  defp adjust_h_scroll(%{appearance: %{wrap: :word}} = state), do: %{state | h_scroll: 0}

  defp adjust_h_scroll(state) do
    content_width =
      max(1, state.width - 2 * TextArea.chrome(state) - state.gutter_width)

    h = state.h_scroll || 0

    cond do
      state.cursor_col < h ->
        %{state | h_scroll: state.cursor_col}

      state.cursor_col >= h + content_width ->
        %{state | h_scroll: state.cursor_col - content_width + 1}

      true ->
        %{state | h_scroll: h}
    end
  end

  @spec apply_cursor_move(map(), :up | :down | :left | :right) :: map()
  def apply_cursor_move(state, :up), do: state |> move_up() |> adjust_scroll()
  def apply_cursor_move(state, :down), do: state |> move_down() |> adjust_scroll()
  def apply_cursor_move(state, :left), do: state |> move_left() |> adjust_scroll()
  def apply_cursor_move(state, :right), do: state |> move_right() |> adjust_scroll()

  @spec take_while_count(list(), (term() -> boolean())) :: {non_neg_integer(), list()}
  def take_while_count(list, pred), do: take_while_count(list, pred, 0)

  @spec word_char?(String.t()) :: boolean()
  def word_char?(char), do: Regex.match?(~r/\w/, char)

  defp take_while_count([], _pred, count), do: {count, []}

  defp take_while_count([h | t], pred, count) do
    if pred.(h), do: take_while_count(t, pred, count + 1), else: {count, [h | t]}
  end
end
