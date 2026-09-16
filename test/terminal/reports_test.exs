defmodule Drafter.Terminal.ReportsTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.{ANSI, Reports}

  test "the cell size query" do
    assert Reports.cell_size_query() == "\e[16t"
  end

  test "the reply parses to width and height in pixels" do
    assert {[{:cell_size, {9, 18}}], ""} = ANSI.parse_sequence("\e[6;18;9t")
    assert {[{:cell_size, {9, 18}}, {:key, :a}], ""} = ANSI.parse_sequence("\e[6;18;9ta")
  end

  test "a partial reply is held back" do
    assert {[], "\e[6;18;"} = ANSI.parse_sequence("\e[6;18;")
  end

  test "other t reports are not taken for a cell size" do
    assert {events, ""} = ANSI.parse_sequence("\e[8;24;80t")
    refute Enum.any?(events, &match?({:cell_size, _}, &1))
  end
end
