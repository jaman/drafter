defmodule Drafter.Widget.DataTable.Sorting do
  @moduledoc false

  def sort_data(data, column_key, direction) do
    sorted =
      Enum.sort_by(data, fn row ->
        Map.get(row, column_key, "")
      end)

    if direction == :desc do
      Enum.reverse(sorted)
    else
      sorted
    end
  end

  def cycle_sort(state, column_key) do
    cond do
      state.sort_column != column_key ->
        {:asc, sort_data(state._unsorted_data, column_key, :asc), column_key}

      state.sort_direction == :asc ->
        {:desc, sort_data(state._unsorted_data, column_key, :desc), column_key}

      true ->
        {:asc, state._unsorted_data, nil}
    end
  end

  def apply_sort(state, column, col_index, trigger_sort_fn) do
    {new_direction, new_data, new_sort_col} = cycle_sort(state, column.key)

    new_state = %{
      state
      | data: new_data,
        sort_column: new_sort_col,
        sort_direction: new_direction,
        cursor_col: col_index
    }

    trigger_sort_fn.(new_state)
    {:ok, new_state}
  end

  def trigger_sort(state) do
    if state.callbacks.on_sort do
      try do
        state.callbacks.on_sort.(state.sort_column, state.sort_direction)
      rescue
        _error -> :ok
      end
    end
  end
end
