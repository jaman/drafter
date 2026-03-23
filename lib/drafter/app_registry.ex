defmodule Drafter.AppRegistry do
  @moduledoc """
  Session-scoped registration for the active app loop process.

  Replaces the global `:tui_app_loop` atom with a named ETS-backed lookup
  keyed by the calling process's group leader, preparing the foundation for
  true multi-session support.

  For the current single-session implementation the table always holds at
  most one entry; the multi-session architecture will extend this with proper
  session-id scoping.
  """

  @table :drafter_app_registry

  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set])
        :ok

      _ ->
        :ok
    end
  end

  @spec register() :: true
  def register do
    ensure_table()
    :ets.insert(@table, {:app_loop, self()})
  end

  @spec unregister() :: true
  def unregister do
    ensure_table()
    :ets.delete(@table, :app_loop)
  end

  @spec whereis() :: pid() | nil
  def whereis do
    @table
    |> :ets.whereis()
    |> lookup_app_pid()
  end

  defp lookup_app_pid(:undefined), do: nil
  defp lookup_app_pid(_) do
    @table
    |> :ets.lookup(:app_loop)
    |> resolve_pid()
  end

  defp resolve_pid([{:app_loop, pid}]) when is_pid(pid), do: alive_or_nil(pid)
  defp resolve_pid(_), do: nil

  defp alive_or_nil(pid) do
    if Process.alive?(pid), do: pid, else: nil
  end

  @spec send_to_loop(term()) :: term()
  def send_to_loop(message) do
    case whereis() do
      nil -> message
      pid -> send(pid, message)
    end
  end

  @spec set_frame_interval(pos_integer() | nil) :: true
  def set_frame_interval(ms) do
    ensure_table()
    :ets.insert(@table, {:frame_interval, ms})
  end

  @spec get_frame_interval() :: pos_integer() | nil
  def get_frame_interval do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@table, :frame_interval) do
          [{:frame_interval, ms}] -> ms
          _ -> nil
        end
    end
  end
end
