defmodule Drafter.AppRegistry do
  @moduledoc """
  Registry of running application loops, keyed by session.

  A loop registers itself under its session id — the compositor pid held in the
  calling process's dictionary — so concurrent sessions do not collide.

  `whereis/0` resolves the caller's own session. A caller with no session id gets
  the sole registered loop, or `nil` when several are running. Pass an id from
  `current_session/0` to `whereis/1` or `send_to_loop/2` to name a loop from a
  process that sits outside any session.

  Also holds the render frame interval, which per-widget render processes read to
  throttle themselves to the application's frame rate.
  """

  require Logger

  @table :drafter_app_registry
  @ambiguity_warned {__MODULE__, :ambiguity_warned}

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
      _ -> resolve_loop(session_key())
    end
  end

  @doc """
  The live loop registered for `session`, or `nil`.

  `session` is an id from `current_session/0`. Falls back to the sole registered
  loop when `session` has none of its own.
  """
  @spec whereis(term()) :: pid() | nil
  def whereis(session) do
    case :ets.whereis(@table) do
      :undefined -> nil
      _ -> resolve_loop(session)
    end
  end

  @doc "The calling process's session id, for later use with `whereis/1`."
  @spec current_session() :: term()
  def current_session, do: session_key()

  @doc """
  Sends a message to the loop resolved by `whereis/0`.

  Returns `:ok`, or `{:error, :no_loop}` when no loop resolved.
  """
  @spec send_to_loop(term()) :: :ok | {:error, :no_loop}
  def send_to_loop(message) do
    deliver(whereis(), message)
  end

  @doc """
  Sends a message to `session`'s loop.

  Returns `:ok`, or `{:error, :no_loop}` when that session has no loop.
  """
  @spec send_to_loop(term(), term()) :: :ok | {:error, :no_loop}
  def send_to_loop(session, message) do
    deliver(whereis(session), message)
  end

  defp deliver(nil, _message), do: {:error, :no_loop}

  defp deliver(pid, message) do
    send(pid, message)
    :ok
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

  defp resolve_loop(session) do
    case :ets.lookup(@table, {:loop, session}) do
      [{_, pid}] -> alive_or_nil(pid)
      [] -> sole_loop()
    end
  end

  defp sole_loop do
    case live_loops() do
      [pid] -> pid
      [] -> nil
      several -> warn_ambiguous(length(several))
    end
  end

  defp warn_ambiguous(count) do
    unless :persistent_term.get(@ambiguity_warned, false) do
      :persistent_term.put(@ambiguity_warned, true)

      Logger.warning("""
      Drafter.AppRegistry: a process with no session identity asked for "the" \
      application loop while #{count} are running, so the message was dropped.

      A caller inside a session resolves its own loop. This one has no \
      :drafter_compositor in its process dictionary, and the single-loop fallback \
      cannot choose between #{count} of them.

      Capture Drafter.AppRegistry.current_session/0 inside the session and pass it \
      to send_to_loop/2 or whereis/1. This is logged once per node.\
      """)
    end

    nil
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
