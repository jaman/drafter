defmodule Drafter.Transport.SSH.Sessions do
  @moduledoc """
  The ssh sessions each ssh server runs, so a server stopping can end them cleanly.

  A server started by `Drafter.Server.start_ssh/2` is a listener: a reference
  its daemons are recorded under (`listen/2`). Each session's shell process joins its
  listener with its terminal driver (`join/2`). `close/2` ends every session of a
  daemon's listener: each client's terminal is restored, shown the notice and its
  channel closed by the shell's ordinary exit, before the caller stops the daemon.
  """

  require Logger

  alias Drafter.Transport.SSHDriver

  @registry __MODULE__
  @listeners Drafter.Transport.SSH.Listeners
  @end_ms 3_000

  @doc "The registry of sessions by listener, for the application's supervision tree."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc "Create the table of daemons by listener. Nothing when it exists."
  @spec create() :: :ok
  def create do
    if :ets.whereis(@listeners) == :undefined,
      do: :ets.new(@listeners, [:set, :public, :named_table])

    :ok
  end

  @doc "Record `daemons` as serving `listener`."
  @spec listen(pid() | [pid()], reference()) :: :ok
  def listen(daemons, listener) do
    daemons |> List.wrap() |> Enum.each(&:ets.insert(@listeners, {&1, listener}))
  end

  @doc "Record the calling shell process, with its terminal `driver`, as a session of `listener`."
  @spec join(reference(), pid()) :: :ok
  def join(listener, driver) do
    {:ok, _owner} = Registry.register(@registry, listener, driver)
    :ok
  end

  @doc """
  End every session of the listener `daemon` serves, showing each client `notice`,
  and forget the daemon. Returns once the sessions have exited; one still running
  after #{@end_ms} ms is killed, with a warning logged saying where it was.
  """
  @spec close(pid(), String.t()) :: :ok
  def close(daemon, notice) do
    case :ets.take(@listeners, daemon) do
      [{^daemon, listener}] -> end_sessions(listener, notice)
      [] -> :ok
    end
  end

  @doc "End every session of every listener, showing each client `notice`, and forget every daemon."
  @spec close_all(String.t()) :: :ok
  def close_all(notice) do
    if :ets.whereis(@listeners) != :undefined do
      @listeners
      |> :ets.tab2list()
      |> Enum.flat_map(fn {daemon, _listener} -> :ets.take(@listeners, daemon) end)
      |> Enum.map(fn {_daemon, listener} -> listener end)
      |> Enum.uniq()
      |> Enum.each(&end_sessions(&1, notice))
    end

    :ok
  end

  defp end_sessions(listener, notice) do
    deadline = System.monotonic_time(:millisecond) + @end_ms

    @registry
    |> Registry.lookup(listener)
    |> Enum.map(fn {shell, driver} -> ending(shell, driver, notice) end)
    |> Enum.each(&await_end(&1, deadline))
  end

  defp ending(shell, driver, notice) do
    finish(driver, notice)
    monitor = Process.monitor(shell)
    send(shell, :drafter_end_session)
    {shell, monitor}
  end

  defp finish(driver, notice) do
    SSHDriver.finish(driver, notice)
  catch
    :exit, _gone -> :ok
  end

  defp await_end({shell, monitor}, deadline) do
    receive do
      {:DOWN, ^monitor, :process, ^shell, _reason} -> :ok
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        Logger.warning(
          "ssh session #{inspect(shell)} did not end in #{@end_ms} ms and is killed; it was at #{inspect(Process.info(shell, :current_stacktrace))}"
        )

        Process.exit(shell, :kill)
        receive do: ({:DOWN, ^monitor, :process, ^shell, _reason} -> :ok)
    end
  end
end
