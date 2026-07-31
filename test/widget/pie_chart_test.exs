defmodule Drafter.Widget.PieChartTest do
  use ExUnit.Case

  alias Drafter.Draw.Strip
  alias Drafter.Widget.PieChart

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "mounts with basic label-value data" do
      state = PieChart.mount(%{data: [{"Elixir", 45}, {"Rust", 30}]})
      assert length(state.data) == 2
      assert state.show_legend == true
      assert state.show_percentages == true
    end

    test "mounts with label-value-color data" do
      data = [{"A", 60, {255, 0, 0}}, {"B", 40, {0, 0, 255}}]
      state = PieChart.mount(%{data: data})
      assert length(state.data) == 2
    end

    test "mounts with empty data" do
      state = PieChart.mount(%{data: []})
      assert state.data == []
    end

    test "mounts with custom options" do
      state =
        PieChart.mount(%{
          data: [{"X", 10}],
          show_legend: false,
          show_percentages: false,
          colors: [{255, 0, 0}]
        })

      assert state.show_legend == false
      assert state.show_percentages == false
      assert state.colors == [{255, 0, 0}]
    end

    test "uses default palette when no colors specified" do
      state = PieChart.mount(%{data: [{"A", 1}]})
      assert is_list(state.colors)
      assert state.colors != []
    end
  end

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

    test "renders with single data point" do
      state = PieChart.mount(%{data: [{"Only", 100}]})
      rect = %{width: 30, height: 8}
      strips = PieChart.render(state, rect)
      assert length(strips) == 8
    end

    test "renders with empty data" do
      state = PieChart.mount(%{data: []})
      rect = %{width: 20, height: 5}
      strips = PieChart.render(state, rect)
      assert length(strips) == 5
    end

    test "renders without percentages" do
      state =
        PieChart.mount(%{
          data: [{"A", 30}, {"B", 70}],
          show_percentages: false
        })

      rect = %{width: 40, height: 10}
      strips = PieChart.render(state, rect)
      assert length(strips) == 10
    end

    test "strips are properly structured" do
      state = PieChart.mount(%{data: [{"X", 25}, {"Y", 75}]})
      rect = %{width: 30, height: 6}
      strips = PieChart.render(state, rect)

      Enum.each(strips, fn strip ->
        assert is_struct(strip, Strip)
        assert is_list(strip.segments)
      end)
    end
  end

  describe "update/2" do
    test "updates data" do
      state = PieChart.mount(%{data: [{"A", 50}, {"B", 50}]})
      new_state = PieChart.update(%{data: [{"C", 30}, {"D", 70}]}, state)
      assert length(new_state.data) == 2
      assert hd(new_state.data) == {"C", 30}
    end

    test "updates legend visibility" do
      state = PieChart.mount(%{data: [{"A", 1}], show_legend: true})
      new_state = PieChart.update(%{show_legend: false}, state)
      assert new_state.show_legend == false
    end

    test "preserves unmodified fields" do
      state = PieChart.mount(%{data: [{"A", 1}], show_percentages: true})
      new_state = PieChart.update(%{show_legend: false}, state)
      assert new_state.show_percentages == true
      assert new_state.data == [{"A", 1}]
    end
  end

  describe "handle_event/2" do
    test "bubbles all events" do
      state = PieChart.mount(%{data: [{"A", 1}]})
      assert {:bubble, ^state} = PieChart.handle_event(:any_event, state)
    end
  end

  describe "apply_data_buffer/3" do
    test "applies label-value tuples from data list" do
      state = PieChart.mount(%{data: []})
      data = [{"New", 42}, {"Other", 58}]
      rect = %{width: 20, height: 10}

      new_state = PieChart.apply_data_buffer(state, data, rect)
      assert length(new_state.data) == 2
      assert {"New", 42} in new_state.data
    end

    test "applies label-value-color tuples from data list" do
      state = PieChart.mount(%{data: []})
      data = [{"Red", 50, {255, 0, 0}}, {"Blue", 50, {0, 0, 255}}]
      rect = %{width: 20, height: 10}

      new_state = PieChart.apply_data_buffer(state, data, rect)
      assert length(new_state.data) == 2
    end

    test "preserves state on empty data list" do
      state = PieChart.mount(%{data: [{"Keep", 100}]})
      rect = %{width: 20, height: 10}

      new_state = PieChart.apply_data_buffer(state, [], rect)
      assert new_state.data == [{"Keep", 100}]
    end
  end

  describe "from_component_opts/2" do
    test "extracts data from first argument" do
      props = PieChart.from_component_opts([{"A", 10}], [])
      assert props.data == [{"A", 10}]
    end

    test "extracts data from opts when first arg is keyword list" do
      props = PieChart.from_component_opts([], data: [{"B", 20}])
      assert props.data == [{"B", 20}]
    end

    test "applies default options" do
      props = PieChart.from_component_opts([{"A", 1}], [])
      assert props.show_legend == true
      assert props.show_percentages == true
    end

    test "applies custom options" do
      props =
        PieChart.from_component_opts([{"A", 1}], show_legend: false, show_percentages: false)

      assert props.show_legend == false
      assert props.show_percentages == false
    end
  end

  describe "component_tag/0" do
    test "returns :pie_chart" do
      assert PieChart.component_tag() == :pie_chart
    end
  end

  describe "preferred_height/2" do
    test "returns default height" do
      assert PieChart.preferred_height(nil, []) == 10
    end

    test "returns custom height" do
      assert PieChart.preferred_height(nil, height: 15) == 15
    end
  end
end
