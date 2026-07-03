defmodule Drafter.WidgetStripCache do
  @moduledoc false

  @table :drafter_widget_strips
  @visible_table :drafter_widget_visible

  @spec create() :: :ok
  def create do
    ensure_table(@table)
    ensure_table(@visible_table)
    :ok
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set, {:read_concurrency, true}])
      _ -> :ok
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

  @spec mark_visible(term(), boolean()) :: true
  def mark_visible(widget_id, visible?) do
    :ets.insert(@visible_table, {session_key(widget_id), visible?})
  rescue
    ArgumentError -> true
  end

  @spec visible?(term()) :: boolean()
  def visible?(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@visible_table, key) do
      [{^key, visible?}] -> visible?
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  @spec clear() :: :ok
  def clear do
    session = session_id()
    clear_session(@table, {{:"$1", :_, :_}, [match_session(session)], [true]})
    clear_session(@visible_table, {{:"$1", :_}, [match_session(session)], [true]})
    :ok
  end

  defp clear_session(table, match_spec) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.select_delete(table, [match_spec])
    end
  end

  defp session_key(widget_id), do: {session_id(), widget_id}

  defp session_id, do: Process.get(:drafter_compositor, self())

  defp match_session(session) do
    {:==, {:element, 1, :"$1"}, {:const, session}}
  end
end
