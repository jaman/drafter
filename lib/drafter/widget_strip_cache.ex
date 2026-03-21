defmodule Drafter.WidgetStripCache do
  @moduledoc false

  @table :drafter_widget_strips

  @spec create() :: :ok
  def create do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
      _ ->
        :ok
    end

    :ok
  end

  @spec put(term(), map(), list()) :: true
  def put(widget_id, rect, strips) do
    :ets.insert(@table, {widget_id, rect, strips})
  end

  @spec get(term()) :: {map(), list()} | nil
  def get(widget_id) do
    case :ets.lookup(@table, widget_id) do
      [{^widget_id, rect, strips}] -> {rect, strips}
      [] -> nil
    end
  end

  @spec delete(term()) :: true
  def delete(widget_id) do
    :ets.delete(@table, widget_id)
  end

  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ ->
        :ets.delete_all_objects(@table)
        :ok
    end
  end
end
