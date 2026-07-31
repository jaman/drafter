defmodule Drafter.Regression.SetWidgetValueTest do
  use ExUnit.Case, async: false

  alias Drafter.ThemeManager
  alias Drafter.Widget.Checkbox
  alias Drafter.Widget.TextArea
  alias Drafter.WidgetServer

  setup do
    {:ok, tm} = ThemeManager.start_link(name: nil)
    Process.put(:drafter_theme_manager, tm)
    Drafter.WidgetPidRegistry.create()
    Drafter.WidgetPidRegistry.clear()
    :ok
  end

  defp start_widget(id, module, props) do
    rect = %{x: 0, y: 0, width: 40, height: 6}
    session_ctx = %{drafter_theme_manager: Process.get(:drafter_theme_manager)}

    {:ok, pid} =
      WidgetServer.start_link(
        id: id,
        module: module,
        props: props,
        rect: rect,
        session_ctx: session_ctx
      )

    pid
  end

  test "set_widget_value replaces a text_area's text via the widget's own update" do
    pid = start_widget(:editor, TextArea, %{text: "old", width: 40, height: 6})
    assert Drafter.WidgetPidRegistry.lookup(:editor) == pid

    assert :ok = Drafter.set_widget_value(:editor, "select * from quotes")

    assert WidgetServer.get_state(pid).text == "select * from quotes"
  end

  test "set_widget_value reclamps the cursor when the new text is shorter" do
    pid =
      start_widget(:editor, TextArea, %{text: "select from some_long_table", width: 40, height: 6})

    WidgetServer.set_state(pid, %{WidgetServer.get_state(pid) | cursor_col: 25})

    assert :ok = Drafter.set_widget_value(:editor, "abc")

    state = WidgetServer.get_state(pid)
    assert state.text == "abc"
    assert state.cursor_col <= 3
  end

  test "set_widget_value sets a checkbox boolean" do
    pid = start_widget(:agree, Checkbox, %{label: "Agree", checked: false})

    assert :ok = Drafter.set_widget_value(:agree, true)

    assert WidgetServer.get_state(pid).checked == true
  end

  test "set_widget_value is a no-op for an unknown widget id" do
    assert :ok = Drafter.set_widget_value(:nonexistent, "x")
  end

  test "get_widget_state reads a registered widget with no running loop" do
    start_widget(:editor, TextArea, %{text: "hello world", width: 40, height: 6})

    assert Drafter.get_widget_state(:editor).text == "hello world"
  end

  test "round-trip: set then read back through the public API" do
    start_widget(:editor, TextArea, %{text: "", width: 40, height: 6})

    assert :ok = Drafter.set_widget_value(:editor, "select 1")
    assert Drafter.get_widget_state(:editor).text == "select 1"
  end

  test "set_widget_value ignores a type-mismatched value" do
    pid = start_widget(:editor, TextArea, %{text: "keep", width: 40, height: 6})

    assert :ok = Drafter.set_widget_value(:editor, 123)

    assert WidgetServer.get_state(pid).text == "keep"
  end
end
