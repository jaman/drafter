defmodule Drafter.Widget.TextInput.Selection do
  @moduledoc false

  alias Drafter.Draw.Segment
  alias Drafter.Widget.TextInput.Rendering

  @spec has_selection?(map()) :: boolean()
  def has_selection?(state) do
    state.selection_start != nil and state.selection_end != nil
  end

  @spec clear_selection(map()) :: map()
  def clear_selection(state) do
    %{state | selection_start: nil, selection_end: nil}
  end

  @spec extend_selection(map(), non_neg_integer()) :: map()
  def extend_selection(state, new_position) do
    if state.selection_start == nil do
      %{state | selection_start: state.cursor_position, selection_end: new_position}
    else
      %{state | selection_end: new_position}
    end
  end

  @spec get_selection_range(map()) :: {non_neg_integer(), non_neg_integer()} | nil
  def get_selection_range(state) do
    if has_selection?(state) do
      start_pos = min(state.selection_start, state.selection_end)
      end_pos = max(state.selection_start, state.selection_end)
      {start_pos, end_pos}
    else
      nil
    end
  end

  @spec handle_shift_selection(map(), :left | :right | :home | :end) :: map()
  def handle_shift_selection(state, :left) do
    new_position = max(0, state.cursor_position - 1)
    extend_selection(state, new_position) |> Rendering.adjust_scroll_offset()
  end

  def handle_shift_selection(state, :right) do
    new_position = min(String.length(state.text), state.cursor_position + 1)
    extend_selection(state, new_position) |> Rendering.adjust_scroll_offset()
  end

  def handle_shift_selection(state, :home) do
    extend_selection(state, 0) |> Rendering.adjust_scroll_offset()
  end

  def handle_shift_selection(state, :end) do
    extend_selection(state, String.length(state.text)) |> Rendering.adjust_scroll_offset()
  end

  @spec render_with_selection(map(), String.t(), non_neg_integer(), map(), map()) :: [Segment.t()]
  def render_with_selection(state, display_text, content_width, normal_style, selection_style) do
    {sel_start, sel_end} = get_selection_range(state)
    scroll_offset = state.scroll_offset

    visible_start = max(0, sel_start - scroll_offset)
    visible_end = max(0, sel_end - scroll_offset)

    text_len = String.length(display_text)
    visible_start = min(visible_start, text_len)
    visible_end = min(visible_end, text_len)

    if visible_start >= visible_end do
      cursor_pos = Rendering.get_visible_cursor_position(state, content_width)
      padded_text = String.pad_trailing(display_text, content_width)
      Rendering.insert_cursor(padded_text, cursor_pos, normal_style)
    else
      before_text = String.slice(display_text, 0, visible_start)
      selected_text = String.slice(display_text, visible_start, visible_end - visible_start)
      after_text = String.slice(display_text, visible_end..-1//1)

      segments = []

      segments =
        if String.length(before_text) > 0 do
          segments ++ [Segment.new(before_text, normal_style)]
        else
          segments
        end

      segments = segments ++ [Segment.new(selected_text, selection_style)]

      segments =
        if String.length(after_text) > 0 do
          segments ++ [Segment.new(after_text, normal_style)]
        else
          segments
        end

      total_visible_len =
        String.length(before_text) + String.length(selected_text) + String.length(after_text)

      if total_visible_len < content_width do
        padding = String.duplicate(" ", content_width - total_visible_len)
        segments ++ [Segment.new(padding, normal_style)]
      else
        segments
      end
    end
  end

  @spec split_text_at_selection(String.t(), non_neg_integer(), non_neg_integer()) ::
          {String.t(), String.t(), String.t()}
  def split_text_at_selection(text, sel_start, sel_end) do
    before = String.slice(text, 0, sel_start)
    selected = String.slice(text, sel_start, sel_end - sel_start)
    after_text = String.slice(text, sel_end..-1//1)
    {before, selected, after_text}
  end

  @spec delete_selection(map()) :: map()
  def delete_selection(state) do
    {sel_start, sel_end} = get_selection_range(state)
    {before, _middle, after_text} = split_text_at_selection(state.text, sel_start, sel_end)
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

  @spec insert_char_replace_selection(map(), String.t()) :: map()
  def insert_char_replace_selection(state, char) do
    {sel_start, sel_end} = get_selection_range(state)
    {before, _middle, after_text} = split_text_at_selection(state.text, sel_start, sel_end)
    new_text = before <> char <> after_text

    %{
      state
      | text: new_text,
        cursor_position: sel_start + 1,
        selection_start: nil,
        selection_end: nil
    }
    |> Rendering.adjust_scroll_offset()
  end
end
