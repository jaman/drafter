defmodule Drafter.Widget.Callback do
  defp dispatch(session_pid, name, data) do
    case Drafter.ScreenManager.get_active_screen() do
      nil -> send(session_pid, {:app_event, name, data})
      _screen -> send(session_pid, {:tui_event, {:app_callback, name, data}})
    end
  end

  def wrap_0(nil), do: nil
  def wrap_0(f) when is_function(f, 0), do: f
  def wrap_0(name) do
    session_pid = self()
    fn -> dispatch(session_pid, name, nil) end
  end

  def wrap_1(nil), do: nil
  def wrap_1(f) when is_function(f, 1), do: f
  def wrap_1(name) do
    session_pid = self()
    fn data -> dispatch(session_pid, name, data) end
  end

  def wrap_2(nil), do: nil
  def wrap_2(f) when is_function(f, 2), do: f
  def wrap_2(name) do
    session_pid = self()
    fn a, b -> dispatch(session_pid, name, {a, b}) end
  end
end
