defmodule Drafter.Widget.Chart.Readout do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}

  @line_types [:line, :braille, :step, :area, :braille_area, :stacked_area]
  @bar_types [:bar, :clustered_bar, :stacked_bar, :range_bar]
  @readout_types @line_types ++ @bar_types
  @marker_bg {70, 70, 95}
  @default_colors [{100, 200, 255}]

  @type box :: %{
          dx: non_neg_integer(),
          dy: non_neg_integer(),
          cols: pos_integer(),
          rows: pos_integer()
        }

  def readout_type?(chart_type), do: chart_type in @readout_types

  def index(state, box) do
    with true <- readout_type?(state.chart_type),
         {:ok, offset, span} <- pointer(state, box),
         [_ | _] = series <- series(state),
         shown when shown > 0 <- shown_length(series, state) do
      position(state.chart_type, offset, span, shown)
    else
      _ -> nil
    end
  end

  defp pointer(state, box) do
    x = Map.get(state._internal, :cursor_x)
    y = Map.get(state._internal, :cursor_y)

    cond do
      not (is_integer(x) and x >= box.dx and x < box.dx + box.cols) -> :outside
      not horizontal_bars?(state) -> {:ok, x - box.dx, box.cols}
      is_integer(y) and y >= box.dy and y < box.dy + box.rows -> {:ok, y - box.dy, box.rows}
      true -> :outside
    end
  end

  defp horizontal_bars?(state),
    do: state.chart_type in @bar_types and state.orientation == :horizontal

  defp position(type, offset, span, shown) when type in @bar_types do
    visible = min(shown, span)
    shown - visible + min(visible - 1, div(offset * visible, span))
  end

  defp position(_type, offset, span, shown),
    do: round(offset / max(span - 1, 1) * (shown - 1))

  def decorate(strips, _state, _box, nil, _fg), do: strips

  def decorate(strips, state, box, index, fg) do
    x = Map.fetch!(state._internal, :cursor_x)

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, row} -> decorate_row(strip, row, x, box) end)
    |> put_tooltip(tooltip(state, index, fg, box), x, box)
  end

  def image_overlay(_state, _box, nil, _fg), do: {nil, []}

  def image_overlay(state, box, index, fg) do
    col = Map.fetch!(state._internal, :cursor_x) - box.dx
    lines = tooltip(state, index, fg, box)
    left = tooltip_left(lines, col + box.dx, box) - box.dx

    cells =
      for {strip, row} <- Enum.with_index(lines),
          {char, offset, style} <- strip_cells(strip),
          do: {left + offset, row, char, rgba(style[:fg]), rgba(style[:bg])}

    {{col, @marker_bg}, cells}
  end

  defp strip_cells(strip) do
    strip.segments
    |> Enum.flat_map(fn segment ->
      segment.text |> String.graphemes() |> Enum.map(&{&1, segment.style})
    end)
    |> Enum.with_index()
    |> Enum.map(fn {{char, style}, offset} -> {char, offset, style} end)
  end

  defp rgba({r, g, b}), do: {r, g, b, 255}
  defp rgba(_other), do: nil

  defp shown_length(series, state) do
    longest = series |> Enum.map(&length/1) |> Enum.max()
    longest - min(Map.get(state._internal, :scroll_offset) || 0, longest - 1)
  end

  @tooltip_bg {28, 30, 38}
  @tooltip_border {90, 90, 110}
  @tooltip_text {220, 220, 230}

  defp tooltip(state, index, fg, box) do
    rows =
      state
      |> readings(index, fg)
      |> sort_readings(Map.get(state._internal, :readout_sort, :none))

    header = x_label(state, index)
    name_width = rows |> Enum.map(&String.length(elem(&1, 0))) |> Enum.max(fn -> 0 end)
    value_width = rows |> Enum.map(&String.length(elem(&1, 1))) |> Enum.max(fn -> 0 end)

    inner =
      max(String.length(header) + 2, 6 + name_width + value_width) |> min(max(box.cols - 2, 8))

    room = max(box.rows - 3, 1)
    shown = if length(rows) > room, do: Enum.take(rows, max(room - 1, 0)), else: rows
    hidden = length(rows) - length(shown)

    lines =
      [header_line(header, inner)] ++
        Enum.map(shown, &reading_line(&1, inner, value_width)) ++
        more_line(hidden, inner)

    framed_tooltip(lines, inner)
  end

  defp readings(state, index, fg) do
    names = Map.get(state._internal, :series_names, [])
    formatter = Map.get(state._internal, :readout_format) || (&format/1)

    colors =
      if state.colors == [], do: [state.color || fg || hd(@default_colors)], else: state.colors

    state
    |> series()
    |> Enum.with_index()
    |> Enum.flat_map(fn {values, si} ->
      case Enum.at(values, index) do
        nil ->
          []

        value ->
          [
            {series_name(names, si), text(value, formatter),
             Enum.at(colors, rem(si, length(colors))), sort_key(value)}
          ]
      end
    end)
  end

  defp text({:range, low, high}, formatter), do: formatter.(low) <> " – " <> formatter.(high)
  defp text(value, formatter), do: formatter.(value)

  defp sort_key({:range, _low, high}), do: high
  defp sort_key(value), do: value

  defp series_name(names, si) do
    case Enum.at(names, si) do
      nil -> "series #{si + 1}"
      name -> to_string(name)
    end
  end

  defp sort_readings(rows, :desc), do: Enum.sort_by(rows, &elem(&1, 3), :desc)
  defp sort_readings(rows, :asc), do: Enum.sort_by(rows, &elem(&1, 3), :asc)
  defp sort_readings(rows, _none), do: rows

  defp header_line(header, inner) do
    [
      Segment.new(String.pad_trailing(" " <> String.slice(header, 0, inner - 1), inner), %{
        fg: @tooltip_text,
        bg: @tooltip_bg,
        bold: true
      })
    ]
  end

  defp reading_line({name, value, color, _raw}, inner, value_width) do
    name_room = max(inner - value_width - 6, 1)
    shown_name = name |> String.slice(0, name_room) |> String.pad_trailing(name_room)

    [
      Segment.new(" ■ ", %{fg: color, bg: @tooltip_bg}),
      Segment.new(shown_name, %{fg: @tooltip_text, bg: @tooltip_bg}),
      Segment.new("  " <> String.pad_leading(value, value_width) <> " ", %{
        fg: @tooltip_text,
        bg: @tooltip_bg,
        bold: true
      })
    ]
  end

  defp more_line(0, _inner), do: []

  defp more_line(hidden, inner) do
    [
      [
        Segment.new(String.pad_trailing(" … #{hidden} more", inner), %{
          fg: @tooltip_border,
          bg: @tooltip_bg
        })
      ]
    ]
  end

  defp framed_tooltip(lines, inner) do
    edge = %{fg: @tooltip_border, bg: @tooltip_bg}
    top = Strip.new([Segment.new("╭" <> String.duplicate("─", inner) <> "╮", edge)])
    bottom = Strip.new([Segment.new("╰" <> String.duplicate("─", inner) <> "╯", edge)])

    middle =
      Enum.map(lines, fn segments ->
        Strip.new([Segment.new("│", edge)] ++ segments ++ [Segment.new("│", edge)])
      end)

    [top | middle] ++ [bottom]
  end

  defp tooltip_left(tooltip, x, box) do
    width = tooltip |> hd() |> Map.fetch!(:width)
    if x + 2 + width <= box.dx + box.cols, do: x + 2, else: max(box.dx, x - 1 - width)
  end

  defp put_tooltip(strips, tooltip, x, box) do
    left = tooltip_left(tooltip, x, box)
    top = box.dy

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, row} ->
      case Enum.at(tooltip, row - top) do
        line when row >= top and line != nil -> overlay(strip, left, line)
        _ -> strip
      end
    end)
  end

  defp overlay(strip, left, line) do
    {before, rest} = Strip.divide(strip, left)
    {_covered, after_line} = Strip.divide(rest, line.width)
    before |> Strip.combine(line) |> Strip.combine(after_line)
  end

  defp decorate_row(strip, row, x, box) when row >= box.dy and row < box.dy + box.rows,
    do: mark_column(strip, x)

  defp decorate_row(strip, _row, _x, _box), do: strip

  defp mark_column(strip, x) do
    {left, rest} = Strip.divide(strip, x)
    {cell, right} = Strip.divide(rest, 1)

    left
    |> Strip.combine(Strip.apply_style(cell, %{bg: @marker_bg}))
    |> Strip.combine(right)
  end

  defp x_label(%{chart_type: type, bar_labels: [_ | _] = labels} = state, index)
       when type in @bar_types do
    case Enum.at(labels, index) do
      nil -> x_label(%{state | bar_labels: []}, index)
      label -> to_string(label)
    end
  end

  defp x_label(%{x_labels: labels}, index) when is_list(labels) and labels != [] do
    case Enum.at(labels, index) do
      nil -> "##{index}"
      label -> to_string(label)
    end
  end

  defp x_label(_state, index), do: "##{index}"

  defp format(value) when is_integer(value), do: Integer.to_string(value)

  defp format(value) when abs(value) >= 1000,
    do: :erlang.float_to_binary(value * 1.0, decimals: 0)

  defp format(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)

  defp series(%{chart_type: :range_bar, data: [_ | _] = data}), do: [Enum.map(data, &range/1)]
  defp series(%{data: data}), do: series_of(data)

  defp series_of([first | _] = data) when is_list(first),
    do: for(list <- data, is_list(list), do: values(list))

  defp series_of([_ | _] = data), do: [values(data)]
  defp series_of(_data), do: []

  defp range([low, high]) when is_number(low) and is_number(high), do: {:range, low, high}
  defp range({low, high}) when is_number(low) and is_number(high), do: {:range, low, high}
  defp range(_other), do: nil

  defp values(list), do: Enum.map(list, &value/1)

  defp value(n) when is_number(n), do: n
  defp value({n, _weight}) when is_number(n), do: n
  defp value(_other), do: nil
end
