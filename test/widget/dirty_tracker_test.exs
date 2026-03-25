defmodule Drafter.Widget.DirtyTrackerTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.DirtyTracker

  describe "state_hash/2" do
    test "identical state produces same hash" do
      state = %{text: "hello", _scroll_offset_y: 0, focused: true}
      affecting = [:text, :_scroll_offset_y]

      assert DirtyTracker.state_hash(state, affecting) ==
               DirtyTracker.state_hash(state, affecting)
    end

    test "changed affecting field produces different hash" do
      state1 = %{text: "hello", focused: true}
      state2 = %{text: "world", focused: true}
      affecting = [:text]

      refute DirtyTracker.state_hash(state1, affecting) ==
               DirtyTracker.state_hash(state2, affecting)
    end

    test "changed non-affecting field produces same hash" do
      state1 = %{text: "hello", focused: true}
      state2 = %{text: "hello", focused: false}
      affecting = [:text]

      assert DirtyTracker.state_hash(state1, affecting) ==
               DirtyTracker.state_hash(state2, affecting)
    end
  end

  describe "render_needed?/3" do
    defmodule FakeWidget do
      def __render_affecting_fields__, do: [:text, :count]
    end

    test "returns true on first call" do
      state = %{text: "hello", count: 1}
      assert DirtyTracker.render_needed?(:test_widget_1, state, FakeWidget)
    end

    test "returns false on same state" do
      state = %{text: "hello", count: 1}
      DirtyTracker.render_needed?(:test_widget_2, state, FakeWidget)
      refute DirtyTracker.render_needed?(:test_widget_2, state, FakeWidget)
    end

    test "returns true on changed state" do
      state1 = %{text: "hello", count: 1}
      state2 = %{text: "world", count: 1}
      DirtyTracker.render_needed?(:test_widget_3, state1, FakeWidget)
      assert DirtyTracker.render_needed?(:test_widget_3, state2, FakeWidget)
    end
  end

  describe "invalidate/1" do
    defmodule FakeWidget2 do
      def __render_affecting_fields__, do: [:text]
    end

    test "forces next render_needed? to return true" do
      state = %{text: "hello"}
      DirtyTracker.render_needed?(:test_widget_4, state, FakeWidget2)
      DirtyTracker.invalidate(:test_widget_4)
      assert DirtyTracker.render_needed?(:test_widget_4, state, FakeWidget2)
    end
  end
end
