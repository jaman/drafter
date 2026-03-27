defmodule Drafter.Widget.TextArea.Highlight do
  @moduledoc false

  alias Drafter.Draw.Segment

  @highlight_colors %{
    keyword: {200, 120, 220},
    string: {180, 200, 100},
    comment: {100, 120, 100},
    number: {180, 150, 100},
    function: {100, 180, 220}
  }

  @python_keywords ~w(def class if else elif for while return import from as try except finally with raise pass break continue lambda yield async await and or not in is True False None)
  @elixir_keywords ~w(def defp defmodule do end if else cond case when fn for with import alias require use true false nil and or not in)
  @javascript_keywords ~w(function const let var if else for while return import export from class extends new this true false null undefined async await try catch finally throw typeof instanceof)

  @spec highlight_line(String.t(), atom(), map()) :: [Segment.t()]
  def highlight_line(line, language, base_style) do
    keywords = get_keywords(language)
    bg = base_style[:bg] || {40, 40, 40}
    default_fg = base_style[:fg] || {200, 200, 200}

    tokenize_line(line, language)
    |> Enum.map(fn {type, text} ->
      color = token_color(type, text, keywords, default_fg)
      Segment.new(text, %{fg: color, bg: bg})
    end)
  end

  @spec token_color(atom(), String.t(), [String.t()], tuple()) :: tuple()
  def token_color(:keyword, text, keywords, default_fg) do
    if text in keywords, do: @highlight_colors.keyword, else: default_fg
  end

  def token_color(type, _text, _keywords, default_fg) do
    Map.get(@highlight_colors, type, default_fg)
  end

  @spec get_keywords(atom()) :: [String.t()]
  def get_keywords(:python), do: @python_keywords
  def get_keywords(:elixir), do: @elixir_keywords
  def get_keywords(:javascript), do: @javascript_keywords
  def get_keywords(:js), do: @javascript_keywords
  def get_keywords(_), do: []

  @spec tokenize_line(String.t(), atom()) :: [{atom(), String.t()}]
  def tokenize_line(line, language) do
    comment_prefix =
      case language do
        :python -> "#"
        :elixir -> "#"
        :javascript -> "//"
        :js -> "//"
        _ -> "#"
      end

    if String.contains?(line, comment_prefix) do
      [before_comment, comment_text] = String.split(line, comment_prefix, parts: 2)
      tokenize_code(before_comment, language) ++ [{:comment, comment_prefix <> comment_text}]
    else
      tokenize_code(line, language)
    end
  end

  @spec tokenize_code(String.t(), atom()) :: [{atom(), String.t()}]
  def tokenize_code(code, language) do
    keywords = get_keywords(language)

    pattern = ~r/("[^"]*"|'[^']*'|\b\d+\.?\d*\b|\b\w+\b(?=\s*\()?|\b\w+\b|[^\s\w"']+|\s+)/

    Regex.scan(pattern, code)
    |> Enum.map(fn [match] ->
      cond do
        String.starts_with?(match, "\"") or String.starts_with?(match, "'") ->
          {:string, match}

        Regex.match?(~r/^\d+\.?\d*$/, match) ->
          {:number, match}

        Regex.match?(~r/^\w+$/, match) and match in keywords ->
          {:keyword, match}

        Regex.match?(~r/^\w+$/, match) ->
          {:identifier, match}

        true ->
          {:other, match}
      end
    end)
  end
end
