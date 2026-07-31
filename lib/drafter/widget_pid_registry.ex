defmodule Drafter.WidgetPidRegistry do
  @moduledoc """
  Maps widget ids to their server processes, scoped to the owning session.

  Keys are qualified by the session, identified by its compositor, so the same
  widget id used by concurrent sessions resolves within the caller's own session.
  """

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
  rescue
    ArgumentError -> :ok
  end

  @spec register(term(), pid()) :: :ok
  def register(widget_id, pid) do
    create()
    :ets.insert(@table, {session_key(widget_id), pid})
    :ok
  end

  @spec lookup(term()) :: pid() | nil
  def lookup(widget_id) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ ->
        key = session_key(widget_id)

        case :ets.lookup(@table, key) do
          [{^key, pid}] -> pid
          [] -> nil
        end
    end
  end

  @spec unregister(term()) :: :ok
  def unregister(widget_id) do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table, session_key(widget_id))
    end

    :ok
  end

  @doc "Drop every registration belonging to the calling session."
  @spec clear_session() :: :ok
  def clear_session do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        session = session_id()
        match = {{:"$1", :_}, [{:==, {:element, 1, :"$1"}, {:const, session}}], [true]}
        :ets.select_delete(@table, [match])
        :ok
    end
  end

  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp session_key(widget_id), do: {session_id(), widget_id}

  defp session_id, do: Process.get(:drafter_compositor)
end
