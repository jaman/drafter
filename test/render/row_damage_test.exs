defmodule Drafter.Render.RowDamageTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Render.RowDamage

  defp row(text, style \\ %{}), do: Strip.new([Segment.new(text, style)])

  test "only the changed cells are rewritten, nearby changes as one run" do
    before = row(String.duplicate(".", 40))
    now = row("..AB.C" <> String.duplicate(".", 26) <> "XY......")

    assert RowDamage.runs(before, now) == [{2, 4}, {32, 2}]
  end

  test "a change of colour alone counts" do
    before =
      Strip.new([Segment.new("aaaa", %{fg: {1, 2, 3}}), Segment.new(String.duplicate("b", 20))])

    now =
      Strip.new([
        Segment.new("aa", %{fg: {1, 2, 3}}),
        Segment.new("aa", %{fg: {9, 9, 9}}),
        Segment.new(String.duplicate("b", 20))
      ])

    assert RowDamage.runs(before, now) == [{2, 2}]
  end

  test "a wide character is taken whole, and a mostly changed row is written whole" do
    before = row("ab" <> "漢" <> String.duplicate(".", 17))
    now = row("ab" <> "字" <> String.duplicate(".", 17))

    assert RowDamage.runs(before, now) == [{2, 2}]

    assert RowDamage.runs(row(String.duplicate(".", 20)), row(String.duplicate("x", 20))) ==
             :whole
  end
end
