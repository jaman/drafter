defmodule Drafter.Widget.TextInput.WordNav do
  @moduledoc false

  alias Drafter.Widget.TextInput.{Rendering, Selection}

  @spec handle_word_navigation(map(), :left | :right) :: map()
  def handle_word_navigation(state, direction) do
    new_position = find_word_boundary(state.text, state.cursor_position, direction)

    Selection.clear_selection(state)
    |> Map.put(:cursor_position, new_position)
    |> Rendering.adjust_scroll_offset()
  end

  @spec handle_word_selection(map(), :left | :right) :: map()
  def handle_word_selection(state, direction) do
    new_position = find_word_boundary(state.text, state.cursor_position, direction)

    Selection.extend_selection(state, new_position)
    |> Map.put(:cursor_position, new_position)
    |> Rendering.adjust_scroll_offset()
  end

  @spec delete_word_left(map()) :: map()
  def delete_word_left(state) do
    graphemes = String.graphemes(state.text)
    pos = state.cursor_position

    new_pos = find_word_left_boundary(graphemes, pos - 1)

    before = String.slice(state.text, 0, new_pos)
    after_text = String.slice(state.text, pos..-1//1)

    %{state | text: before <> after_text, cursor_position: new_pos}
    |> Selection.clear_selection()
    |> Rendering.adjust_scroll_offset()
  end

  @spec find_word_left_boundary(list(), integer()) :: non_neg_integer()
  def find_word_left_boundary(_graphemes, index) when index < 0, do: 0

  def find_word_left_boundary(graphemes, index) do
    char = Enum.at(graphemes, index, "")

    if char == " " do
      find_word_left_boundary(graphemes, index - 1)
    else
      find_word_left_non_space(graphemes, index)
    end
  end

  @spec find_word_left_non_space(list(), integer()) :: non_neg_integer()
  def find_word_left_non_space(_graphemes, index) when index < 0, do: 0

  def find_word_left_non_space(graphemes, index) do
    char = Enum.at(graphemes, index, "")

    if char != " " and index > 0 do
      find_word_left_non_space(graphemes, index - 1)
    else
      if char == " ", do: index + 1, else: index
    end
  end

  @spec find_word_boundary(String.t(), non_neg_integer(), :left | :right) :: non_neg_integer()
  def find_word_boundary(text, position, direction) do
    text_len = String.length(text)

    cond do
      direction == :left and position == 0 ->
        0

      direction == :right and position >= text_len ->
        text_len

      true ->
        graphemes = String.graphemes(text)
        current_index = position

        if direction == :left do
          skip_non_word_chars(graphemes, current_index - 1, :left)
        else
          skip_word_chars(graphemes, current_index, :right)
        end
    end
  end

  @spec skip_word_chars(list(), integer(), :left | :right) :: non_neg_integer()
  def skip_word_chars(graphemes, index, direction) do
    len = length(graphemes)

    cond do
      index >= len ->
        len

      direction == :right ->
        if index < len and word_char?(Enum.at(graphemes, index, "")) do
          skip_word_chars(graphemes, index + 1, :right)
        else
          index
        end

      true ->
        index
    end
  end

  @spec skip_non_word_chars(list(), integer(), :left | :right) :: non_neg_integer()
  def skip_non_word_chars(graphemes, index, direction) do
    cond do
      index < 0 ->
        0

      direction == :left ->
        if index >= 0 and not word_char?(Enum.at(graphemes, index, "")) do
          skip_non_word_chars(graphemes, index - 1, :left)
        else
          index + 1
        end

      true ->
        index
    end
  end

  @spec word_char?(String.t()) :: boolean()
  def word_char?(char) do
    case Regex.run(~r/^\w$/, char) do
      nil -> false
      _ -> true
    end
  end
end
