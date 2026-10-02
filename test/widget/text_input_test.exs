defmodule Drafter.Widget.TextInputTest do
  use ExUnit.Case
  alias Drafter.Widget.TextInput

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "named keys while focused" do
    test "a key with no glyph bubbles rather than being swallowed" do
      state = %{TextInput.mount(%{}) | focused: true}
      assert {:bubble, ^state} = TextInput.handle_event({:key, :escape}, state)
      assert {:bubble, ^state} = TextInput.handle_event({:key, :f5}, state)
    end

    test "a glyph key is still inserted" do
      state = %{TextInput.mount(%{}) | focused: true}
      assert {:ok, %{text: "a"}} = TextInput.handle_event({:key, :a}, state)
    end
  end

  describe "handle_event/2 char insertion" do
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
  end

  describe "update/2" do
    test "updates text when provided" do
      state = TextInput.mount(%{text: "old"})
      new_state = TextInput.update(%{text: "new"}, state)
      assert new_state.text == "new"
    end
  end

  describe "handle_event/2 focus and blur" do
    test "blur sets touched to true" do
      state = TextInput.mount(%{})
      assert {:ok, new_state} = TextInput.handle_event({:blur}, state)
      assert new_state.touched == true
    end
  end
end
