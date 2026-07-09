defmodule Drafter.Regression.PasteTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.{TextArea, TextInput}

  test "text_input inserts pasted text at the cursor, collapsing newlines" do
    state = %{TextInput.mount(%{}) | focused: true}
    {:ok, s} = TextInput.handle_event({:bracketed_paste, "hello\nworld"}, state)
    assert s.text == "hello world"
    assert s.cursor_position == String.length("hello world")
  end

  test "text_input paste inserts between existing text" do
    state = %{TextInput.mount(%{}) | focused: true, text: "ac", cursor_position: 1}
    {:ok, s} = TextInput.handle_event({:bracketed_paste, "b"}, state)
    assert s.text == "abc"
  end

  test "text_area inserts multi-line pasted text and moves the cursor to the end" do
    state = %{TextArea.mount(%{}) | focused: true}
    {:ok, s} = TextArea.handle_event({:bracketed_paste, "line1\nline2\nline3"}, state)
    assert s.lines == ["line1", "line2", "line3"]
    assert s.text == "line1\nline2\nline3"
    assert s.cursor_line == 2
    assert s.cursor_col == String.length("line3")
  end

  test "text_area single-line paste inserts at the cursor without adding a line" do
    state = %{TextArea.mount(%{}) | focused: true}
    {:ok, s} = TextArea.handle_event({:bracketed_paste, "select 1"}, state)
    assert s.lines == ["select 1"]
  end
end
