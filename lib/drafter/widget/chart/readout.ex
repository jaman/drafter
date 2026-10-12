defmodule Drafter.Widget.Chart.Readout do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}

  @readout_types [:line, :braille, :step, :area, :braille_area, :stacked_area]
  @marker_bg {70, 70, 95}
  @default_colors [{100, 200, 255}]

  @type box :: %{
          dx: non_neg_integer(),
          dy: non_neg_integer(),
          cols: pos_integer(),
          rows: pos_integer()
        }

  def readout_type?(chart_type), do: chart_type in @readout_types

  def index(state, box, mode) do
    with x when is_integer(x) <- Map.get(state._internal, :cursor_x),
         true <- readout_type?(state.chart_type),
         true <- x >= box.dx and x < box.dx + box.cols,
         [_ | _] = series <- series(state.data) do
      longest = series |> Enum.map(&length/1) |> Enum.max()
      data_index(state, mode, x - box.dx, box.cols, longest)
    else
      _ -> nil
    end
  end

  def decorate(strips, _state, _box, nil, _fg), do: strips

  def decorate(strips, state, box, index, fg) do
    x = Map.fetch!(state._internal, :cursor_x)

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, row} -> decorate_row(strip, row, x, box) end)
    |> put_readout(readout_strip(state, index, fg), title_width(state))
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

  defp put_readout([], _readout, _title_width), do: []

  defp put_readout([first | rest], readout, title_width) do
    {title, after_title} = Strip.divide(first, title_width)
    {_covered, uncovered} = Strip.divide(after_title, readout.width)
    [title |> Strip.combine(readout) |> Strip.combine(uncovered) | rest]
  end

  defp title_width(%{title: title}) when is_binary(title) and title != "",
    do: String.length(title) + 1

  defp title_width(_state), do: 0

  defp readout_strip(state, index, fg) do
    colors =
      if state.colors == [], do: [state.color || fg || hd(@default_colors)], else: state.colors

    values =
      state.data
      |> series()
      |> Enum.with_index()
      |> Enum.flat_map(fn {values, si} ->
        value_segments(Enum.at(values, index), Enum.at(colors, rem(si, length(colors))))
      end)

    Strip.new([Segment.new(" #{x_label(state, index)} ", %{bold: true, bg: @marker_bg}) | values])
  end

  defp value_segments(nil, _color), do: []

  defp value_segments(value, color) do
    [
      Segment.new(" ■", %{fg: color, bg: @marker_bg}),
      Segment.new(" #{format(value)} ", %{bg: @marker_bg})
    ]
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

  defp data_index(_state, mode, col, cols, longest) when mode != :text do
    round(col / max(cols - 1, 1) * (longest - 1))
  end

  defp data_index(%{chart_type: :braille_area}, :text, col, cols, longest) do
    dot = col * 2
    dots = cols * 2

    cond do
      longest > dots -> round(dot / max(dots - 1, 1) * (longest - 1))
      dot < longest -> dot
      true -> nil
    end
  end

  defp data_index(%{data: [first | _], _internal: %{raw_data: true}}, :text, col, cols, longest)
       when is_list(first) do
    index = round(col * 2 * longest / (cols * 2))
    if index < longest, do: index
  end

  defp data_index(state, :text, col, cols, longest) do
    scroll = state._internal.scroll_offset || 0
    end_index = longest - scroll
    start = max(0, end_index - cols * 2)
    dot = col * 2
    if dot < end_index - start, do: start + dot
  end

  defp series([first | _] = data) when is_number(first) or is_tuple(first), do: [values(data)]

  defp series([first | _] = data) when is_list(first),
    do: for(list <- data, is_list(list), do: values(list))

  defp series(_data), do: []

  defp values(list) do
    for item <- list, value = value(item), value != nil, do: value
  end

  defp value(n) when is_number(n), do: n
  defp value({n, _weight}) when is_number(n), do: n
  defp value(_other), do: nil
end
