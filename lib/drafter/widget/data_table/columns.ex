defmodule Drafter.Widget.DataTable.Columns do
  @moduledoc false

  def normalize_columns(columns) do
    Enum.map(columns, fn
      %{} = col ->
        Map.merge(%{width: :auto, align: :left, sortable: true, color_fn: nil}, col)

      {key, label} ->
        %{key: key, label: label, width: :auto, align: :left, sortable: true, color_fn: nil}

      key when is_atom(key) ->
        %{
          key: key,
          label: to_string(key),
          width: :auto,
          align: :left,
          sortable: true,
          color_fn: nil
        }
    end)
  end

  def distribute_remainder(widths, 0), do: widths

  def distribute_remainder(widths, remainder) do
    {first_part, rest} = Enum.split(widths, remainder)
    Enum.map(first_part, &(&1 + 1)) ++ rest
  end

  def calculate_column_widths([], _total_width, _fit_mode, _data), do: []

  def calculate_column_widths(columns, total_width, :fit, _data) do
    col_count = length(columns)
    base_width = div(total_width, col_count)
    remainder = rem(total_width, col_count)
    List.duplicate(base_width, col_count) |> distribute_remainder(remainder)
  end

  def calculate_column_widths(columns, total_width, :expand, data) do
    calculate_content_based_widths(columns, data, total_width)
  end

  def optimal_column_width(column, data) do
    header_width = String.length(column.label) + 2

    content_width =
      data
      |> Enum.take(20)
      |> Enum.map(fn row -> Map.get(row, column.key, "") |> to_string() |> String.length() end)
      |> Enum.max(fn -> 0 end)

    width = max(header_width, content_width)
    max(8, min(30, width))
  end

  def expand_widths_to_fill(optimal_widths, min_total_width) do
    total_optimal = Enum.sum(optimal_widths)

    if total_optimal < min_total_width do
      extra_space = min_total_width - total_optimal
      extra_per_col = div(extra_space, length(optimal_widths))
      remainder = rem(extra_space, length(optimal_widths))
      Enum.map(optimal_widths, &(&1 + extra_per_col)) |> distribute_remainder(remainder)
    else
      optimal_widths
    end
  end

  def calculate_content_based_widths(columns, data, min_total_width) do
    optimal_widths = Enum.map(columns, &optimal_column_width(&1, data))
    expand_widths_to_fill(optimal_widths, min_total_width)
  end

  def get_column_widths(state, table_width) do
    state._col_widths ||
      calculate_column_widths(state.columns, table_width, state.column_fit_mode, state.data)
  end

  def get_ordered_columns(state) do
    case state._col_order do
      nil -> state.columns
      order -> Enum.map(order, &Enum.at(state.columns, &1))
    end
  end

  def get_col_order_list(state) do
    count = length(state.columns)
    state._col_order || if count > 0, do: Enum.to_list(0..(count - 1)//1), else: []
  end

  def format_cell_content(content, width, align, cell_padding) when width > 0 do
    pad = String.duplicate(" ", cell_padding)
    inner_width = max(0, width - 2 * cell_padding)

    truncated =
      if String.length(content) > inner_width do
        String.slice(content, 0, max(0, inner_width - 1)) <> "…"
      else
        content
      end

    aligned =
      case align do
        :left ->
          String.pad_trailing(truncated, inner_width)

        :right ->
          String.pad_leading(truncated, inner_width)

        :center ->
          total_padding = inner_width - String.length(truncated)
          left_padding = div(total_padding, 2)
          right_padding = total_padding - left_padding
          String.duplicate(" ", left_padding) <> truncated <> String.duplicate(" ", right_padding)
      end

    pad <> aligned <> pad
  end

  def format_cell_content(_content, _width, _align, _cell_padding), do: ""

  def calculate_column_from_x(state, x) do
    column_widths = get_column_widths(state, state.width)

    {col_index, _} =
      column_widths
      |> Enum.with_index()
      |> Enum.reduce_while({0, 0}, fn {width, col_index}, {current_x, _} ->
        if x >= current_x && x < current_x + width do
          {:halt, {col_index, current_x}}
        else
          {:cont, {current_x + width, col_index}}
        end
      end)

    col_index
  end

  def fixed_col_widths_for(state, fixed_cols) do
    Enum.slice(state.columns, 0, fixed_cols)
    |> Enum.map(fn col -> if col.width == :auto, do: 10, else: col.width end)
  end

  def compute_scroll_offset(state, fixed_cols, num_scrollable, remaining_width)
      when remaining_width > 0 do
    if state.cursor_col < fixed_cols do
      0
    else
      widths = get_column_widths(state, state.width)
      scrollable_widths = Enum.drop(widths, fixed_cols)
      cursor_in_scrollable = state.cursor_col - fixed_cols
      current_offset = Map.get(state.scroll, :offset_col, 0)

      scrollable_offset(
        scrollable_widths,
        cursor_in_scrollable,
        current_offset,
        remaining_width,
        num_scrollable
      )
    end
  end

  def compute_scroll_offset(_state, _fixed_cols, _num_scrollable, _remaining_width), do: 0

  defp scrollable_offset(widths, cursor, current_offset, remaining_width, num_scrollable) do
    visible_end = find_visible_end(widths, current_offset, remaining_width)

    cond do
      cursor < current_offset ->
        cursor

      cursor >= visible_end ->
        new_offset = find_offset_for_cursor(widths, cursor, remaining_width)
        min(new_offset, max(0, num_scrollable - 1))

      true ->
        current_offset
    end
  end

  defp find_visible_end(widths, offset, remaining_width) do
    {visible_end, _} =
      widths
      |> Enum.drop(offset)
      |> Enum.reduce_while({offset, 0}, fn w, {col, used} ->
        next = used + w + 1
        if next > remaining_width, do: {:halt, {col, used}}, else: {:cont, {col + 1, next}}
      end)

    visible_end
  end

  defp find_offset_for_cursor(widths, cursor, remaining_width) do
    {new_offset, _} =
      widths
      |> Enum.slice(0..cursor)
      |> Enum.reverse()
      |> Enum.reduce_while({cursor + 1, 0}, fn w, {col, used} ->
        next = used + w + 1
        if next > remaining_width, do: {:halt, {col, used}}, else: {:cont, {col - 1, next}}
      end)

    new_offset
  end

  def adjust_scroll_horizontal(state) do
    fixed_cols = state.fixed_columns

    if length(state.columns) <= fixed_cols do
      state
    else
      num_scrollable = length(state.columns) - fixed_cols

      if num_scrollable == 0 do
        state
      else
        fixed_widths = fixed_col_widths_for(state, fixed_cols)
        fixed_width = Enum.sum(fixed_widths) + length(fixed_widths) - 1
        remaining_width = max(0, state.width - fixed_width)
        offset = compute_scroll_offset(state, fixed_cols, num_scrollable, remaining_width)
        %{state | scroll: %{state.scroll | offset_col: offset}, fixed_col_widths: fixed_widths}
      end
    end
  end

  def do_column_resize(state, x) do
    delta = x - state.drag.resize_start_x
    new_width = max(3, state.drag.resize_start_width + delta)
    new_col_widths = List.replace_at(state._col_widths, state.drag.resize_col, new_width)
    {:ok, %{state | _col_widths: new_col_widths}, [:render_update]}
  end

  def resize_cursor_col(state, delta, trigger_layout_change_fn) do
    col = state.cursor_col
    widths = get_column_widths(state, state.width)
    current = Enum.at(widths, col, 10)
    new_width = max(3, current + delta)
    new_col_widths = List.replace_at(widths, col, new_width)
    new_state = %{state | _col_widths: new_col_widths}
    trigger_layout_change_fn.(new_state)
    {:ok, new_state, [:render_update]}
  end

  def do_column_reorder(state, x) do
    target_col = calculate_column_from_x(state, x)
    source_col = state.drag.reorder_col

    if target_col != source_col do
      new_col_order = swap_in_list(state._col_order, source_col, target_col)
      new_col_widths = swap_in_list(state._col_widths, source_col, target_col)

      new_state = %{
        state
        | _col_order: new_col_order,
          _col_widths: new_col_widths,
          drag: %{state.drag | reorder_col: target_col},
          cursor_col: target_col
      }

      {:ok, new_state, [:render_update]}
    else
      {:ok, state}
    end
  end

  def reorder_column(state, display_col, :left, trigger_layout_change_fn) when display_col > 0 do
    widths = get_column_widths(state, state.width)
    col_order = get_col_order_list(state)
    new_col_order = swap_in_list(col_order, display_col, display_col - 1)
    new_col_widths = swap_in_list(widths, display_col, display_col - 1)

    new_state = %{
      state
      | _col_order: new_col_order,
        _col_widths: new_col_widths,
        cursor_col: display_col - 1
    }

    trigger_layout_change_fn.(new_state)
    {:ok, new_state, [:render_update]}
  end

  def reorder_column(state, _display_col, :left, _trigger_layout_change_fn), do: {:ok, state}

  def reorder_column(state, display_col, :right, trigger_layout_change_fn)
      when display_col < length(state.columns) - 1 do
    widths = get_column_widths(state, state.width)
    col_order = get_col_order_list(state)
    new_col_order = swap_in_list(col_order, display_col, display_col + 1)
    new_col_widths = swap_in_list(widths, display_col, display_col + 1)

    new_state = %{
      state
      | _col_order: new_col_order,
        _col_widths: new_col_widths,
        cursor_col: display_col + 1
    }

    trigger_layout_change_fn.(new_state)
    {:ok, new_state, [:render_update]}
  end

  def reorder_column(state, _display_col, :right, _trigger_layout_change_fn), do: {:ok, state}

  def swap_in_list(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end
end
