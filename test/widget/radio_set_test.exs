defmodule Drafter.Widget.RadioSetTest do
  use ExUnit.Case
  alias Drafter.Widget.RadioSet

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "normalizes tuple options to maps" do
      state = RadioSet.mount(%{options: [{"Light", :light}, {"Dark", :dark}]})
      assert state.options == [%{id: :light, label: "Light"}, %{id: :dark, label: "Dark"}]
    end

    test "normalizes string options to maps" do
      state = RadioSet.mount(%{options: ["alpha", "beta"]})
      assert state.options == [%{id: "alpha", label: "alpha"}, %{id: "beta", label: "beta"}]
    end

    test "accepts already-normalized map options" do
      opts = [%{id: :a, label: "A"}, %{id: :b, label: "B"}]
      state = RadioSet.mount(%{options: opts})
      assert state.options == opts
    end

    test "sets selected_index when selected matches a tuple option" do
      state = RadioSet.mount(%{options: [{"Light", :light}, {"Dark", :dark}], selected: :dark})
      assert state.selected_index == 1
    end

    test "sets selected_index when selected matches a string option" do
      state = RadioSet.mount(%{options: ["alpha", "beta", "gamma"], selected: "beta"})
      assert state.selected_index == 1
    end

    test "defaults selected_index to 0 when no selected given" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      assert state.selected_index == 0
    end

    test "highlighted_index matches selected_index on mount" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}], selected: :c})
      assert state.highlighted_index == state.selected_index
      assert state.highlighted_index == 2
    end

    test "defaults focused to false" do
      state = RadioSet.mount(%{})
      assert state.focused == false
    end
  end

  describe "update/2" do
    test "normalizes tuple options — does not store raw tuples" do
      state = RadioSet.mount(%{options: [{"A", :a}]})
      new_state = RadioSet.update(%{options: [{"X", :x}, {"Y", :y}]}, state)
      assert new_state.options == [%{id: :x, label: "X"}, %{id: :y, label: "Y"}]
    end

    test "preserves highlighted_index when selected_index does not change" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}]})
      state = %{state | highlighted_index: 2}
      new_state = RadioSet.update(%{options: [{"A", :a}, {"B", :b}, {"C", :c}]}, state)
      assert new_state.selected_index == state.selected_index
      assert new_state.highlighted_index == 2
    end

    test "recalculates selected_index when :selected changes" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}], selected: :a})
      new_state = RadioSet.update(%{selected: :c}, state)
      assert new_state.selected_index == 2
    end

    test "clamps selected_index when options list shrinks" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}], selected: :c})
      assert state.selected_index == 2
      new_state = RadioSet.update(%{options: [{"A", :a}]}, state)
      assert new_state.selected_index == 0
    end

    test "preserves options when no options key in props" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      new_state = RadioSet.update(%{selected: :b}, state)
      assert new_state.options == state.options
    end
  end

  describe "handle_event/2" do
    test "up decrements highlighted_index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}]})
      state = %{state | highlighted_index: 2}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :up}, state)
      assert new_state.highlighted_index == 1
    end

    test "up does not go below 0" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      state = %{state | highlighted_index: 0}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :up}, state)
      assert new_state.highlighted_index == 0
    end

    test "down increments highlighted_index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}]})
      state = %{state | highlighted_index: 0}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :down}, state)
      assert new_state.highlighted_index == 1
    end

    test "down does not exceed last option index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      state = %{state | highlighted_index: 1}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :down}, state)
      assert new_state.highlighted_index == 1
    end

    test "enter sets selected_index to highlighted_index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}, {"C", :c}]})
      state = %{state | highlighted_index: 2}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :enter}, state)
      assert new_state.selected_index == 2
    end

    test "space sets selected_index to highlighted_index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      state = %{state | highlighted_index: 1}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :" "}, state)
      assert new_state.selected_index == 1
    end

    test "focus sets focused to true" do
      state = RadioSet.mount(%{options: []})
      assert {:ok, new_state} = RadioSet.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "blur sets focused to false" do
      state = RadioSet.mount(%{options: []})
      state = %{state | focused: true}
      assert {:ok, new_state} = RadioSet.handle_event({:blur}, state)
      assert new_state.focused == false
    end

    test "unhandled event returns noreply" do
      state = RadioSet.mount(%{options: []})
      assert {:noreply, ^state} = RadioSet.handle_event({:key, :tab}, state)
    end
  end
end
