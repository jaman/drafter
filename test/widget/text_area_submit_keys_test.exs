defmodule Drafter.Widget.TextAreaSubmitKeysTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.ANSI
  alias Drafter.Widget.TextArea

  defp press(bytes) do
    {[event | _key_down], ""} = ANSI.parse_sequence(bytes)
    event
  end

  defp composer(text) do
    test = self()

    state =
      TextArea.mount(%{text: text, enter: :submit, on_submit: &send(test, {:submitted, &1})})

    %{state | focused: true}
  end

  test "enter submits the text and leaves it for the app to clear" do
    assert {:ok, state} = TextArea.handle_event(press("\r"), composer("hello"))
    assert_received {:submitted, "hello"}
    assert state.text == "hello"
  end

  test "alt, shift or ctrl with enter starts a new line at the cursor instead" do
    for bytes <- ["\e\r", "\e[13;2u", "\e[13;5u"] do
      {:ok, state} = TextArea.handle_event(press(bytes), composer("hello"))
      assert state.lines == ["", "hello"]
    end

    refute_received {:submitted, _text}
  end

  test "text the app completes is typed on after, from a cursor that was at the end" do
    state = composer("/mo")
    state = %{state | cursor_col: 3}

    completed = TextArea.update(%{text: "/model "}, state)
    assert {completed.cursor_line, completed.cursor_col} == {0, 7}

    middle = TextArea.update(%{text: "/model "}, %{state | cursor_col: 1})
    assert {middle.cursor_line, middle.cursor_col} == {0, 1}
  end
end
