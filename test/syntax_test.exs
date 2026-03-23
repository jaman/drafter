defmodule Drafter.SyntaxTest do
  use ExUnit.Case, async: true

  alias Drafter.Syntax.{ElixirHighlighter, Highlighter, PlainHighlighter, TSFeatures}

  @treesitter_available Code.ensure_loaded?(:tree_sitter) and
                          function_exported?(:tree_sitter, :parse, 2)

  describe "Highlighter.resolve_color/2" do
    test "resolves exact atom key" do
      colors = %{keyword: {255, 0, 0}}
      assert Highlighter.resolve_color("keyword", colors) == {255, 0, 0}
    end

    test "falls back from specific to general" do
      colors = %{function: {0, 255, 0}}
      assert Highlighter.resolve_color("function.builtin", colors) == {0, 255, 0}
    end

    test "returns default when nothing specific matches" do
      colors = %{default: {128, 128, 128}}
      assert Highlighter.resolve_color("something.unknown", colors) == {128, 128, 128}
    end

    test "returns nil when no match at all" do
      assert Highlighter.resolve_color("unknown", %{}) == nil
    end

    test "prefers most specific key" do
      colors = %{function: {0, 255, 0}, function_builtin: {0, 0, 255}}
      assert Highlighter.resolve_color("function.builtin", colors) == {0, 0, 255}
    end
  end

  describe "PlainHighlighter" do
    test "always returns empty captures" do
      assert PlainHighlighter.highlight("defmodule Foo do\nend", :elixir) == []
      assert PlainHighlighter.highlight("any text", :text) == []
    end
  end

  describe "ElixirHighlighter" do
    test "returns empty list for unknown language" do
      assert ElixirHighlighter.highlight("defmodule Foo do\nend", :python) == []
    end

    test "returns captures for elixir language" do
      source = "defmodule Foo do\n  def bar, do: :ok\nend"
      captures = ElixirHighlighter.highlight(source, :elixir)
      assert is_list(captures)
      assert captures != []
    end

    test "returns captures for exs language" do
      captures = ElixirHighlighter.highlight("x = 42", :exs)
      assert is_list(captures)
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
    test "builds empty features from empty captures" do
      result = TSFeatures.build([])
      assert result.highlights == %{}
      assert result.folds == []
      assert result.symbols == []
      assert result.textobjects == []
    end

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

  describe "tree-sitter integration" do
    test "tree-sitter availability is detectable" do
      assert is_boolean(@treesitter_available)
    end

    if @treesitter_available do
      test "tree-sitter highlighter returns structured captures" do
        source = "defmodule Example do\n  def hello, do: :world\nend"
        captures = :tree_sitter.highlight(source, :elixir)
        assert is_list(captures)

        Enum.each(captures, fn {sl, sc, el, ec, name} ->
          assert is_integer(sl)
          assert is_integer(sc)
          assert is_integer(el)
          assert is_integer(ec)
          assert is_binary(name)
        end)

        features = TSFeatures.build(captures)
        assert is_map(features.highlights)
      end
    else
      test "without tree-sitter, ElixirHighlighter provides built-in highlighting" do
        source = "defmodule Example do\n  def hello, do: :world\nend"
        captures = ElixirHighlighter.highlight(source, :elixir)
        assert is_list(captures)
        assert captures != []
        features = TSFeatures.build(captures)
        assert map_size(features.highlights) > 0
      end

      test "without tree-sitter, PlainHighlighter degrades to no highlighting" do
        source = "defmodule Example do\n  def hello, do: :world\nend"
        captures = PlainHighlighter.highlight(source, :elixir)
        assert captures == []
        features = TSFeatures.build(captures)
        assert features.highlights == %{}
      end
    end
  end
end
