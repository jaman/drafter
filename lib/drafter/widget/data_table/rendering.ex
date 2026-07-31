defmodule Drafter.Widget.DataTable.Rendering do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.DataTable
  alias Drafter.Widget.DataTable.Columns
  alias Drafter.Widget.Scrollbar

  def normalize_state(state) when is_struct(state, DataTable), do: state
  def normalize_state(state), do: DataTable.mount(state)

  def table_width(state, content_width, data_height) do
    if state.show_scrollbars && length(state.data) > data_height do
      content_width - 1
    else
      content_width
    end
  end

  def render_data_strips(state, column_widths, table_width, data_height) do
    start_idx = state.scroll.offset
    visible_count = min(data_height, length(state.data) - start_idx)

    if visible_count > 0 do
      start_idx..(start_idx + visible_count - 1)
      |> Enum.map(fn row_index ->
        render_row(state, Enum.at(state.data, row_index), row_index, column_widths, table_width)
      end)
    else
      []
    end
  end

  def pad_strips_to_height(strips, content_height, table_width, style) do
    current_height = length(strips)

    if current_height < content_height do
      empty_strip = Strip.new([Segment.new(String.duplicate(" ", table_width), style)])
      strips ++ List.duplicate(empty_strip, content_height - current_height)
    else
      Enum.take(strips, content_height)
    end
  end

  def header_sort_indicator(state, column, width)
      when state.sortable and column.sortable and width > 1 do
    char = sort_indicator_char(state, column.key)
    {width - 1, char}
  end

  def header_sort_indicator(_state, _column, width), do: {width, ""}

  def sort_indicator_char(%{sort_column: key, sort_direction: :asc}, key), do: "↑"
  def sort_indicator_char(%{sort_column: key, sort_direction: :desc}, key), do: "↓"
  def sort_indicator_char(_state, _key), do: "↕"

  def header_cell_cursor?(state, col_index, focused) do
    focused and col_index == state.cursor_col and state.cursor_type != :none and state.show_cursor
  end

  def header_segment(state, column, width, col_index, focused) do
    {label_width, indicator} = header_sort_indicator(state, column, width)

    formatted_text =
      Columns.format_cell_content(column.label, label_width, column.align, 0) <> indicator

    style =
      if header_cell_cursor?(state, col_index, focused) do
        Map.merge(state.styles.header, state.styles.cursor)
      else
        state.styles.header
      end

    Segment.new(formatted_text, style)
  end

  def render_header(state, column_widths, total_width, focused) do
    {visible_cols, visible_widths, visible_indices} =
      visible_columns(state, column_widths, total_width)

    segments =
      Enum.zip([visible_cols, visible_widths, visible_indices])
      |> Enum.map(fn {column, width, col_index} ->
        header_segment(state, column, width, col_index, focused)
      end)

    current_width = Enum.sum(visible_widths)

    segments =
      if current_width < total_width do
        padding = String.duplicate(" ", total_width - current_width)
        segments ++ [Segment.new(padding, state.styles.header)]
      else
        segments
      end

    Strip.new(segments)
  end

  def row_base_style(state, is_selected, is_zebra) do
    cond do
      is_selected -> state.styles.selected
      is_zebra -> Map.merge(state.styles.base, %{bg: adjust_color(state.styles.base.bg, -10)})
      true -> state.styles.base
    end
  end

  def apply_color_fn(base_style, _raw_value, nil), do: base_style

  def apply_color_fn(base_style, raw_value, color_fn) do
    case color_fn.(raw_value) do
      nil -> base_style
      %{bg: bg, fg: fg} -> base_style |> Map.put(:bg, bg) |> Map.put(:fg, fg)
      color -> Map.put(base_style, :bg, color)
    end
  end

  def cursor_highlights_cell?(%{cursor_type: :row}, _col_index, is_highlighted, focused) do
    is_highlighted and focused
  end

  def cursor_highlights_cell?(%{cursor_type: :cell} = state, col_index, is_highlighted, focused) do
    is_highlighted and col_index == state.cursor_col and focused
  end

  def cursor_highlights_cell?(
        %{cursor_type: :column} = state,
        col_index,
        _is_highlighted,
        focused
      ) do
    col_index == state.cursor_col and focused
  end

  def cursor_highlights_cell?(_state, _col_index, _is_highlighted, _focused), do: false

  def cell_style(
        state,
        base_style,
        raw_value,
        column,
        col_index,
        is_selected,
        is_highlighted,
        focused
      ) do
    cond do
      is_selected -> base_style
      cursor_highlights_cell?(state, col_index, is_highlighted, focused) -> state.styles.cursor
      true -> apply_color_fn(base_style, raw_value, Map.get(column, :color_fn))
    end
  end

  def render_row(state, row, row_index, column_widths, total_width) do
    is_selected = MapSet.member?(state.selected_indices, row_index)
    is_highlighted = state.highlighted_index == row_index
    is_zebra = state.zebra_stripes && rem(row_index, 2) == 1
    base_style = row_base_style(state, is_selected, is_zebra)
    focused = Map.get(state, :focused, false)

    {visible_cols, visible_widths, visible_indices} =
      visible_columns(state, column_widths, total_width)

    segments =
      Enum.zip([visible_cols, visible_widths, visible_indices])
      |> Enum.map(fn {column, width, col_index} ->
        raw_value = Map.get(row, column.key, "")

        formatted_text =
          Columns.format_cell_content(
            to_string(raw_value),
            width,
            column.align,
            state.cell_padding
          )

        style =
          cell_style(
            state,
            base_style,
            raw_value,
            column,
            col_index,
            is_selected,
            is_highlighted,
            focused
          )

        Segment.new(formatted_text, style)
      end)

    current_width = Enum.sum(visible_widths)

    segments =
      if current_width < total_width do
        padding = String.duplicate(" ", total_width - current_width)
        segments ++ [Segment.new(padding, state.styles.base)]
      else
        segments
      end

    Strip.new(segments)
  end

  def visible_columns(state, column_widths, total_width) do
    offset_col = get_in(state, [Access.key(:scroll), Access.key(:offset_col)]) || 0
    all_cols = Columns.get_ordered_columns(state)
    indexed = Enum.zip([all_cols, column_widths, Enum.to_list(0..(length(all_cols) - 1)//1)])
    scrolled = Enum.drop(indexed, offset_col)

    {visible, _used} =
      Enum.reduce_while(scrolled, {[], 0}, fn {col, width, idx}, {acc, used} ->
        next_used = used + width

        if next_used > total_width do
          {:halt, {acc ++ [{col, min(width, total_width - used), idx}], next_used}}
        else
          {:cont, {acc ++ [{col, width, idx}], next_used}}
        end
      end)

    cols = Enum.map(visible, &elem(&1, 0))
    widths = Enum.map(visible, &elem(&1, 1))
    indices = Enum.map(visible, &elem(&1, 2))
    {cols, widths, indices}
  end

  def adjust_color({r, g, b}, adjustment) do
    {
      max(0, min(255, r + adjustment)),
      max(0, min(255, g + adjustment)),
      max(0, min(255, b + adjustment))
    }
  end

  def adjust_color(color, _adjustment), do: color

  def apply_theme_styles(state, theme) do
    %{
      state
      | styles: %{
          base: %{fg: theme.text_primary, bg: theme.background},
          header: %{fg: theme.text_primary, bg: theme.surface, bold: true},
          selected: %{fg: theme.text_primary, bg: theme.primary},
          cursor: %{fg: theme.text_primary, bg: theme.primary, bold: true}
        }
    }
  end

  @doc """
  The strip rows the scrollbar thumb covers, offset to the widget's coordinates.

  Returns `nil` when the data fits and no scrollbar is drawn. Thumb geometry
  comes from `Drafter.Widget.Scrollbar`.
  """
  def scrollbar_thumb_rows(state, data_start_y, data_height) do
    case Scrollbar.thumb_rows(state.scroll.offset, length(state.data), data_height) do
      nil -> nil
      first..last//_ -> (data_start_y + first)..(data_start_y + last)
    end
  end

  def scrollbar_char_at(index, thumb, data_start_y) do
    cond do
      on_thumb?(index, thumb) -> "█"
      index >= data_start_y -> "│"
      true -> " "
    end
  end

  defp on_thumb?(_index, nil), do: false
  defp on_thumb?(index, thumb), do: index in thumb

  def scrollbar_style_at(index, thumb, hovering) do
    cond do
      on_thumb?(index, thumb) and hovering -> %{fg: {255, 255, 255}, bg: {0, 150, 255}}
      on_thumb?(index, thumb) -> %{fg: {200, 200, 200}, bg: {100, 100, 100}}
      true -> %{fg: {100, 100, 100}, bg: {60, 60, 60}}
    end
  end

  def append_scrollbar_segment(strip, index, thumb, data_start_y, hovering) do
    char = scrollbar_char_at(index, thumb, data_start_y)
    style = scrollbar_style_at(index, thumb, hovering)
    segment = Segment.new(char, style)
    existing = strip.segments || []
    Strip.new(existing ++ [segment])
  end

  def add_vertical_scrollbar(strips, state, _total_width, data_height) do
    total_rows = length(state.data)

    if total_rows > data_height do
      data_start_y = DataTable.get_data_start_y(state)
      thumb = scrollbar_thumb_rows(state, data_start_y, data_height)

      strips
      |> Enum.with_index()
      |> Enum.map(fn {strip, index} ->
        append_scrollbar_segment(strip, index, thumb, data_start_y, state.drag.hovering_scrollbar)
      end)
    else
      strips
    end
  end
end
