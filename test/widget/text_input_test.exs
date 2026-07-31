defmodule Drafter.Widget.TextInputTest do
  use ExUnit.Case
  alias Drafter.Widget.TextInput

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "defaults text to empty string" do
      state = TextInput.mount(%{})
      assert state.text == ""
    end

    test "defaults cursor_position to 0" do
      state = TextInput.mount(%{})
      assert state.cursor_position == 0
    end

    test "defaults scroll_offset to 0" do
      state = TextInput.mount(%{})
      assert state.scroll_offset == 0
    end

    test "defaults focused to false" do
      state = TextInput.mount(%{})
      assert state.focused == false
    end

    test "accepts initial text" do
      state = TextInput.mount(%{text: "hello"})
      assert state.text == "hello"
    end
  end

  describe "handle_event/2 char insertion" do
    test "inserts character at cursor position" do
      state = TextInput.mount(%{focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:char, ?a}, state)
      assert new_state.text == "a"
    end

    test "advances cursor after char insertion" do
      state = TextInput.mount(%{focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:char, ?a}, state)
      assert new_state.cursor_position == 1
    end

    test "multiple chars build up correctly" do
      state = TextInput.mount(%{focused: true})
      {:ok, state} = TextInput.handle_event({:char, ?h}, state)
      {:ok, state} = TextInput.handle_event({:char, ?i}, state)
      {:ok, state} = TextInput.handle_event({:char, ?!}, state)
      assert state.text == "hi!"
      assert state.cursor_position == 3
    end

    test "inserts at correct position mid-text" do
      state = TextInput.mount(%{text: "ac", cursor_position: 1, focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:char, ?b}, state)
      assert new_state.text == "abc"
      assert new_state.cursor_position == 2
    end

    test "does not insert when not focused" do
      state = TextInput.mount(%{focused: false})
      assert {:noreply, _} = TextInput.handle_event({:char, ?a}, state)
    end
  end

  describe "handle_event/2 backspace" do
    test "removes character before cursor" do
      state = TextInput.mount(%{text: "ab", cursor_position: 2, focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:key, :backspace}, state)
      assert new_state.text == "a"
      assert new_state.cursor_position == 1
    end

    test "does nothing at position 0" do
      state = TextInput.mount(%{text: "ab", cursor_position: 0, focused: true})
      assert {:noreply, _} = TextInput.handle_event({:key, :backspace}, state)
    end

    test "backspace mid-text removes correct character" do
      state = TextInput.mount(%{text: "abc", cursor_position: 2, focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:key, :backspace}, state)
      assert new_state.text == "ac"
      assert new_state.cursor_position == 1
    end
  end

  describe "scroll_offset regression" do
    test "scroll does not trigger until cursor reaches the content width boundary" do
      state = TextInput.mount(%{focused: true, width: 10})

      state =
        Enum.reduce(1..9, state, fn _, acc ->
          {:ok, next} = TextInput.handle_event({:char, ?x}, acc)
          next
        end)

      assert state.cursor_position == 9
      assert state.scroll_offset == 0
    end

    test "scroll triggers when cursor reaches position equal to width" do
      state = TextInput.mount(%{focused: true, width: 10})

      state =
        Enum.reduce(1..10, state, fn _, acc ->
          {:ok, next} = TextInput.handle_event({:char, ?x}, acc)
          next
        end)

      assert state.cursor_position == 10
      assert state.scroll_offset == 1
    end

    test "scroll_offset advances with each char beyond width" do
      state = TextInput.mount(%{focused: true, width: 10})

      state =
        Enum.reduce(1..12, state, fn _, acc ->
          {:ok, next} = TextInput.handle_event({:char, ?x}, acc)
          next
        end)

      assert state.cursor_position == 12
      assert state.scroll_offset == 3
    end
  end

  describe "update/2" do
    test "preserves cursor_position" do
      state = TextInput.mount(%{text: "hello", cursor_position: 3, focused: true})
      new_state = TextInput.update(%{text: "hello world"}, state)
      assert new_state.cursor_position == 3
    end

    test "preserves scroll_offset" do
      state = TextInput.mount(%{text: "hello", scroll_offset: 2})
      new_state = TextInput.update(%{text: "hello world"}, state)
      assert new_state.scroll_offset == 2
    end

    test "updates text when provided" do
      state = TextInput.mount(%{text: "old"})
      new_state = TextInput.update(%{text: "new"}, state)
      assert new_state.text == "new"
    end

    test "preserves text when not provided" do
      state = TextInput.mount(%{text: "keep me"})
      new_state = TextInput.update(%{placeholder: "hint"}, state)
      assert new_state.text == "keep me"
    end
  end

  describe "handle_event/2 focus and blur" do
    test "focus sets focused to true" do
      state = TextInput.mount(%{})
      assert {:ok, new_state} = TextInput.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "blur sets focused to false" do
      state = TextInput.mount(%{focused: true})
      assert {:ok, new_state} = TextInput.handle_event({:blur}, state)
      assert new_state.focused == false
    end

    test "blur sets touched to true" do
      state = TextInput.mount(%{})
      assert {:ok, new_state} = TextInput.handle_event({:blur}, state)
      assert new_state.touched == true
    end
  end
end
