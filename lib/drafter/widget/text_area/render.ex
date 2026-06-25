defmodule Drafter.Widget.TextArea.Render do
  @moduledoc false

  alias Drafter.Draw.Segment
  alias Drafter.Widget.TextArea.{Highlight, Selection}

  @spec render_content(map(), pos_integer(), pos_integer(), map()) ::
          [{String.t() | nil, [Segment.t()] | nil}]
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
          {nil, [Segment.t()]}
  def render_visible_line({line, line_index}, state, content_width, effective_style) do
    is_cursor_line = state.focused and line_index == state.cursor_line

    line_style =
      if state.highlight_cursor_line and is_cursor_line do
        tint_bg(effective_style, -15)
      else
        effective_style
      end

    h = clamp_scroll(state.h_scroll || 0, state.cursor_col, content_width)

    visible =
      state
      |> base_segments(line, line_style)
      |> slice_segments(h, content_width)

    decorated = decorate(state, visible, line_index, is_cursor_line, content_width, h, line_style)
    {nil, pad_segments(decorated, content_width, line_style)}
  end

  defp clamp_scroll(h, col, width) do
    cond do
      col < h -> col
      col >= h + width -> col - width + 1
      true -> h
    end
  end

  defp base_segments(%{language: nil}, line, style), do: [Segment.new(line, style)]

  defp base_segments(%{language: language}, line, style),
    do: Highlight.highlight_line(line, language, style)

  defp decorate(state, visible, line_index, is_cursor_line, content_width, h, style) do
    cond do
      state.selection != nil and state.focused ->
        overlay_selection(state, visible, line_index, content_width, h, style)

      is_cursor_line ->
        overlay_cursor(visible, state.cursor_col - h, content_width, style)

      true ->
        visible
    end
  end

  @spec overlay_cursor([Segment.t()], integer(), pos_integer(), map()) :: [Segment.t()]
  def overlay_cursor(visible, col, _content_width, _style) when col < 0, do: visible

  def overlay_cursor(visible, col, content_width, style) do
    total = segments_len(visible)
    cursor_style = %{fg: {0, 0, 0}, bg: {255, 255, 255}}

    if col >= total do
      pad = min(col, content_width - 1) - total
      visible ++ pad_run(pad, style) ++ [Segment.new(" ", cursor_style)]
    else
      {left, rest} = split_segments(visible, col)
      {mid, right} = split_segments(rest, 1)
      left ++ recolor(mid, cursor_style) ++ right
    end
  end

  @spec slice_segments([Segment.t()], non_neg_integer(), non_neg_integer()) :: [Segment.t()]
  def slice_segments(segments, start, width) do
    segments |> drop_cols(start) |> take_cols(width, [])
  end

  defp drop_cols(segments, 0), do: segments
  defp drop_cols([], _n), do: []

  defp drop_cols([seg | rest], n) do
    len = String.length(seg.text)

    if len <= n do
      drop_cols(rest, n - len)
    else
      [Segment.new(String.slice(seg.text, n, len - n), seg.style) | rest]
    end
  end

  defp take_cols(_segments, 0, acc), do: Enum.reverse(acc)
  defp take_cols([], _width, acc), do: Enum.reverse(acc)

  defp take_cols([seg | rest], width, acc) do
    len = String.length(seg.text)

    if len <= width do
      take_cols(rest, width - len, [seg | acc])
    else
      Enum.reverse([Segment.new(String.slice(seg.text, 0, width), seg.style) | acc])
    end
  end

  defp split_segments(segments, col), do: do_split(segments, col, [])

  defp do_split(segments, 0, acc), do: {Enum.reverse(acc), segments}
  defp do_split([], _col, acc), do: {Enum.reverse(acc), []}

  defp do_split([seg | rest], col, acc) do
    len = String.length(seg.text)

    if len <= col do
      do_split(rest, col - len, [seg | acc])
    else
      left = Segment.new(String.slice(seg.text, 0, col), seg.style)
      right = Segment.new(String.slice(seg.text, col, len - col), seg.style)
      {Enum.reverse([left | acc]), [right | rest]}
    end
  end

  defp recolor(segments, style), do: Enum.map(segments, fn s -> Segment.new(s.text, style) end)

  defp segments_len(segments), do: Enum.reduce(segments, 0, fn s, acc -> acc + String.length(s.text) end)

  defp pad_run(n, _style) when n <= 0, do: []
  defp pad_run(n, style), do: [Segment.new(String.duplicate(" ", n), style)]

  defp overlay_selection(state, visible, line_index, content_width, h, style) do
    {ss_row, ss_col, se_row, se_col} = Selection.normalize_selection(state.selection)

    recolored =
      if line_index >= ss_row and line_index <= se_row do
        col_start = if line_index == ss_row, do: ss_col, else: h
        col_end = if line_index == se_row, do: se_col, else: h + content_width
        ws = max(0, col_start - h)
        we = min(content_width, col_end - h)
        recolor_range(visible, ws, we, state.selection_style)
      else
        visible
      end

    if state.focused and line_index == state.cursor_line do
      overlay_cursor(recolored, state.cursor_col - h, content_width, style)
    else
      recolored
    end
  end

  defp recolor_range(segments, start, stop, _style) when stop <= start, do: segments

  defp recolor_range(segments, start, stop, style) do
    {left, rest} = split_segments(segments, start)
    {mid, right} = split_segments(rest, stop - start)
    left ++ recolor(mid, style) ++ right
  end

  @spec pad_segments([Segment.t()], pos_integer(), map()) :: [Segment.t()]
  def pad_segments(segments, target_width, style) do
    seg_width = Enum.reduce(segments, 0, fn seg, acc -> acc + Segment.width(seg) end)

    if seg_width < target_width do
      segments ++ [Segment.new(String.duplicate(" ", target_width - seg_width), style)]
    else
      segments
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
