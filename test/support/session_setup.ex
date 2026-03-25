defmodule Drafter.Test.SessionSetup do
  @moduledoc false

  def setup_session_pdict(_context \\ %{}) do
    tm_pid = ensure_started(Drafter.ThemeManager.start_link(name: nil))
    eh_pid = ensure_started(Drafter.EventHandler.start_link(name: nil))
    sm_pid = ensure_started(Drafter.ScreenManager.start_link(name: nil, event_handler: eh_pid))

    Process.put(:drafter_theme_manager, tm_pid)
    Process.put(:drafter_screen_manager, sm_pid)
    Process.put(:drafter_event_handler, eh_pid)

    on_exit_pids = [tm_pid, sm_pid, eh_pid]

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(on_exit_pids, &stop_if_alive/1)
    end)

    :ok
  end

  defp ensure_started({:ok, pid}), do: pid
  defp ensure_started({:error, {:already_started, pid}}), do: pid

  defp stop_if_alive(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end
end
