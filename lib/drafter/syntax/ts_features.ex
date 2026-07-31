defmodule Drafter.Syntax.TSFeatures do
  @moduledoc """
  Parses Tree-sitter-style captures into structured highlight, fold, symbol, and textobject data.
  """

  @type capture ::
          {pos_integer(), non_neg_integer(), pos_integer(), non_neg_integer(), String.t()}

  @type span :: {non_neg_integer(), non_neg_integer(), atom()}

  @type t :: %__MODULE__{
          highlights: %{pos_integer() => [span()]},
          folds: list(),
          symbols: list(),
          textobjects: list()
        }

  defstruct highlights: %{},
            folds: [],
            symbols: [],
            textobjects: []

  @spec build([capture()]) :: t()
  def build(captures) do
    highlights = build_highlights(captures)
    folds = build_folds(captures)
    symbols = build_symbols(captures)
    textobjects = build_textobjects(captures)

    %__MODULE__{
      highlights: highlights,
      folds: folds,
      symbols: symbols,
      textobjects: textobjects
    }
  end

  @spec get_spans(t(), pos_integer()) :: [span()]
  def get_spans(%__MODULE__{highlights: highlights}, line) do
    Map.get(highlights, line, [])
  end

  @spec highlight_type?(String.t()) :: boolean()
  def highlight_type?(name) do
    not fold_type?(name) and not symbol_type?(name) and not textobject_type?(name)
  end

  defp build_highlights(captures) do
    captures
    |> Enum.filter(fn {_sl, _sc, _el, _ec, name} -> highlight_type?(name) end)
    |> Enum.reduce(%{}, fn {sl, sc, el, ec, name}, acc ->
      capture_type = capture_name_to_atom(name)
      add_spans_for_capture(acc, sl, sc, el, ec, capture_type)
    end)
  end

  defp add_spans_for_capture(acc, sl, sc, el, ec, capture_type) when sl == el do
    spans = Map.get(acc, sl, [])
    Map.put(acc, sl, spans ++ [{sc, ec, capture_type}])
  end

  defp add_spans_for_capture(acc, sl, sc, el, ec, capture_type) do
    first_line_spans = Map.get(acc, sl, [])
    acc = Map.put(acc, sl, first_line_spans ++ [{sc, :eol, capture_type}])

    acc =
      Enum.reduce((sl + 1)..(el - 1), acc, fn line, a ->
        line_spans = Map.get(a, line, [])
        Map.put(a, line, line_spans ++ [{0, :eol, capture_type}])
      end)

    last_line_spans = Map.get(acc, el, [])
    Map.put(acc, el, last_line_spans ++ [{0, ec, capture_type}])
  end

  defp build_folds(captures) do
    captures
    |> Enum.filter(fn {_sl, _sc, _el, _ec, name} -> fold_type?(name) end)
    |> Enum.map(fn {sl, _sc, el, _ec, _name} -> {sl, el} end)
  end

  defp build_symbols(captures) do
    captures
    |> Enum.filter(fn {_sl, _sc, _el, _ec, name} -> symbol_type?(name) end)
    |> Enum.map(fn {sl, sc, _el, _ec, name} -> {sl, sc, capture_name_to_atom(name)} end)
  end

  defp build_textobjects(captures) do
    captures
    |> Enum.filter(fn {_sl, _sc, _el, _ec, name} -> textobject_type?(name) end)
    |> Enum.map(fn {sl, sc, el, ec, name} -> {sl, sc, el, ec, capture_name_to_atom(name)} end)
  end

  defp fold_type?(name), do: String.starts_with?(name, "fold")

  defp symbol_type?(name), do: String.starts_with?(name, "symbol")

  defp textobject_type?(name), do: String.starts_with?(name, "textobject")

  defp capture_name_to_atom(name) do
    name
    |> String.replace(".", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :unknown
  end
end
