defmodule Drafter.Widget.TextArea.History do
  @moduledoc false

  alias Drafter.Widget.TextArea.Cursor

  @spec snapshot(map()) :: {[String.t()], non_neg_integer(), non_neg_integer()}
  def snapshot(state), do: {state.lines, state.cursor_line, state.cursor_col}

  @spec push_undo(map()) :: map()
  def push_undo(state) do
    snap = snapshot(state)
    trimmed = Enum.take([snap | state.history.undo], state.max_checkpoints)
    %{state | history: %{undo: trimmed, redo: []}}
  end

  @spec handle_undo(map()) :: {:ok, map()}
  def handle_undo(state) do
    case state.history.undo do
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
              history: %{undo: rest, redo: [current_snap | state.history.redo]},
              selection: nil
          }
          |> Cursor.adjust_scroll()

        {:ok, new_state}
    end
  end

  @spec handle_redo(map()) :: {:ok, map()}
  def handle_redo(state) do
    case state.history.redo do
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
              history: %{undo: [current_snap | state.history.undo], redo: rest},
              selection: nil
          }
          |> Cursor.adjust_scroll()

        {:ok, new_state}
    end
  end
end
