defmodule Drafter.Widget.Trait.EditableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Editable

  describe "metadata" do
    test "name is :editable" do
      assert :editable = Editable.name()
    end

    test "depends on focusable" do
      assert [:focusable] = Editable.dependencies()
    end

    test "handles keyboard and char" do
      handles = Editable.handles()
      assert :keyboard in handles
      assert :char in handles
    end

    test "is layout static" do
      assert Editable.layout_static?()
    end
  end

  describe "default_state/0" do
    test "initializes with empty text and zero cursor" do
      state = Editable.default_state()
      assert state._text == ""
      assert state._cursor_position == 0
      assert state._selection_start == nil
      assert state._selection_end == nil
    end
  end

  describe "character input" do
    test "inserts character at cursor position" do
      state = %{Editable.default_state() | _text: "hllo", _cursor_position: 1}
      {:ok, new_state} = Editable.handle_event({:char, ?e}, state, %{})
      assert new_state._text == "hello"
      assert new_state._cursor_position == 2
    end

    test "appends character at end" do
      state = %{Editable.default_state() | _text: "hell", _cursor_position: 4}
      {:ok, new_state} = Editable.handle_event({:char, ?o}, state, %{})
      assert new_state._text == "hello"
      assert new_state._cursor_position == 5
    end

    test "inserts at beginning" do
      state = %{Editable.default_state() | _text: "ello", _cursor_position: 0}
      {:ok, new_state} = Editable.handle_event({:char, ?h}, state, %{})
      assert new_state._text == "hello"
      assert new_state._cursor_position == 1
    end
  end

  describe "backspace" do
    test "deletes character before cursor" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 3}
      {:ok, new_state} = Editable.handle_event({:key, :backspace}, state, %{})
      assert new_state._text == "helo"
      assert new_state._cursor_position == 2
    end

    test "passes when cursor at beginning" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 0}
      {:pass, _} = Editable.handle_event({:key, :backspace}, state, %{})
    end
  end

  describe "delete" do
    test "deletes character after cursor" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 2}
      {:ok, new_state} = Editable.handle_event({:key, :delete}, state, %{})
      assert new_state._text == "helo"
      assert new_state._cursor_position == 2
    end

    test "passes when cursor at end" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 5}
      {:pass, _} = Editable.handle_event({:key, :delete}, state, %{})
    end
  end

  describe "cursor movement" do
    test "left arrow moves cursor left" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 3}
      {:ok, new_state} = Editable.handle_event({:key, :left}, state, %{})
      assert new_state._cursor_position == 2
    end

    test "left arrow does not go below zero" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 0}
      {:ok, new_state} = Editable.handle_event({:key, :left}, state, %{})
      assert new_state._cursor_position == 0
    end

    test "right arrow moves cursor right" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 3}
      {:ok, new_state} = Editable.handle_event({:key, :right}, state, %{})
      assert new_state._cursor_position == 4
    end

    test "right arrow does not exceed text length" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 5}
      {:ok, new_state} = Editable.handle_event({:key, :right}, state, %{})
      assert new_state._cursor_position == 5
    end

    test "home moves to beginning" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 3}
      {:ok, new_state} = Editable.handle_event({:key, :home}, state, %{})
      assert new_state._cursor_position == 0
    end

    test "end moves to end" do
      state = %{Editable.default_state() | _text: "hello", _cursor_position: 0}
      {:ok, new_state} = Editable.handle_event({:key, :end}, state, %{})
      assert new_state._cursor_position == 5
    end

    test "cursor movement clears selection" do
      state = %{
        Editable.default_state()
        | _text: "hello",
          _cursor_position: 3,
          _selection_start: 1,
          _selection_end: 4
      }

      {:ok, new_state} = Editable.handle_event({:key, :left}, state, %{})
      assert new_state._selection_start == nil
      assert new_state._selection_end == nil
    end
  end

  describe "unhandled events" do
    test "pass through" do
      state = Editable.default_state()
      {:pass, _} = Editable.handle_event({:key, :tab}, state, %{})
    end
  end
end
