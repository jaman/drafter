defmodule Drafter.LayoutGridTest do
  use ExUnit.Case, async: true

  alias Drafter.Layout

  @rect %{x: 0, y: 0, width: 12, height: 6}

  defp cells(n, opts \\ []) do
    children = for i <- 1..n, do: {:text_input, [key: "c#{i}"]}
    Layout.calculate_grid_layout(children, @rect, opts)
  end

  test "an empty grid places nothing" do
    assert Layout.calculate_grid_layout([], @rect, columns: 3) == []
  end

  test "columns divide the width evenly" do
    [a, b, c] = cells(3, columns: 3)
    assert Enum.map([a, b, c], & &1.width) == [4, 4, 4]
    assert Enum.map([a, b, c], & &1.x) == [0, 4, 8]
  end

  test "rows divide the height evenly" do
    [a, _b, c, _d] = cells(4, columns: 2)
    assert a.height == 3
    assert a.y == 0
    assert c.y == 3
  end

  test "children wrap onto subsequent rows" do
    [a, b, c, d, e] = cells(5, columns: 2)
    assert {a.x, a.y} == {0, 0}
    assert {b.x, b.y} == {6, 0}
    assert {c.x, c.y} == {0, 2}
    assert {d.x, d.y} == {6, 2}
    assert {e.x, e.y} == {0, 4}
  end

  test "uneven division distributes the remainder rather than dropping it" do
    widths = cells(5, columns: 5) |> Enum.map(& &1.width)
    assert Enum.sum(widths) == 12
    assert Enum.max(widths) - Enum.min(widths) <= 1
  end

  test "a gap separates cells in both directions" do
    [a, b, c, _d] = cells(4, columns: 2, gap: 2)
    assert b.x == a.x + a.width + 2
    assert c.y == a.y + a.height + 2
  end

  test "row and column gaps can differ" do
    [a, b, c, _d] = cells(4, columns: 2, gap: {1, 3})
    assert b.x == a.x + a.width + 3
    assert c.y == a.y + a.height + 1
  end

  test "rows infer the column count" do
    assert length(cells(6, rows: 2)) == 6
    [a, _b, _c, d, _e, _f] = cells(6, rows: 2)
    assert d.y > a.y
  end

  test "with neither columns nor rows everything sits on one row" do
    cells = cells(4)
    assert Enum.map(cells, & &1.y) |> Enum.uniq() == [0]
  end

  test "a column span widens a cell across its neighbours" do
    children = [
      {:text_input, [key: "wide", col_span: 2]},
      {:text_input, [key: "b"]},
      {:text_input, [key: "c"]}
    ]

    [wide, _b, _c] = Layout.calculate_grid_layout(children, @rect, columns: 3)
    assert wide.width == 8
  end

  test "a row span deepens a cell" do
    children = [
      {:text_input, [key: "tall", row_span: 2]},
      {:text_input, [key: "b"]},
      {:text_input, [key: "c"]},
      {:text_input, [key: "d"]}
    ]

    [tall | _] = Layout.calculate_grid_layout(children, @rect, columns: 2)
    assert tall.height == 6
  end

  test "a span beyond the grid is clamped to its edge" do
    children = [{:text_input, [key: "a", col_span: 99]}, {:text_input, [key: "b"]}]
    [a, _b] = Layout.calculate_grid_layout(children, @rect, columns: 2)
    assert a.x + a.width <= @rect.x + @rect.width
  end

  test "cells stay inside the grid rect" do
    for cell <- cells(7, columns: 3, gap: 1) do
      assert cell.x >= @rect.x
      assert cell.y >= @rect.y
      assert cell.x + cell.width <= @rect.x + @rect.width
      assert cell.y + cell.height <= @rect.y + @rect.height
    end
  end
end
