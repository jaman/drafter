defmodule Drafter.SyntaxTest do
  use ExUnit.Case, async: true

  alias Drafter.Syntax.{ElixirHighlighter, Highlighter, TSFeatures}

  describe "Highlighter.resolve_color/2" do
    test "falls back from specific to general" do
      colors = %{function: {0, 255, 0}}
      assert Highlighter.resolve_color("function.builtin", colors) == {0, 255, 0}
    end

    test "prefers most specific key" do
      colors = %{function: {0, 255, 0}, function_builtin: {0, 0, 255}}
      assert Highlighter.resolve_color("function.builtin", colors) == {0, 0, 255}
    end
  end

  describe "ElixirHighlighter" do
    test "returns empty list for unknown language" do
      assert ElixirHighlighter.highlight("defmodule Foo do\nend", :python) == []
    end

    test "each capture is a 5-tuple with correct types" do
      captures = ElixirHighlighter.highlight("def foo, do: :ok", :elixir)

      Enum.each(captures, fn {sl, sc, el, ec, name} ->
        assert is_integer(sl) and sl >= 1
        assert is_integer(sc) and sc >= 0
        assert is_integer(el) and el >= sl
        assert is_integer(ec) and ec >= 0
        assert is_binary(name)
      end)
    end

    test "recovers gracefully from invalid source" do
      captures = ElixirHighlighter.highlight("\"unclosed string", :elixir)
      assert captures == []
    end

    test "identifies keywords" do
      captures = ElixirHighlighter.highlight("defmodule Foo do\nend", :elixir)
      names = Enum.map(captures, fn {_, _, _, _, name} -> name end)
      assert "keyword" in names
    end

    test "identifies numbers" do
      captures = ElixirHighlighter.highlight("x = 42", :elixir)
      names = Enum.map(captures, fn {_, _, _, _, name} -> name end)
      assert "number" in names
    end
  end

  describe "TSFeatures.build/1" do
    test "stores single-line highlight spans" do
      captures = [{1, 0, 1, 9, "keyword"}]
      result = TSFeatures.build(captures)
      spans = TSFeatures.get_spans(result, 1)
      assert [{0, 9, :keyword}] = spans
    end

    test "expands multi-line captures across lines" do
      captures = [{1, 5, 3, 4, "string"}]
      result = TSFeatures.build(captures)

      line1 = TSFeatures.get_spans(result, 1)
      line2 = TSFeatures.get_spans(result, 2)
      line3 = TSFeatures.get_spans(result, 3)

      assert Enum.any?(line1, fn {sc, _ec, type} -> sc == 5 and type == :string end)
      assert Enum.any?(line2, fn {sc, _ec, type} -> sc == 0 and type == :string end)
      assert Enum.any?(line3, fn {_sc, ec, type} -> ec == 4 and type == :string end)
    end

    test "separates fold captures from highlights" do
      captures = [{1, 0, 5, 3, "fold.default"}]
      result = TSFeatures.build(captures)
      assert result.folds != []
      assert TSFeatures.get_spans(result, 1) == []
    end

    test "separates symbol captures from highlights" do
      captures = [{2, 0, 2, 10, "symbol.function"}]
      result = TSFeatures.build(captures)
      assert result.symbols != []
      assert TSFeatures.get_spans(result, 2) == []
    end

    test "get_spans returns empty list for line with no highlights" do
      result = TSFeatures.build([])
      assert TSFeatures.get_spans(result, 99) == []
    end
  end
end
