defmodule Drafter.Widget.TextArea.Render do
  @moduledoc false

  alias Drafter.Draw.Segment
  alias Drafter.Widget.TextArea.{Highlight, Selection}

  @spec render_content(map(), pos_integer(), pos_integer(), map()) ::
          [{String.t(), [Segment.t()] | nil}]
  def render_content(state, content_width, content_height, effective_style) do
    lines = state.lines
    focused = state.focused
    placeholder = state.placeholder

    if Enum.all?(lines, &(&1 == "")) and not focused and placeholder != "" do
      placeholder_lines =
        String.split(placeholder, "\n")
        |> Enum.map(fn line ->
          padded = String.pad_trailing(String.slice(line, 0, content_width), content_width)
          {padded, nil}
        end)
        |> Enum.take(content_height)

      padding_needed = max(0, content_height - length(placeholder_lines))

      placeholder_lines ++
        List.duplicate({String.duplicate(" ", content_width), nil}, padding_needed)
    else
      visible_lines =
        lines
        |> Enum.slice(state.scroll_offset, content_height)
        |> Enum.with_index(state.scroll_offset)
        |> Enum.map(&render_visible_line(&1, state, content_width, effective_style))

      padding_needed = max(0, content_height - length(visible_lines))

      visible_lines ++
        List.duplicate({String.duplicate(" ", content_width), nil}, padding_needed)
    end
  end

  @spec render_visible_line({String.t(), non_neg_integer()}, map(), pos_integer(), map()) ::
          {String.t(), [Segment.t()]}
  def render_visible_line({line, line_index}, state, content_width, effective_style) do
    line_content = String.slice(line, 0, content_width)
    is_cursor_line = state.focused and line_index == state.cursor_line

    cursor_line_style =
      if state.highlight_cursor_line and is_cursor_line do
        tint_bg(effective_style, -15)
      else
        effective_style
      end

    segments = build_line_segments(state, line_content, line_index, content_width, cursor_line_style, effective_style)
    display_line = line_display(is_cursor_line, line_content, state.cursor_col, content_width)
    {display_line, segments}
  end

  @spec line_display(boolean(), String.t(), non_neg_integer(), pos_integer()) :: String.t()
  def line_display(true, line_content, cursor_col, content_width),
    do: insert_cursor_in_line(line_content, cursor_col, content_width)

  def line_display(false, line_content, _cursor_col, content_width),
    do: String.pad_trailing(line_content, content_width)

  @spec build_line_segments(map(), String.t(), non_neg_integer(), pos_integer(), map(), map()) ::
          [Segment.t()]
  def build_line_segments(state, line_content, line_index, content_width, cursor_line_style, _effective_style) do
    focused = state.focused
    is_cursor_line = focused and line_index == state.cursor_line
    has_selection = state.selection != nil and focused

    cond do
      has_selection ->
        build_selection_segments(state, line_content, line_index, content_width, cursor_line_style)

      is_cursor_line ->
        build_cursor_segments(line_content, state.cursor_col, content_width, cursor_line_style)

      state.language != nil ->
        Highlight.highlight_line(line_content, state.language, cursor_line_style)

      true ->
        [Segment.new(String.pad_trailing(line_content, content_width), cursor_line_style)]
    end
  end

  @spec build_cursor_segments(String.t(), non_neg_integer(), pos_integer(), map()) :: [Segment.t()]
  def build_cursor_segments(line, cursor_col, content_width, style) do
    padded = String.pad_trailing(line, content_width)
    cursor_pos = min(cursor_col, content_width - 1)
    line_len = String.length(padded)

    if cursor_pos >= 0 and cursor_pos < line_len do
      before_text = String.slice(padded, 0, cursor_pos)
      cursor_char = String.slice(padded, cursor_pos, 1)
      after_text = String.slice(padded, cursor_pos + 1, line_len)

      cursor_style = %{fg: {0, 0, 0}, bg: {255, 255, 255}}

      [
        Segment.new(before_text, style),
        Segment.new(cursor_char, cursor_style),
        Segment.new(after_text, style)
      ]
      |> Enum.reject(&(&1.text == ""))
    else
      [
        Segment.new(padded, style),
        Segment.new(" ", %{fg: {0, 0, 0}, bg: {255, 255, 255}})
      ]
    end
  end

  @spec build_selection_segments(map(), String.t(), non_neg_integer(), pos_integer(), map()) ::
          [Segment.t()]
  def build_selection_segments(state, line_content, line_index, content_width, base_style) do
    {sel_start_row, sel_start_col, sel_end_row, sel_end_col} = Selection.normalize_selection(state.selection)
    padded = String.pad_trailing(line_content, content_width)

    if line_index < sel_start_row or line_index > sel_end_row do
      render_unselected_line(padded, state.language, base_style)
    else
      sel_bounds = {sel_start_row, sel_start_col, sel_end_row, sel_end_col}
      build_selected_line_segments(state, padded, line_index, sel_bounds, base_style)
    end
  end

  @spec render_unselected_line(String.t(), atom() | nil, map()) :: [Segment.t()]
  def render_unselected_line(padded, nil, base_style), do: [Segment.new(padded, base_style)]
  def render_unselected_line(padded, language, base_style), do: Highlight.highlight_line(padded, language, base_style)

  @spec build_selected_line_segments(map(), String.t(), non_neg_integer(), tuple(), map()) ::
          [Segment.t()]
  def build_selected_line_segments(state, padded, line_index, {sel_start_row, sel_start_col, sel_end_row, sel_end_col}, base_style) do
    line_len = String.length(padded)
    col_start = if line_index == sel_start_row, do: sel_start_col, else: 0
    col_end = if line_index == sel_end_row, do: min(sel_end_col, line_len), else: line_len

    before_text = String.slice(padded, 0, col_start)
    selected_text = String.slice(padded, col_start, col_end - col_start)
    after_text = String.slice(padded, col_end, line_len - col_end)

    is_cursor_line = state.focused and line_index == state.cursor_line
    cursor_style = %{fg: {0, 0, 0}, bg: {255, 255, 255}}
    sel_style = state.selection_style

    []
    |> append_segment(before_text, base_style)
    |> append_selected_segment(selected_text, col_start, state.cursor_col, is_cursor_line, sel_style, cursor_style)
    |> append_after_segment(after_text, col_end, state.cursor_col, is_cursor_line, base_style, cursor_style)
  end

  @spec append_segment([Segment.t()], String.t(), map()) :: [Segment.t()]
  def append_segment(segs, "", _style), do: segs
  def append_segment(segs, text, style), do: segs ++ [Segment.new(text, style)]

  @spec append_selected_segment(
          [Segment.t()],
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          boolean(),
          map(),
          map()
        ) :: [Segment.t()]
  def append_selected_segment(segs, "", _col_start, _cursor_col, _is_cursor_line, _sel_style, _cursor_style),
    do: segs

  def append_selected_segment(segs, selected_text, col_start, cursor_col, true, sel_style, cursor_style),
    do: build_selected_with_cursor(selected_text, col_start, cursor_col, sel_style, cursor_style, segs)

  def append_selected_segment(segs, selected_text, _col_start, _cursor_col, false, sel_style, _cursor_style),
    do: segs ++ [Segment.new(selected_text, sel_style)]

  @spec append_after_segment(
          [Segment.t()],
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          boolean(),
          map(),
          map()
        ) :: [Segment.t()]
  def append_after_segment(segs, "", _col_end, _cursor_col, _is_cursor_line, _base_style, _cursor_style),
    do: segs

  def append_after_segment(segs, after_text, col_end, cursor_col, true, base_style, cursor_style)
      when cursor_col >= col_end do
    after_cursor_pos = cursor_col - col_end
    after_len = String.length(after_text)
    split_text_with_cursor(segs, after_text, after_cursor_pos, after_len, base_style, cursor_style)
  end

  def append_after_segment(segs, after_text, _col_end, _cursor_col, _is_cursor_line, base_style, _cursor_style),
    do: segs ++ [Segment.new(after_text, base_style)]

  @spec split_text_with_cursor([Segment.t()], String.t(), non_neg_integer(), non_neg_integer(), map(), map()) ::
          [Segment.t()]
  def split_text_with_cursor(segs, text, cursor_pos, text_len, base_style, cursor_style)
      when cursor_pos < text_len do
    before_c = String.slice(text, 0, cursor_pos)
    cursor_c = String.slice(text, cursor_pos, 1)
    after_c = String.slice(text, cursor_pos + 1, text_len)

    segs
    |> append_segment(before_c, base_style)
    |> then(&(&1 ++ [Segment.new(cursor_c, cursor_style)]))
    |> append_segment(after_c, base_style)
  end

  def split_text_with_cursor(segs, text, _cursor_pos, _text_len, base_style, _cursor_style),
    do: segs ++ [Segment.new(text, base_style)]

  @spec build_selected_with_cursor(String.t(), non_neg_integer(), non_neg_integer(), map(), map(), [Segment.t()]) ::
          [Segment.t()]
  def build_selected_with_cursor(selected_text, col_start, cursor_col, sel_style, cursor_style, acc) do
    sel_len = String.length(selected_text)
    relative_cursor = cursor_col - col_start

    if relative_cursor >= 0 and relative_cursor < sel_len do
      before_c = String.slice(selected_text, 0, relative_cursor)
      cursor_c = String.slice(selected_text, relative_cursor, 1)
      after_c = String.slice(selected_text, relative_cursor + 1, sel_len)

      segs = if before_c != "", do: acc ++ [Segment.new(before_c, sel_style)], else: acc
      segs = segs ++ [Segment.new(cursor_c, cursor_style)]
      if after_c != "", do: segs ++ [Segment.new(after_c, sel_style)], else: segs
    else
      acc ++ [Segment.new(selected_text, sel_style)]
    end
  end

  @spec insert_cursor_in_line(String.t(), non_neg_integer(), pos_integer()) :: String.t()
  def insert_cursor_in_line(line, cursor_col, max_width) do
    padded_line = String.pad_trailing(line, max_width)
    cursor_pos = min(cursor_col, max_width - 1)

    if cursor_pos >= 0 and cursor_pos < String.length(padded_line) do
      {before, after_text} = String.split_at(padded_line, cursor_pos)
      after_char = String.slice(after_text, 1..-1//1) || ""
      before <> "\u2588" <> after_char
    else
      padded_line <> "\u2588"
    end
  end

  @spec tint_bg(map(), integer()) :: map()
  def tint_bg(style, delta) do
    case Map.get(style, :bg) do
      {r, g, b} ->
        clamped = fn v -> max(0, min(255, v + delta)) end
        Map.put(style, :bg, {clamped.(r), clamped.(g), clamped.(b)})

      _ ->
        style
    end
  end
end
