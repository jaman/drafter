defmodule Drafter.Widget.SparklineTest do
  use ExUnit.Case
  alias Drafter.ThemeManager
  alias Drafter.Widget.Sparkline

  setup do
    case start_supervised(ThemeManager) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  describe "mount/1" do
    test "mounts with basic data" do
      state = Sparkline.mount(%{data: [1, 2, 3, 4, 5]})
      assert state.data == [1, 2, 3, 4, 5]
      assert state.min_value == 1
      assert state.max_value == 5
    end

    test "mounts with custom min and max values" do
      state = Sparkline.mount(%{data: [1, 2, 3], min_value: 0, max_value: 10})
      assert state.min_value == 0
      assert state.max_value == 10
    end

    test "mounts with color options" do
      state =
        Sparkline.mount(%{
          data: [1, 2, 3],
          color: {100, 100, 100},
          min_color: {0, 255, 0},
          max_color: {255, 0, 0}
        })

      assert state.color == {100, 100, 100}
      assert state.min_color == {0, 255, 0}
      assert state.max_color == {255, 0, 0}
    end

    test "mounts with summary enabled" do
      state = Sparkline.mount(%{data: [1, 2, 3], summary: true})
      assert state.summary == true
    end

    test "handles empty data" do
      state = Sparkline.mount(%{data: []})
      assert state.data == []
      assert state.min_value == 0
      assert state.max_value == 0
    end
  end

  describe "render/2" do
    test "renders sparkline with data" do
      state = Sparkline.mount(%{data: [1, 2, 3, 4, 5]})
      rect = %{width: 10, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "renders sparkline with color gradient" do
      state =
        Sparkline.mount(%{
          data: [0, 0.5, 1.0],
          min_color: {0, 255, 0},
          max_color: {255, 0, 0}
        })

      rect = %{width: 3, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "renders sparkline with summary" do
      state =
        Sparkline.mount(%{
          data: [1, 2, 3, 4, 5],
          summary: true
        })

      rect = %{width: 30, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "renders empty sparkline" do
      state = Sparkline.mount(%{data: []})
      rect = %{width: 10, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "uses default color when min/max not specified" do
      state =
        Sparkline.mount(%{
          data: [1, 2, 3],
          color: {100, 200, 100}
        })

      rect = %{width: 5, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end
  end

  describe "update/2" do
    test "updates data" do
      state = Sparkline.mount(%{data: [1, 2, 3]})
      new_state = Sparkline.update(%{data: [4, 5, 6]}, state)
      assert new_state.data == [4, 5, 6]
      assert new_state.min_value == 4
      assert new_state.max_value == 6
    end

    test "recalculates min/max when updating data without custom values" do
      state = Sparkline.mount(%{data: [1, 2, 3], min_value: 0, max_value: 10})
      new_state = Sparkline.update(%{data: [5, 6, 7]}, state)
      assert new_state.data == [5, 6, 7]
      assert new_state.min_value == 5
      assert new_state.max_value == 7
    end

    test "preserves custom min/max when explicitly provided in update" do
      state = Sparkline.mount(%{data: [1, 2, 3], min_value: 0, max_value: 10})
      new_state = Sparkline.update(%{data: [5, 6, 7], min_value: 0, max_value: 10}, state)
      assert new_state.data == [5, 6, 7]
      assert new_state.min_value == 0
      assert new_state.max_value == 10
    end

    test "updates colors" do
      state = Sparkline.mount(%{data: [1, 2, 3]})

      new_state =
        Sparkline.update(
          %{
            min_color: {255, 0, 0},
            max_color: {0, 0, 255}
          },
          state
        )

      assert new_state.min_color == {255, 0, 0}
      assert new_state.max_color == {0, 0, 255}
    end

    test "toggles summary" do
      state = Sparkline.mount(%{data: [1, 2, 3], summary: false})
      new_state = Sparkline.update(%{summary: true}, state)
      assert new_state.summary == true
    end
  end

  describe "interpolate_color/3" do
    test "interpolates between two colors at factor 0" do
      assert Sparkline.interpolate_color({0, 0, 0}, {255, 255, 255}, 0.0) == {0, 0, 0}
    end

    test "interpolates between two colors at factor 1" do
      assert Sparkline.interpolate_color({0, 0, 0}, {255, 255, 255}, 1.0) == {255, 255, 255}
    end

    test "interpolates between two colors at factor 0.5" do
      assert Sparkline.interpolate_color({0, 0, 0}, {255, 255, 255}, 0.5) == {128, 128, 128}
    end

    test "interpolates between different colors" do
      assert Sparkline.interpolate_color({255, 0, 0}, {0, 0, 255}, 0.5) == {128, 0, 128}
    end

    test "interpolates green to red" do
      assert Sparkline.interpolate_color({0, 255, 0}, {255, 0, 0}, 0.75) == {191, 64, 0}
    end

    test "handles factor at boundaries" do
      assert Sparkline.interpolate_color({100, 150, 200}, {200, 250, 300}, 0.0) == {100, 150, 200}
      assert Sparkline.interpolate_color({100, 150, 200}, {200, 250, 300}, 1.0) == {200, 250, 300}
    end
  end

  describe "handle_event/2" do
    test "returns noreply for all events" do
      state = Sparkline.mount(%{data: [1, 2, 3]})
      assert {:noreply, _} = Sparkline.handle_event(:any_event, state)
    end
  end

  describe "render_sparkline_with_values/4" do
    test "returns characters and normalized values" do
      state = Sparkline.mount(%{data: [0, 0.5, 1.0]})
      {chars, values} = Sparkline.render_sparkline_with_values(state.data, 0, 1.0, 3)
      assert String.length(chars) == 3
      assert length(values) == 3
      assert Enum.all?(values, fn v -> v >= 0 and v <= 1 end)
    end

    test "handles edge case where min equals max" do
      {chars, values} = Sparkline.render_sparkline_with_values([5, 5, 5], 5, 5, 3)
      assert String.length(chars) == 3
      assert length(values) == 3
      assert Enum.all?(values, fn v -> v == 0.0 end)
    end

    test "handles empty data" do
      {chars, values} = Sparkline.render_sparkline_with_values([], 0, 0, 5)
      assert String.length(chars) == 5
      assert String.trim(chars) == ""
      assert length(values) == 5
    end

    test "normalizes values correctly" do
      data = [0, 5, 10]
      {_chars, values} = Sparkline.render_sparkline_with_values(data, 0, 10, 3)
      assert Enum.at(values, 0) == 0.0
      assert Enum.at(values, 1) == 0.5
      assert Enum.at(values, 2) == 1.0
    end
  end

  describe "gradient color consistency" do
    test "low values use min_color" do
      state =
        Sparkline.mount(%{
          data: [0, 0.1, 0.2],
          min_value: 0,
          max_value: 1,
          min_color: {0, 255, 0},
          max_color: {255, 0, 0}
        })

      rect = %{width: 3, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "high values use max_color" do
      state =
        Sparkline.mount(%{
          data: [0.8, 0.9, 1.0],
          min_value: 0,
          max_value: 1,
          min_color: {0, 255, 0},
          max_color: {255, 0, 0}
        })

      rect = %{width: 3, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end

    test "middle values use interpolated colors" do
      state =
        Sparkline.mount(%{
          data: [0.5],
          min_value: 0,
          max_value: 1,
          min_color: {0, 0, 255},
          max_color: {255, 0, 0}
        })

      rect = %{width: 1, height: 1}
      strips = Sparkline.render(state, rect)
      assert length(strips) == 1
    end
  end
end
