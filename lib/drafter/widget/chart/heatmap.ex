defmodule Drafter.Widget.Chart.Heatmap do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Shared

  @spec render(map(), pos_integer(), pos_integer(), tuple(), tuple()) :: [Strip.t()]
  def render(state, width, height, bg, _fg) do
    matrix = state.data

    if matrix == [] or not is_list(hd(matrix)) do
      Shared.empty_strips(height, bg)
    else
      render_heatmap(matrix, width, height, bg, state)
    end
  end

  defp render_heatmap(matrix, width, height, default_bg, state) do
    {min_val, max_val} = value_range(matrix, state)
    num_rows = length(matrix)
    num_cols = matrix |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    row_mapping = map_indices(num_rows, height)
    col_mapping = map_indices(num_cols, width)

    indexed_matrix = index_matrix(matrix)

    Enum.map(0..(height - 1), fn term_row ->
      segments =
        Enum.map(0..(width - 1), fn term_col ->
          data_rows = Enum.at(row_mapping, term_row, [])
          data_cols = Enum.at(col_mapping, term_col, [])
          avg = aggregate_cells(indexed_matrix, data_rows, data_cols)
          color = value_to_color(avg, min_val, max_val, default_bg)
          Segment.new(" ", %{bg: color})
        end)

      Strip.new(segments)
    end)
  end

  defp value_range(matrix, state) do
    flat = List.flatten(matrix) |> Enum.filter(&is_number/1)

    data_min = if flat == [], do: 0, else: Enum.min(flat)
    data_max = if flat == [], do: 1, else: Enum.max(flat)

    min_val = if is_number(state.min_value), do: state.min_value, else: data_min
    max_val = if is_number(state.max_value), do: state.max_value, else: data_max

    if min_val == max_val, do: {min_val - 1, max_val + 1}, else: {min_val, max_val}
  end

  defp map_indices(data_count, terminal_count) when data_count == 0 do
    List.duplicate([], terminal_count)
  end

  defp map_indices(data_count, terminal_count) do
    Enum.map(0..(terminal_count - 1), fn term_idx ->
      start_f = term_idx * data_count / terminal_count
      end_f = (term_idx + 1) * data_count / terminal_count
      start_i = trunc(start_f)
      end_i = max(start_i + 1, trunc(end_f))
      Enum.to_list(start_i..min(end_i - 1, data_count - 1))
    end)
  end

  defp index_matrix(matrix) do
    matrix
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {row, ri}, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {val, ci}, inner_acc ->
        Map.put(inner_acc, {ri, ci}, val)
      end)
    end)
  end

  defp aggregate_cells(_indexed, [], _cols), do: nil
  defp aggregate_cells(_indexed, _rows, []), do: nil

  defp aggregate_cells(indexed, rows, cols) do
    values =
      for r <- rows, c <- cols, reduce: [] do
        acc ->
          case Map.get(indexed, {r, c}) do
            nil -> acc
            val when is_number(val) -> [val | acc]
            _ -> acc
          end
      end

    case values do
      [] -> nil
      vals -> Enum.sum(vals) / length(vals)
    end
  end

  defp value_to_color(nil, _min, _max, default_bg), do: default_bg

  defp value_to_color(value, min_val, max_val, _default_bg) do
    range = max_val - min_val
    t = (value - min_val) / range |> max(0.0) |> min(1.0)
    gradient_color(t)
  end

  defp gradient_color(t) when t < 0.2 do
    f = t / 0.2
    lerp_color({0, 0, 40}, {0, 0, 180}, f)
  end

  defp gradient_color(t) when t < 0.4 do
    f = (t - 0.2) / 0.2
    lerp_color({0, 0, 180}, {0, 180, 80}, f)
  end

  defp gradient_color(t) when t < 0.6 do
    f = (t - 0.4) / 0.2
    lerp_color({0, 180, 80}, {220, 220, 0}, f)
  end

  defp gradient_color(t) when t < 0.8 do
    f = (t - 0.6) / 0.2
    lerp_color({220, 220, 0}, {255, 80, 0}, f)
  end

  defp gradient_color(t) do
    f = (t - 0.8) / 0.2
    lerp_color({255, 80, 0}, {255, 255, 255}, f)
  end

  defp lerp_color({r1, g1, b1}, {r2, g2, b2}, f) do
    {
      round(r1 + (r2 - r1) * f),
      round(g1 + (g2 - g1) * f),
      round(b1 + (b2 - b1) * f)
    }
  end
end
