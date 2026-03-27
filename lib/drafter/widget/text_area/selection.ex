defmodule Drafter.Widget.TextArea.Selection do
  @moduledoc false

  alias Drafter.Widget.TextArea.Cursor

  @spec normalize_selection({non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def normalize_selection({anchor_row, anchor_col, active_row, active_col}) do
    if {anchor_row, anchor_col} <= {active_row, active_col} do
      {anchor_row, anchor_col, active_row, active_col}
    else
      {active_row, active_col, anchor_row, anchor_col}
    end
  end

  @spec clear_selection(map()) :: map()
  def clear_selection(state), do: %{state | selection: nil}

  @spec select_all(map()) :: map()
  def select_all(state) do
    last_line = length(state.lines) - 1
    last_col = String.length(Enum.at(state.lines, last_line, ""))

    %{state | selection: {0, 0, last_line, last_col}, cursor_line: last_line, cursor_col: last_col}
  end

  @spec extend_selection(map(), :up | :down | :left | :right) :: map()
  def extend_selection(state, direction) do
    anchor =
      case state.selection do
        nil -> {state.cursor_line, state.cursor_col}
        {ar, ac, _, _} -> {ar, ac}
      end

    moved_state = Cursor.apply_cursor_move(state, direction)
    {anchor_row, anchor_col} = anchor

    %{moved_state
      | selection: {anchor_row, anchor_col, moved_state.cursor_line, moved_state.cursor_col}}
  end

  @spec selected_text(map()) :: String.t()
  def selected_text(state) do
    case state.selection do
      nil ->
        ""

      selection ->
        {start_row, start_col, end_row, end_col} = normalize_selection(selection)

        if start_row == end_row do
          line = Enum.at(state.lines, start_row, "")
          String.slice(line, start_col, end_col - start_col)
        else
          first_line = Enum.at(state.lines, start_row, "")
          last_line = Enum.at(state.lines, end_row, "")
          first_part = String.slice(first_line, start_col, String.length(first_line) - start_col)
          last_part = String.slice(last_line, 0, end_col)

          middle_lines =
            state.lines
            |> Enum.slice(start_row + 1, end_row - start_row - 1)

          ([first_part] ++ middle_lines ++ [last_part]) |> Enum.join("\n")
        end
    end
  end

  @spec delete_selection(map()) :: map()
  def delete_selection(state) do
    {start_row, start_col, end_row, end_col} = normalize_selection(state.selection)

    start_line = Enum.at(state.lines, start_row, "")
    end_line = Enum.at(state.lines, end_row, "")

    before_text = String.slice(start_line, 0, start_col)
    after_text = String.slice(end_line, end_col, String.length(end_line) - end_col)

    merged_line = before_text <> after_text

    lines_before = Enum.slice(state.lines, 0, start_row)
    lines_after = Enum.slice(state.lines, end_row + 1, length(state.lines))

    new_lines = lines_before ++ [merged_line] ++ lines_after

    %{
      state
      | lines: new_lines,
        cursor_line: start_row,
        cursor_col: start_col,
        selection: nil,
        text: Enum.join(new_lines, "\n")
    }
    |> Cursor.adjust_scroll()
  end
end
