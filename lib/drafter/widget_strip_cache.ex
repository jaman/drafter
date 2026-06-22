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
  rescue
    ArgumentError -> :ok
  end

  @spec put(term(), map(), list()) :: true
  def put(widget_id, rect, strips) do
    :ets.insert(@table, {session_key(widget_id), rect, strips})
  end

  @spec get(term()) :: {map(), list()} | nil
  def get(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@table, key) do
      [{^key, rect, strips}] -> {rect, strips}
      [] -> nil
    end
  end

  @spec delete(term()) :: true
  def delete(widget_id) do
    :ets.delete(@table, session_key(widget_id))
  end

  @spec clear() :: :ok
  def clear do
    session = session_id()

    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.select_delete(@table, [{{:"$1", :_, :_}, [match_session(session)], [true]}])
        :ok
    end
  end

  defp session_key(widget_id), do: {session_id(), widget_id}

  defp session_id, do: Process.get(:drafter_compositor, self())

  defp match_session(session) do
    {:==, {:element, 1, :"$1"}, {:const, session}}
  end
end
