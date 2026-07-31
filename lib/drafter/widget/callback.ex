defmodule Drafter.Widget.Callback do
  @moduledoc """
  Wraps atom event names or functions into closures for widget callback wiring.

  `wrap_0/1`, `wrap_1/1`, and `wrap_2/1` each accept `nil`, a bare function of
  the matching arity, or an atom name. When given an atom, the returned closure
  dispatches the event to the app loop as `{:app_event, name, data}` when no
  modal screen is active, or as `{:tui_event, {:app_callback, name, data}}`
  when a modal is on top.
  """
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

  def wrap_1_with_pid(nil, _pid), do: nil
  def wrap_1_with_pid(f, _pid) when is_function(f, 1), do: f

  def wrap_1_with_pid(name, session_pid) do
    fn data -> dispatch(session_pid, name, data) end
  end

  def wrap_2(nil), do: nil
  def wrap_2(f) when is_function(f, 2), do: f

  def wrap_2(name) do
    session_pid = self()
    fn a, b -> dispatch(session_pid, name, {a, b}) end
  end
end
