defmodule Drafter.TextWrapFastPathTest do
  use ExUnit.Case, async: true

  alias Drafter.Text

  doctest Drafter.Text

  describe "lines that already fit" do
    test "leading and trailing whitespace survives a line that fits" do
      assert Text.wrap("  indented  ", 40, :word) == ["  indented  "]
    end

    test "a blank line stays blank" do
      assert Text.wrap("", 40, :word) == [""]
      assert Text.wrap("a\n\nb", 40, :word) == ["a", "", "b"]
    end
  end

  describe "lines that need wrapping are unaffected" do
    test "word mode still breaks on word boundaries" do
      assert Text.wrap("alpha beta gamma", 11, :word) == ["alpha beta", "gamma"]
    end

    test "every produced line is within the target width" do
      text = "the quick brown fox jumps over the lazy dog"

      for mode <- [:word, :char], width <- [5, 8, 13, 21] do
        for line <- Text.wrap(text, width, mode) do
          assert Text.display_width(line) <= width or not String.contains?(line, " ")
        end
      end
    end
  end
end
