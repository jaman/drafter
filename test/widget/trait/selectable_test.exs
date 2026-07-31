defmodule Drafter.Widget.Trait.SelectableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Selectable

  describe "metadata" do
    test "name is :selectable" do
      assert :selectable = Selectable.name()
    end

    test "depends on focusable" do
      assert [:focusable] = Selectable.dependencies()
    end

    test "handles keyboard" do
      assert [:keyboard] = Selectable.handles()
    end

    test "is layout static" do
      assert Selectable.layout_static?()
    end
  end

  describe "default_state/0" do
    test "initializes with single selection mode" do
      state = Selectable.default_state()
      assert state._selection_mode == :single
      assert state._cursor_index == 0
      assert MapSet.equal?(state._selected_indices, MapSet.new())
    end
  end

  describe "cursor movement" do
    test "arrow up moves cursor up" do
      state = %{Selectable.default_state() | _cursor_index: 5, _item_count: 10}
      {:ok, new_state} = Selectable.handle_event({:key, :up}, state, %{})
      assert new_state._cursor_index == 4
    end

    test "arrow up does not go below zero" do
      state = %{Selectable.default_state() | _cursor_index: 0, _item_count: 10}
      {:ok, new_state} = Selectable.handle_event({:key, :up}, state, %{})
      assert new_state._cursor_index == 0
    end

    test "arrow down moves cursor down" do
      state = %{Selectable.default_state() | _cursor_index: 3, _item_count: 10}
      {:ok, new_state} = Selectable.handle_event({:key, :down}, state, %{})
      assert new_state._cursor_index == 4
    end

    test "arrow down does not exceed item count" do
      state = %{Selectable.default_state() | _cursor_index: 9, _item_count: 10}
      {:ok, new_state} = Selectable.handle_event({:key, :down}, state, %{})
      assert new_state._cursor_index == 9
    end
  end

  describe "single selection" do
    test "space selects current item" do
      state = %{Selectable.default_state() | _cursor_index: 3, _item_count: 10}
      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.member?(new_state._selected_indices, 3)
    end

    test "space deselects already selected item" do
      state = %{Selectable.default_state() | _cursor_index: 3, _selected_indices: MapSet.new([3])}
      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.equal?(new_state._selected_indices, MapSet.new())
    end

    test "selecting new item clears previous selection in single mode" do
      state = %{Selectable.default_state() | _cursor_index: 5, _selected_indices: MapSet.new([3])}
      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.equal?(new_state._selected_indices, MapSet.new([5]))
    end
  end

  describe "multiple selection" do
    test "space adds to selection in multiple mode" do
      state = %{
        Selectable.default_state()
        | _selection_mode: :multiple,
          _cursor_index: 5,
          _selected_indices: MapSet.new([3])
      }

      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.equal?(new_state._selected_indices, MapSet.new([3, 5]))
    end

    test "space removes from selection in multiple mode" do
      state = %{
        Selectable.default_state()
        | _selection_mode: :multiple,
          _cursor_index: 3,
          _selected_indices: MapSet.new([3, 5])
      }

      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.equal?(new_state._selected_indices, MapSet.new([5]))
    end
  end

  describe "none selection mode" do
    test "space does nothing in none mode" do
      state = %{Selectable.default_state() | _selection_mode: :none, _cursor_index: 3}
      {:ok, new_state} = Selectable.handle_event({:key, :" "}, state, %{})
      assert MapSet.equal?(new_state._selected_indices, MapSet.new())
    end
  end

  describe "enter and other keys" do
    test "enter passes through" do
      state = Selectable.default_state()
      {:pass, _} = Selectable.handle_event({:key, :enter}, state, %{})
    end

    test "unhandled keys pass through" do
      state = Selectable.default_state()
      {:pass, _} = Selectable.handle_event({:key, :tab}, state, %{})
    end
  end
end
