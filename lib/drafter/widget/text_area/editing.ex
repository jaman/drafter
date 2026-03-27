defmodule Drafter.Widget.TextArea.Editing do
  @moduledoc false

  alias Drafter.Widget.TextArea.{Cursor, History, Selection}

  @spec handle_backspace(map()) :: {:ok, map()} | {:noreply, map()}
  def handle_backspace(state) do
    if state.selection != nil do
      {:ok, History.push_undo(state) |> Selection.delete_selection()}
    else
      if state.read_only do
        {:noreply, state}
      else
        do_backspace(state)
      end
    end
  end

  @spec do_backspace(map()) :: {:ok, map()}
  def do_backspace(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    state = History.push_undo(state)

    cond do
      state.cursor_col > 0 ->
        {before, after_text} = String.split_at(current_line, state.cursor_col)
        new_line_content = String.slice(before, 0..-2//1) <> after_text
        new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

        new_state = %{
          state
          | lines: new_lines,
            cursor_col: state.cursor_col - 1,
            text: Enum.join(new_lines, "\n")
        }

        {:ok, new_state}

      state.cursor_line > 0 ->
        prev_line = Enum.at(state.lines, state.cursor_line - 1, "")
        joined_line = prev_line <> current_line

        new_lines =
          state.lines
          |> List.replace_at(state.cursor_line - 1, joined_line)
          |> List.delete_at(state.cursor_line)

        new_state =
          %{
            state
            | lines: new_lines,
              cursor_line: state.cursor_line - 1,
              cursor_col: String.length(prev_line),
              text: Enum.join(new_lines, "\n")
          }
          |> Cursor.adjust_scroll()

        {:ok, new_state}

      true ->
        {:ok, state}
    end
  end

  @spec handle_delete(map()) :: {:ok, map()} | {:noreply, map()}
  def handle_delete(state) do
    if state.selection != nil do
      {:ok, History.push_undo(state) |> Selection.delete_selection()}
    else
      if state.read_only do
        {:noreply, state}
      else
        do_delete(state)
      end
    end
  end

  @spec do_delete(map()) :: {:ok, map()}
  def do_delete(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    state = History.push_undo(state)

    cond do
      state.cursor_col < String.length(current_line) ->
        {before, after_text} = String.split_at(current_line, state.cursor_col)
        new_line_content = before <> String.slice(after_text, 1..-1//1)
        new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

        new_state = %{state | lines: new_lines, text: Enum.join(new_lines, "\n")}

        {:ok, new_state}

      state.cursor_line < length(state.lines) - 1 ->
        next_line = Enum.at(state.lines, state.cursor_line + 1, "")
        joined_line = current_line <> next_line

        new_lines =
          state.lines
          |> List.replace_at(state.cursor_line, joined_line)
          |> List.delete_at(state.cursor_line + 1)

        new_state = %{state | lines: new_lines, text: Enum.join(new_lines, "\n")}

        {:ok, new_state}

      true ->
        {:ok, state}
    end
  end

  @spec handle_enter(map()) :: {:ok, map()} | {:noreply, map()}
  def handle_enter(state) do
    if state.read_only do
      {:noreply, state}
    else
      state =
        if state.selection != nil,
          do: state |> History.push_undo() |> Selection.delete_selection(),
          else: History.push_undo(state)
      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)

      new_lines =
        state.lines
        |> List.replace_at(state.cursor_line, before)
        |> List.insert_at(state.cursor_line + 1, after_text)

      new_state =
        %{
          state
          | lines: new_lines,
            cursor_line: state.cursor_line + 1,
            cursor_col: 0,
            text: Enum.join(new_lines, "\n")
        }
        |> Cursor.adjust_scroll()

      {:ok, new_state}
    end
  end

  @spec handle_tab_indent(map()) :: {:ok, map()} | {:noreply, map()}
  def handle_tab_indent(state) do
    if state.read_only do
      {:noreply, state}
    else
      spaces = String.duplicate(" ", state.tab_size)
      state = History.push_undo(state)
      state = if state.selection != nil, do: Selection.delete_selection(state), else: state

      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)
      new_line_content = before <> spaces <> after_text
      new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

      new_state = %{
        state
        | lines: new_lines,
          cursor_col: state.cursor_col + state.tab_size,
          text: Enum.join(new_lines, "\n")
      }

      {:ok, new_state}
    end
  end

  @spec handle_char_input(map(), String.t()) :: {:ok, map()} | {:noreply, map()}
  def handle_char_input(state, char_str) do
    if state.read_only do
      {:noreply, state}
    else
      state = History.push_undo(state)
      state = if state.selection != nil, do: Selection.delete_selection(state), else: state
      insert_char(state, char_str)
    end
  end

  @spec insert_char(map(), String.t()) :: {:ok, map()}
  def insert_char(state, char) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    {before, after_text} = String.split_at(current_line, state.cursor_col)
    new_line_content = before <> char <> after_text

    new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

    new_state = %{
      state
      | lines: new_lines,
        cursor_col: state.cursor_col + 1,
        text: Enum.join(new_lines, "\n")
    }

    {:ok, new_state}
  end

  @spec can_insert_char?(map()) :: boolean()
  def can_insert_char?(state) do
    case state.max_lines do
      nil -> true
      max_lines -> length(state.lines) < max_lines
    end
  end

  @spec printable_char?(String.t()) :: boolean()
  def printable_char?(char) do
    String.length(char) == 1 and String.printable?(char) and char not in ["\t", "\r"]
  end
end
