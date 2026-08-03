defmodule Drafter.TextWrapFastPathTest do
  use ExUnit.Case, async: true

  alias Drafter.Text

  doctest Drafter.Text

  describe "lines that already fit" do
    test "a short line is returned unchanged in every mode" do
      for mode <- [:word, :char, :none] do
        assert Text.wrap("hello world", 40, mode) == ["hello world"]
      end
    end

    test "a line exactly the target width is returned unchanged" do
      line = String.duplicate("a", 20)

      assert Text.wrap(line, 20, :word) == [line]
      assert Text.wrap(line, 20, :char) == [line]
    end

    test "leading and trailing whitespace survives a line that fits" do
      assert Text.wrap("  indented  ", 40, :word) == ["  indented  "]
    end

    test "wide characters are measured by display width, not grapheme count" do
      line = "日本語テキスト"

      assert Text.wrap(line, 14, :word) == [line]
      assert Text.wrap(line, 14, :char) == [line]
      assert length(Text.wrap(line, 6, :char)) > 1
    end

    test "each line of a multi-line string is judged on its own" do
      assert Text.wrap("short\nalso short", 40, :word) == ["short", "also short"]
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

    test "char mode still breaks mid-word" do
      assert Text.wrap("abcdefghij", 4, :char) == ["abcd", "efgh", "ij"]
    end

    test "every produced line is within the target width" do
      text = "the quick brown fox jumps over the lazy dog"

      for mode <- [:word, :char], width <- [5, 8, 13, 21] do
        for line <- Text.wrap(text, width, mode) do
          assert Text.display_width(line) <= width or not String.contains?(line, " ")
        end
      end
    end

    test "none mode truncates rather than wrapping" do
      assert Text.wrap("alpha beta gamma", 5, :none) == ["alpha"]
    end
  end
end
