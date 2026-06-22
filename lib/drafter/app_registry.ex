defmodule Drafter.AppRegistry do
  @moduledoc """
  Session-scoped registration for active app-loop processes.

  Each session registers its loop under its compositor pid — the session id present in
  the session process dictionary — so concurrent sessions never collide on a single
  global key. A caller running inside a session resolves its own loop directly; a caller
  with no session context (e.g. external introspection of a single-session app) falls
  back to the sole registered loop, keeping the common single-session case plumbing-free.

  The render frame interval is also tracked here, read by per-widget render processes to
  throttle their own re-renders to the app's frame rate.
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
  rescue
    ArgumentError -> :ok
  end

  @spec register() :: true
  def register do
    ensure_table()
    :ets.insert(@table, {{:loop, session_key()}, self()})
  end

  @spec unregister() :: true
  def unregister do
    ensure_table()
    :ets.delete(@table, {:loop, session_key()})
  end

  @spec whereis() :: pid() | nil
  def whereis do
    case :ets.whereis(@table) do
      :undefined -> nil
      _ -> resolve_loop()
    end
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

  defp session_key, do: Process.get(:drafter_compositor)

  defp resolve_loop do
    case :ets.lookup(@table, {:loop, session_key()}) do
      [{_, pid}] -> alive_or_nil(pid)
      [] -> sole_loop()
    end
  end

  defp sole_loop do
    case live_loops() do
      [pid] -> pid
      _ -> nil
    end
  end

  defp live_loops do
    @table
    |> :ets.match({{:loop, :_}, :"$1"})
    |> List.flatten()
    |> Enum.filter(&Process.alive?/1)
  end

  defp alive_or_nil(pid) do
    if Process.alive?(pid), do: pid, else: nil
  end
end
