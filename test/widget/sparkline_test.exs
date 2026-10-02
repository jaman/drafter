defmodule Drafter.Widget.SparklineTest do
  use ExUnit.Case
  alias Drafter.Widget.Sparkline

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "update/2" do
    test "recalculates min/max when updating data without custom values" do
      state = Sparkline.mount(%{data: [1, 2, 3], min_value: 0, max_value: 10})
      new_state = Sparkline.update(%{data: [5, 6, 7]}, state)
      assert new_state.data == [5, 6, 7]
      assert new_state.min_value == 5
      assert new_state.max_value == 7
    end
  end

  describe "interpolate_color/3" do
    test "interpolates green to red" do
      assert Sparkline.interpolate_color({0, 255, 0}, {255, 0, 0}, 0.75) == {191, 64, 0}
    end
  end

  describe "render_sparkline_with_values/4" do
    test "handles edge case where min equals max" do
      {chars, values} = Sparkline.render_sparkline_with_values([5, 5, 5], 5, 5, 3)
      assert String.length(chars) == 3
      assert length(values) == 3
      assert Enum.all?(values, fn v -> v == 0.0 end)
    end

    test "normalizes values correctly" do
      data = [0, 5, 10]
      {_chars, values} = Sparkline.render_sparkline_with_values(data, 0, 10, 3)
      assert Enum.at(values, 0) == 0.0
      assert Enum.at(values, 1) == 0.5
      assert Enum.at(values, 2) == 1.0
    end
  end
end
