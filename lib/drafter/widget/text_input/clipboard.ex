defmodule Drafter.Widget.TextInput.Clipboard do
  @moduledoc false

  alias Drafter.Widget.TextInput.{Rendering, Selection}

  @spec copy_selection(map()) :: :ok
  def copy_selection(state) do
    {sel_start, sel_end} = Selection.get_selection_range(state)
    selected_text = String.slice(state.text, sel_start, sel_end - sel_start)

    case :os.type() do
      {:unix, :darwin} ->
        escaped_text = String.replace(selected_text, "\"", "\\\"")
        System.cmd("osascript", ["-e", "set the clipboard to \"" <> escaped_text <> "\""])

      {:unix, _} ->
        try do
          if File.exists?("/tmp/.clipboard-unicode") do
            File.write!("/tmp/.clipboard-unicode", selected_text)
          end
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  @spec cut_selection(map()) :: map()
  def cut_selection(state) do
    copy_selection(state)
    {sel_start, sel_end} = Selection.get_selection_range(state)

    {before, _middle, after_text} =
      Selection.split_text_at_selection(state.text, sel_start, sel_end)

    new_text = before <> after_text

    %{
      state
      | text: new_text,
        cursor_position: sel_start,
        selection_start: nil,
        selection_end: nil
    }
    |> Rendering.adjust_scroll_offset()
  end

  @spec paste_from_clipboard(map()) :: map()
  def paste_from_clipboard(state) do
    clipboard_text =
      case :os.type() do
        {:unix, :darwin} ->
          {text, _} = System.cmd("pbpaste", [])
          String.trim(text)

        {:unix, _} ->
          case File.read("/tmp/.clipboard-unicode") do
            {:ok, text} -> text
            _ -> ""
          end

        _ ->
          ""
      end

    if Selection.has_selection?(state) do
      {sel_start, sel_end} = Selection.get_selection_range(state)

      {before, _middle, after_text} =
        Selection.split_text_at_selection(state.text, sel_start, sel_end)

      new_text = before <> clipboard_text <> after_text
      new_position = sel_start + String.length(clipboard_text)

      %{
        state
        | text: new_text,
          cursor_position: new_position,
          selection_start: nil,
          selection_end: nil
      }
      |> Rendering.adjust_scroll_offset()
    else
      {before, after_text} = String.split_at(state.text, state.cursor_position)
      new_text = before <> clipboard_text <> after_text
      new_position = state.cursor_position + String.length(clipboard_text)

      %{state | text: new_text, cursor_position: new_position}
      |> Rendering.adjust_scroll_offset()
    end
  end
end
