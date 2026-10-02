defmodule Drafter.Widget.PieChartTest do
  use ExUnit.Case

  alias Drafter.Draw.Strip
  alias Drafter.Widget.PieChart

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "render/2" do
    test "renders pie chart with data" do
      state = PieChart.mount(%{data: [{"Elixir", 45}, {"Rust", 30}, {"Go", 25}]})
      rect = %{width: 40, height: 10}
      strips = PieChart.render(state, rect)
      assert length(strips) == 10
      assert Enum.all?(strips, &is_struct(&1, Strip))
    end

    test "renders without legend" do
      state = PieChart.mount(%{data: [{"A", 50}, {"B", 50}], show_legend: false})
      rect = %{width: 20, height: 8}
      strips = PieChart.render(state, rect)
      assert length(strips) == 8
    end

    test "renders with empty data" do
      state = PieChart.mount(%{data: []})
      rect = %{width: 20, height: 5}
      strips = PieChart.render(state, rect)
      assert length(strips) == 5
    end
  end
end
