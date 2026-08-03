defmodule Drafter.Regression.SessionIsolationTest do
  use ExUnit.Case, async: false

  alias Drafter.WidgetPidRegistry

  setup do
    WidgetPidRegistry.create()
    WidgetPidRegistry.clear()
    :ok
  end

  defp in_session(session_pid, fun) do
    task =
      Task.async(fn ->
        Process.put(:drafter_compositor, session_pid)
        fun.()
      end)

    Task.await(task)
  end

  test "the same widget id in two sessions resolves to each session's own widget" do
    session_a = spawn(fn -> Process.sleep(:infinity) end)
    session_b = spawn(fn -> Process.sleep(:infinity) end)
    widget_a = spawn(fn -> Process.sleep(:infinity) end)
    widget_b = spawn(fn -> Process.sleep(:infinity) end)

    in_session(session_a, fn -> WidgetPidRegistry.register(:query_editor, widget_a) end)
    in_session(session_b, fn -> WidgetPidRegistry.register(:query_editor, widget_b) end)

    assert in_session(session_a, fn -> WidgetPidRegistry.lookup(:query_editor) end) == widget_a
    assert in_session(session_b, fn -> WidgetPidRegistry.lookup(:query_editor) end) == widget_b

    Enum.each([session_a, session_b, widget_a, widget_b], &Process.exit(&1, :kill))
  end

  test "unregistering in one session leaves the other session intact" do
    session_a = spawn(fn -> Process.sleep(:infinity) end)
    session_b = spawn(fn -> Process.sleep(:infinity) end)
    widget_a = spawn(fn -> Process.sleep(:infinity) end)
    widget_b = spawn(fn -> Process.sleep(:infinity) end)

    in_session(session_a, fn -> WidgetPidRegistry.register(:shared_name, widget_a) end)
    in_session(session_b, fn -> WidgetPidRegistry.register(:shared_name, widget_b) end)
    in_session(session_a, fn -> WidgetPidRegistry.unregister(:shared_name) end)

    assert in_session(session_a, fn -> WidgetPidRegistry.lookup(:shared_name) end) == nil
    assert in_session(session_b, fn -> WidgetPidRegistry.lookup(:shared_name) end) == widget_b

    Enum.each([session_a, session_b, widget_a, widget_b], &Process.exit(&1, :kill))
  end

  test "a session with no context still resolves its own registrations" do
    widget = spawn(fn -> Process.sleep(:infinity) end)
    WidgetPidRegistry.register(:standalone, widget)
    assert WidgetPidRegistry.lookup(:standalone) == widget
    Process.exit(widget, :kill)
  end

  test "a lookup from a different session does not see an unrelated registration" do
    other = spawn(fn -> Process.sleep(:infinity) end)
    widget = spawn(fn -> Process.sleep(:infinity) end)

    WidgetPidRegistry.register(:only_here, widget)

    assert in_session(other, fn -> WidgetPidRegistry.lookup(:only_here) end) == nil

    Enum.each([other, widget], &Process.exit(&1, :kill))
  end
end
