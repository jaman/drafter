defmodule Drafter.Draw.StripAnsiTest do
  @moduledoc """
  Serialising a row to ANSI.

  A row is emitted as one stream, so style codes carry across segments: a segment
  matching the one before it needs no codes at all, and one that only changes
  colour need not restate the rest. Charts produce rows of single-cell segments,
  where restating everything per cell dominates the bytes written per frame.
  """

  use ExUnit.Case, async: true

  alias Drafter.Draw.{Segment, Strip}

  defp strip(segments), do: Strip.new(segments)

  defp visible(ansi), do: String.replace(ansi, ~r/\e\[[0-9;]*m/, "")

  describe "text is preserved" do
    test "styled segments keep their characters in order" do
      row =
        strip([
          Segment.new("a", %{fg: {1, 2, 3}}),
          Segment.new("b", %{fg: {4, 5, 6}}),
          Segment.new("c", %{})
        ])

      assert visible(Strip.to_ansi(row)) == "abc"
    end
  end

  describe "codes are not restated" do
    test "a repeated style is emitted once" do
      style = %{fg: {10, 20, 30}, bg: {40, 50, 60}}
      row = strip(Enum.map(~w(a b c d e), &Segment.new(&1, style)))

      assert Strip.to_ansi(row) |> count_sgr() == 2,
             "expected one set and one final reset, got #{inspect(Strip.to_ansi(row))}"
    end

    test "an unstyled row emits no codes at all" do
      row = strip([Segment.new("a"), Segment.new("b")])

      assert Strip.to_ansi(row) == "ab"
    end
  end

  defp count_sgr(ansi), do: ansi |> String.split("\e[") |> length() |> Kernel.-(1)
end
