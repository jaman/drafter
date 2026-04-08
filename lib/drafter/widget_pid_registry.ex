defmodule Drafter.WidgetPidRegistry do
  @moduledoc false

  @table :drafter_widget_pids

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

  @spec register(term(), pid()) :: :ok
  def register(widget_id, pid) do
    create()
    :ets.insert(@table, {widget_id, pid})
    :ok
  end

  @spec lookup(term()) :: pid() | nil
  def lookup(widget_id) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@table, widget_id) do
          [{^widget_id, pid}] -> pid
          [] -> nil
        end
    end
  end

  @spec unregister(term()) :: :ok
  def unregister(widget_id) do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table, widget_id)
    end

    :ok
  end

  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end

    :ok
  end
end
