defmodule Drafter.Widget.MeterTest do
  use ExUnit.Case
  alias Drafter.Widget.Meter
  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

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

    test "renders without label when show_label is false" do
      state = Meter.mount(%{value: 0.5, label: "Test", show_label: false})
      rect = %{width: 20, height: 1}
      strips = Meter.render(state, rect)
      assert length(strips) == 1
    end
  end

  describe "vertical render" do
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

  describe "preferred_height/2" do
    test "returns custom height for vertical" do
      assert Meter.preferred_height(nil, orientation: :vertical, height: 12) == 12
    end
  end
end
