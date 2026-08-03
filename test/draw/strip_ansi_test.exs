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
    test "an unstyled row is its text" do
      assert Strip.to_ansi(strip([Segment.new("abc")])) == "abc"
    end

    test "styled segments keep their characters in order" do
      row =
        strip([
          Segment.new("a", %{fg: {1, 2, 3}}),
          Segment.new("b", %{fg: {4, 5, 6}}),
          Segment.new("c", %{})
        ])

      assert visible(Strip.to_ansi(row)) == "abc"
    end

    test "every style combination round-trips its text" do
      row =
        strip([
          Segment.new("w", %{fg: {1, 1, 1}, bg: {2, 2, 2}, bold: true}),
          Segment.new("x", %{fg: {1, 1, 1}, bg: {2, 2, 2}}),
          Segment.new("y", %{bg: {2, 2, 2}}),
          Segment.new("z", %{})
        ])

      assert visible(Strip.to_ansi(row)) == "wxyz"
    end
  end

  describe "codes are not restated" do
    test "a repeated style is emitted once" do
      style = %{fg: {10, 20, 30}, bg: {40, 50, 60}}
      row = strip(Enum.map(~w(a b c d e), &Segment.new(&1, style)))

      assert Strip.to_ansi(row) |> count_sgr() == 2,
             "expected one set and one final reset, got #{inspect(Strip.to_ansi(row))}"
    end

    test "a row of identical cells costs far less than restating each" do
      style = %{fg: {10, 20, 30}, bg: {40, 50, 60}}
      row = strip(Enum.map(1..60, fn _ -> Segment.new("x", style) end))

      assert byte_size(Strip.to_ansi(row)) < 60 * 10
    end

    test "the row ends reset when it ended styled" do
      row = strip([Segment.new("a", %{fg: {1, 2, 3}})])

      assert String.ends_with?(Strip.to_ansi(row), "\e[0m")
    end

    test "an unstyled row emits no codes at all" do
      row = strip([Segment.new("a"), Segment.new("b")])

      assert Strip.to_ansi(row) == "ab"
    end
  end

  describe "clearing attributes" do
    test "dropping a flag resets before the next segment" do
      row =
        strip([
          Segment.new("a", %{fg: {1, 2, 3}, bold: true}),
          Segment.new("b", %{fg: {1, 2, 3}})
        ])

      ansi = Strip.to_ansi(row)

      assert String.contains?(ansi, "\e[0m"), "a dropped flag must be cleared"
      assert visible(ansi) == "ab"
    end

    test "returning to unstyled resets" do
      row = strip([Segment.new("a", %{bg: {9, 9, 9}}), Segment.new("b", %{})])

      assert visible(Strip.to_ansi(row)) == "ab"
      assert String.contains?(Strip.to_ansi(row), "\e[0m")
    end
  end

  defp count_sgr(ansi), do: ansi |> String.split("\e[") |> length() |> Kernel.-(1)
end
