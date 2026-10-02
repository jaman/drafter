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

    test "down bubbles at last option index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      state = %{state | highlighted_index: 1}
      assert {:bubble, new_state} = RadioSet.handle_event({:key, :down}, state)
      assert new_state.highlighted_index == 1
    end

    test "space sets selected_index to highlighted_index" do
      state = RadioSet.mount(%{options: [{"A", :a}, {"B", :b}]})
      state = %{state | highlighted_index: 1}
      assert {:ok, new_state} = RadioSet.handle_event({:key, :" "}, state)
      assert new_state.selected_index == 1
    end
  end
end
