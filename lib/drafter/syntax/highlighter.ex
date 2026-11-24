defmodule Drafter.Syntax.Highlighter do
  @moduledoc """
  The behaviour of a highlighter `Drafter.Widget.CodeView` takes as its
  `:highlighter`, and how a capture's name is coloured.

  `highlight(source, language)` returns tree-sitter captures, one per
  coloured stretch of `source`: `{start_line, start_column, end_line,
  end_column, name}`, lines from 1, columns in characters from 0, the end
  column exclusive, and `name` a tree-sitter highlight name such as
  `"keyword.function"` or `"string.special"`. A name is coloured by its
  most specific part the theme's syntax colours have: `"keyword.function"`
  by `:keyword_function`, or else `:keyword`, or else `:default`.

      defmodule MyHighlighter do
        @behaviour Drafter.Syntax.Highlighter

        @impl true
        def highlight(_source, _language), do: [{1, 0, 1, 3, "keyword"}]
      end
  """

  @type capture ::
          {pos_integer(), non_neg_integer(), pos_integer(), non_neg_integer(), String.t()}

  @callback highlight(source :: String.t(), language :: atom() | String.t() | nil) :: [capture()]

  @doc """
  The colour of a capture `name` in `syntax_colors`: the colour of its most
  specific part, its parts separated by `.` or `_`, then `:default`'s, or
  `nil` when the map has neither.
  """
  @spec resolve_color(String.t(), map()) :: term() | nil
  def resolve_color(capture_name, syntax_colors) do
    capture_name
    |> specificity_chain()
    |> Enum.find_value(fn key -> Map.get(syntax_colors, key) end)
  end

  defp specificity_chain(capture_name) do
    parts = String.split(capture_name, [".", "_"])
    count = length(parts)

    most_specific_first =
      count
      |> Range.new(1, -1)
      |> Enum.flat_map(fn n ->
        parts
        |> Enum.take(n)
        |> Enum.join("_")
        |> existing_atom()
      end)

    most_specific_first ++ [:default]
  end

  defp existing_atom(name) do
    [String.to_existing_atom(name)]
  rescue
    ArgumentError -> []
  end
end
