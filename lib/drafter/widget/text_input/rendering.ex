defmodule Drafter.Widget.TextInput.Rendering do
  @moduledoc false

  alias Drafter.Draw.Segment

  @spec get_display_text(map(), non_neg_integer()) :: String.t()
  def get_display_text(state, content_width) do
    text = Map.get(state, :text, "")
    placeholder = Map.get(state, :placeholder, "")
    focused = Map.get(state, :focused, false)
    scroll_offset = Map.get(state, :scroll_offset, 0)
    password = Map.get(state, :password, false)

    if String.length(text) == 0 and not focused do
      String.slice(placeholder, 0, content_width)
    else
      visible_text = String.slice(text, scroll_offset, content_width)

      if password do
        String.duplicate("•", String.length(visible_text))
      else
        visible_text
      end
    end
  end

  @spec get_visible_cursor_position(map(), non_neg_integer()) :: integer()
  def get_visible_cursor_position(state, _content_width) do
    state.cursor_position - state.scroll_offset
  end

  @spec insert_cursor(String.t(), integer(), map()) :: [Segment.t()]
  def insert_cursor(text, position, style) do
    if position >= 0 and position < String.length(text) do
      {before, after_text} = String.split_at(text, position)
      cursor_char = String.first(after_text) || " "
      rest = String.slice(after_text, 1..-1//1) || ""

      [
        Segment.new(before, style),
        Segment.new(cursor_char, Map.put(style, :reverse, true)),
        Segment.new(rest, style)
      ]
    else
      [Segment.new(text, style), Segment.new("█", Map.put(style, :reverse, true))]
    end
  end

  @spec adjust_scroll_offset(map()) :: map()
  def adjust_scroll_offset(state) do
    content_width = state.width

    cond do
      state.cursor_position < state.scroll_offset ->
        %{state | scroll_offset: state.cursor_position}

      state.cursor_position >= state.scroll_offset + content_width ->
        %{state | scroll_offset: state.cursor_position - content_width + 1}

      true ->
        state
    end
  end
end
