defmodule Drafter.Widget.ChartGapTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.Chart

  setup do
    {:ok, tm} = Drafter.ThemeManager.start_link(name: nil)
    Process.put(:drafter_theme_manager, tm)
    :ok
  end

  defp drawn_cells(data) do
    %{data: data, chart_type: :line, connect_lines: true, height: 6}
    |> Chart.mount()
    |> Chart.render(%{x: 0, y: 0, width: 20, height: 6})
    |> Enum.flat_map(& &1.segments)
    |> Enum.map_join(& &1.text)
    |> String.graphemes()
    |> Enum.count(&(&1 not in [" ", "⠀"]))
  end

  test "one series given as a list of series is drawn" do
    assert drawn_cells([[1, 4, 2, 5, 3, 6]]) > 0
  end

  test "a gap draws nothing at its positions" do
    assert drawn_cells([[nil, nil, nil, nil, nil, nil]]) == 0
    assert drawn_cells([[1, 4, nil, nil, 3, 6]]) > 0
  end
end
