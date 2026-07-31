defmodule Drafter.Widget.TextArea.Clipboard do
  @moduledoc false

  alias Drafter.Widget.TextArea.{Cursor, History, Selection}

  @spec copy_selection(map()) :: :ok
  def copy_selection(state) do
    text = Selection.selected_text(state)
    if text != "", do: clipboard_copy(text)
    :ok
  end

  @spec handle_cut(map()) :: {:ok, map()}
  def handle_cut(state) do
    if state.selection == nil or state.read_only do
      {:ok, state}
    else
      copy_selection(state)
      new_state = History.push_undo(state) |> Selection.delete_selection()
      {:ok, new_state}
    end
  end

  @spec handle_paste(map()) :: {:ok, map()}
  def handle_paste(state) do
    text = clipboard_paste()

    if text == "" do
      {:ok, state}
    else
      state = History.push_undo(state)
      state = if state.selection != nil, do: Selection.delete_selection(state), else: state

      pasted_lines = String.split(text, "\n")
      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)

      new_lines =
        case pasted_lines do
          [single] ->
            new_line = before <> single <> after_text
            List.replace_at(state.lines, state.cursor_line, new_line)

          [first | rest] ->
            last = List.last(rest)
            middle = Enum.slice(rest, 0, length(rest) - 1)
            first_line = before <> first
            last_line = last <> after_text

            lines_before = Enum.slice(state.lines, 0, state.cursor_line)
            lines_after = Enum.slice(state.lines, state.cursor_line + 1, length(state.lines))

            lines_before ++ [first_line] ++ middle ++ [last_line] ++ lines_after
        end

      new_cursor_line = state.cursor_line + length(pasted_lines) - 1
      last_pasted = List.last(pasted_lines)

      new_cursor_col =
        if length(pasted_lines) == 1 do
          state.cursor_col + String.length(last_pasted)
        else
          String.length(last_pasted)
        end

      new_state =
        %{
          state
          | lines: new_lines,
            cursor_line: new_cursor_line,
            cursor_col: new_cursor_col,
            text: Enum.join(new_lines, "\n")
        }
        |> Cursor.adjust_scroll()

      {:ok, new_state}
    end
  end

  @spec clipboard_copy(String.t()) :: :ok
  def clipboard_copy(text) do
    Drafter.Clipboard.copy(text)
    :ok
  end

  @spec clipboard_paste() :: String.t()
  def clipboard_paste do
    case Drafter.Clipboard.paste() do
      {:ok, text} -> text
      {:error, _reason} -> ""
    end
  end
end
