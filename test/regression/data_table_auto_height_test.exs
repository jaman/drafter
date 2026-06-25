defmodule Drafter.DataTableAutoHeightTest do
  use ExUnit.Case

  alias Drafter.Widget.DataTable

  setup :setup_session_pdict
  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  defp cols, do: [%{key: :id, label: "ID"}, %{key: :name, label: "Name"}]
  defp rows, do: for(i <- 1..40, do: %{id: i, name: "row #{i}"})

  test "mount tolerates height: :auto and normalizes the height field" do
    state = DataTable.mount(%{columns: cols(), data: rows(), height: :auto})
    assert state.viewport_height == :auto
    assert state.height == 20
  end

  test "get_data_height stays sane with an unresolved :auto viewport" do
    state = DataTable.mount(%{columns: cols(), data: rows(), height: :auto})
    assert DataTable.get_data_height(state) == 19
  end

  test "height: :auto fills rect.height on the first render, matching an explicit height" do
    rect = %{x: 0, y: 0, width: 40, height: 12}

    auto = DataTable.mount(%{columns: cols(), data: rows(), height: :auto})
    fixed = DataTable.mount(%{columns: cols(), data: rows(), height: 12})

    auto_strips = DataTable.render(auto, rect)
    assert length(auto_strips) > 1
    assert length(auto_strips) == length(DataTable.render(fixed, rect))
  end
end
