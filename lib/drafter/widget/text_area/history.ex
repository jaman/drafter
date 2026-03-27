defmodule Drafter.Widget.TextArea.History do
  @moduledoc false

  alias Drafter.Widget.TextArea.Cursor

  @spec snapshot(map()) :: {[String.t()], non_neg_integer(), non_neg_integer()}
  def snapshot(state), do: {state.lines, state.cursor_line, state.cursor_col}

  @spec push_undo(map()) :: map()
  def push_undo(state) do
    snap = snapshot(state)
    trimmed = Enum.take([snap | state.undo_stack], state.max_checkpoints)
    %{state | undo_stack: trimmed, redo_stack: []}
  end

  @spec handle_undo(map()) :: {:ok, map()}
  def handle_undo(state) do
    case state.undo_stack do
      [] ->
        {:ok, state}

      [prev | rest] ->
        current_snap = snapshot(state)
        {prev_lines, prev_row, prev_col} = prev

        new_state =
          %{
            state
            | lines: prev_lines,
              cursor_line: prev_row,
              cursor_col: prev_col,
              text: Enum.join(prev_lines, "\n"),
              undo_stack: rest,
              redo_stack: [current_snap | state.redo_stack],
              selection: nil
          }
          |> Cursor.adjust_scroll()

        {:ok, new_state}
    end
  end

  @spec handle_redo(map()) :: {:ok, map()}
  def handle_redo(state) do
    case state.redo_stack do
      [] ->
        {:ok, state}

      [next | rest] ->
        current_snap = snapshot(state)
        {next_lines, next_row, next_col} = next

        new_state =
          %{
            state
            | lines: next_lines,
              cursor_line: next_row,
              cursor_col: next_col,
              text: Enum.join(next_lines, "\n"),
              redo_stack: rest,
              undo_stack: [current_snap | state.undo_stack],
              selection: nil
          }
          |> Cursor.adjust_scroll()

        {:ok, new_state}
    end
  end
end
