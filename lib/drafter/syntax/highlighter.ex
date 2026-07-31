defmodule Drafter.Syntax.Highlighter do
  @moduledoc false

  @type capture ::
          {pos_integer(), non_neg_integer(), pos_integer(), non_neg_integer(), String.t()}

  @callback highlight(source :: String.t(), language :: atom()) :: [capture()]

  @spec resolve_color(String.t(), map()) :: term() | nil
  def resolve_color(capture_name, syntax_colors) do
    capture_name
    |> specificity_chain()
    |> Enum.find_value(fn key -> Map.get(syntax_colors, key) end)
  end

  defp specificity_chain(capture_name) do
    parts = String.split(capture_name, ".")
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
