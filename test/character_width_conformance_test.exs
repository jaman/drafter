defmodule Drafter.CharacterWidthConformanceTest do
  @moduledoc """
  The contract every `Drafter.CharacterWidth` implementation must satisfy.

  Drafter decides where a character ends and the terminal decides where it
  actually ends; when the two disagree the grid shears from that column onward.
  These assertions are the agreement. Point them at a replacement before
  configuring it — `mix test test/character_width_conformance_test.exs`.
  """

  use ExUnit.Case, async: true

  alias Drafter.CharacterWidth

  @implementations [Drafter.CharacterWidth.Default, Drafter.CharacterWidth]

  defp each_implementation(assertion), do: Enum.each(@implementations, assertion)

  describe "the configured implementation" do
    test "is a module exporting the whole behaviour" do
      module = CharacterWidth.implementation()
      Code.ensure_loaded!(module)

      for {function, arity} <- [grapheme: 1, string: 1, codepoint: 1, printable_ascii?: 1] do
        assert function_exported?(module, function, arity),
               "#{inspect(module)} does not export #{function}/#{arity}"
      end
    end

    test "reports whether it is Drafter's own" do
      assert CharacterWidth.default?() ==
               (CharacterWidth.implementation() == CharacterWidth.Default)
    end

    test "dispatches to the implementation rather than measuring separately" do
      module = CharacterWidth.implementation()

      for text <- ["a", "日", "é", "👩‍👩‍👧", ""] do
        assert CharacterWidth.grapheme(text) == module.grapheme(text)
        assert CharacterWidth.string(text) == module.string(text)
      end
    end
  end

  describe "ASCII" do
    test "every printable ASCII character is one column" do
      each_implementation(fn module ->
        for codepoint <- 0x20..0x7E do
          assert module.codepoint(codepoint) == 1,
                 "#{inspect(module)} gave #{inspect(<<codepoint::utf8>>)} a width other than 1"
        end
      end)
    end

    test "printable_ascii? agrees with the width it implies" do
      each_implementation(fn module ->
        for text <- ["hello", "", "a b c", "~!@#"] do
          assert module.printable_ascii?(text)
          assert module.string(text) == byte_size(text)
        end
      end)
    end

    test "printable_ascii? rejects anything whose width is not its byte count" do
      each_implementation(fn module ->
        for text <- ["日本", "café", "a\tb", "\e[31m", "👍"] do
          refute module.printable_ascii?(text),
                 "#{inspect(module)} called #{inspect(text)} printable ASCII"
        end
      end)
    end
  end

  describe "zero-width characters" do
    test "C0 controls occupy no column" do
      each_implementation(fn module ->
        for codepoint <- [0x00, 0x07, 0x09, 0x0A, 0x1B, 0x1F] do
          assert module.codepoint(codepoint) == 0
        end
      end)
    end

    test "combining marks add nothing to their base" do
      each_implementation(fn module ->
        assert module.grapheme("é") == 1
        assert module.grapheme("à́̂") == 1
      end)
    end

    test "a zero-width space and a zero-width joiner occupy no column" do
      each_implementation(fn module ->
        assert module.codepoint(0x200B) == 0
        assert module.codepoint(0x200D) == 0
      end)
    end
  end

  describe "wide characters" do
    test "East Asian wide characters are two columns" do
      each_implementation(fn module ->
        for character <- ["日", "本", "語", "中", "한", "글", "あ", "ア"] do
          assert module.grapheme(character) == 2,
                 "#{inspect(module)} did not give #{character} two columns"
        end
      end)
    end

    test "fullwidth forms are two columns" do
      each_implementation(fn module ->
        assert module.codepoint(0xFF21) == 2
        assert module.codepoint(0xFF10) == 2
      end)
    end

    test "emoji with default emoji presentation are two columns" do
      each_implementation(fn module ->
        for character <- ["😀", "👍", "🎉"] do
          assert module.grapheme(character) == 2
        end
      end)
    end
  end

  describe "variation selectors override the base" do
    test "U+FE0F forces two columns" do
      each_implementation(fn module ->
        assert module.grapheme("❤️") == 2
      end)
    end

    test "U+FE0E forces one column" do
      each_implementation(fn module ->
        assert module.grapheme("❤︎") == 1
      end)
    end
  end

  describe "grapheme clusters" do
    test "a ZWJ sequence measures as one emoji" do
      each_implementation(fn module ->
        assert module.grapheme("👩‍👩‍👧") == 2
      end)
    end

    test "a skin-tone modifier adds nothing" do
      each_implementation(fn module ->
        assert module.grapheme("👍🏽") == 2
      end)
    end

    test "an empty string is zero columns" do
      each_implementation(fn module -> assert module.grapheme("") == 0 end)
    end
  end

  describe "strings" do
    test "a string is the sum of its grapheme clusters" do
      each_implementation(fn module ->
        for text <- ["hello", "日本語", "café", "a日b本c", "👍 ok", "", "étude"] do
          expected =
            text |> String.graphemes() |> Enum.reduce(0, &(&2 + module.grapheme(&1)))

          assert module.string(text) == expected,
                 "#{inspect(module)} disagreed with itself on #{inspect(text)}"
        end
      end)
    end

    test "mixed-width text measures as the sum of its parts" do
      each_implementation(fn module ->
        assert module.string("ab日") == 4
        assert module.string("日本語") == 6
        assert module.string("") == 0
      end)
    end

    test "no string ever measures negative" do
      each_implementation(fn module ->
        for text <- ["\e[31mred\e[0m", "\0\0", "​​", "🇬🇧"] do
          assert module.string(text) >= 0
        end
      end)
    end
  end
end
