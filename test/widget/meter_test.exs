defmodule Drafter.Widget.MeterTest do
  use ExUnit.Case
  alias Drafter.Widget.Meter
  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "mounts with defaults" do
      state = Meter.mount(%{})
      assert state.value == 0.0
      assert state.orientation == :horizontal
      assert state.show_value == true
      assert state.show_label == true
      assert state.label == nil
      assert length(state.thresholds) == 3
    end

    test "mounts with custom value and label" do
      state = Meter.mount(%{value: 0.75, label: "CPU"})
      assert state.value == 0.75
      assert state.label == "CPU"
    end

    test "mounts with custom thresholds" do
      thresholds = [{0.5, {0, 255, 0}}, {1.0, {255, 0, 0}}]
      state = Meter.mount(%{thresholds: thresholds})
      assert state.thresholds == thresholds
    end

    test "mounts with vertical orientation" do
      state = Meter.mount(%{orientation: :vertical})
      assert state.orientation == :vertical
    end
  end

  describe "threshold coloring" do
    test "returns first threshold color for low values" do
      state = Meter.mount(%{value: 0.3})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert is_list(strips)
      assert [_ | _] = strips
    end

    test "returns second threshold color for mid values" do
      state = Meter.mount(%{value: 0.7})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert is_list(strips)
      assert [_ | _] = strips
    end

    test "returns last threshold color for high values" do
      state = Meter.mount(%{value: 0.95})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert is_list(strips)
      assert [_ | _] = strips
    end

    test "custom thresholds are respected" do
      thresholds = [{0.5, {0, 255, 0}}, {1.0, {255, 0, 0}}]
      state = Meter.mount(%{value: 0.3, thresholds: thresholds})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert is_list(strips)
    end
  end

  describe "horizontal render" do
    test "renders single strip without label" do
      state = Meter.mount(%{value: 0.5})
      rect = %{width: 30, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end

    test "renders two strips with label" do
      state = Meter.mount(%{value: 0.5, label: "Memory"})
      rect = %{width: 30, height: 2}
      strips = Meter.render(state, rect)
      assert length(strips) == 2
    end

    test "renders without value text when show_value is false" do
      state = Meter.mount(%{value: 0.5, show_value: false})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end

    test "renders without label when show_label is false" do
      state = Meter.mount(%{value: 0.5, label: "Test", show_label: false})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end

    test "renders zero value" do
      state = Meter.mount(%{value: 0.0})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end

    test "renders full value" do
      state = Meter.mount(%{value: 1.0})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end
  end

  describe "vertical render" do
    test "renders vertical meter" do
      state = Meter.mount(%{value: 0.5, orientation: :vertical})
      rect = %{width: 10, height: 8}
      strips = Meter.render(state, rect)
      assert [_ | _] = strips
    end

    test "renders vertical with label and value" do
      state = Meter.mount(%{value: 0.7, orientation: :vertical, label: "Disk"})
      rect = %{width: 10, height: 10}
      strips = Meter.render(state, rect)
      label_row = 1
      value_row = 1
      bar_rows = 10 - label_row - value_row
      assert length(strips) == label_row + bar_rows + value_row
    end

    test "renders vertical without label" do
      state = Meter.mount(%{value: 0.7, orientation: :vertical})
      rect = %{width: 10, height: 8}
      strips = Meter.render(state, rect)
      value_row = 1
      bar_rows = 8 - value_row
      assert length(strips) == bar_rows + value_row
    end

    test "renders vertical without value text" do
      state = Meter.mount(%{value: 0.7, orientation: :vertical, show_value: false})
      rect = %{width: 10, height: 8}
      strips = Meter.render(state, rect)
      assert length(strips) == 8
    end
  end

  describe "update/2" do
    test "updates value" do
      state = Meter.mount(%{value: 0.3})
      new_state = Meter.update(%{value: 0.8}, state)
      assert new_state.value == 0.8
    end

    test "preserves unchanged fields" do
      state = Meter.mount(%{value: 0.3, label: "CPU"})
      new_state = Meter.update(%{value: 0.8}, state)
      assert new_state.label == "CPU"
    end

    test "updates multiple fields" do
      state = Meter.mount(%{value: 0.3})
      new_state = Meter.update(%{value: 0.9, label: "Memory", show_value: false}, state)
      assert new_state.value == 0.9
      assert new_state.label == "Memory"
      assert new_state.show_value == false
    end
  end

  describe "handle_event/2" do
    test "returns noreply for any event" do
      state = Meter.mount(%{value: 0.5})
      assert {:noreply, ^state} = Meter.handle_event(:any_event, state)
    end
  end

  describe "component_tag/0" do
    test "returns :meter" do
      assert Meter.component_tag() == :meter
    end
  end

  describe "preferred_height/2" do
    test "returns 1 for horizontal without label" do
      assert Meter.preferred_height(nil, []) == 1
    end

    test "returns 2 for horizontal with label" do
      assert Meter.preferred_height(nil, label: "Test") == 2
    end

    test "returns 8 for vertical by default" do
      assert Meter.preferred_height(nil, orientation: :vertical) == 8
    end

    test "returns custom height for vertical" do
      assert Meter.preferred_height(nil, orientation: :vertical, height: 12) == 12
    end
  end

  describe "from_component_opts/2" do
    test "extracts props from keyword opts" do
      props = Meter.from_component_opts(nil, value: 0.6, label: "Net")
      assert props.value == 0.6
      assert props.label == "Net"
    end

    test "uses defaults for missing opts" do
      props = Meter.from_component_opts(nil, [])
      assert props.value == 0.0
      assert props.orientation == :horizontal
      assert props.show_value == true
    end
  end
end
