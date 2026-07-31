defmodule Drafter.Widget.TextArea.Highlight do
  @moduledoc false

  alias Drafter.Draw.Segment

  @tree_sitter_available Code.ensure_loaded?(TreeSitterLanguagePack)

  @highlight_colors %{
    keyword: {200, 120, 220},
    string: {180, 200, 100},
    comment: {100, 120, 100},
    number: {180, 150, 100},
    function: {100, 180, 220}
  }

  @language_name_map %{
    sql: "sql",
    kdb: "q",
    q: "q",
    elixir: "elixir",
    python: "python",
    javascript: "javascript",
    js: "javascript",
    typescript: "typescript",
    ts: "typescript",
    rust: "rust",
    go: "go",
    ruby: "ruby",
    c: "c",
    cpp: "cpp",
    bash: "bash",
    shell: "bash",
    json: "json",
    yaml: "yaml",
    html: "html",
    css: "css"
  }

  @python_keywords ~w(def class if else elif for while return import from as try except finally with raise pass break continue lambda yield async await and or not in is True False None)
  @elixir_keywords ~w(def defp defmodule do end if else cond case when fn for with import alias require use true false nil and or not in)
  @javascript_keywords ~w(function const let var if else for while return import export from class extends new this true false null undefined async await try catch finally throw typeof instanceof)
  @sql_keywords ~w(SELECT FROM WHERE AND OR NOT IN IS NULL LIKE BETWEEN EXISTS HAVING GROUP BY ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE ALTER DROP INDEX VIEW JOIN INNER LEFT RIGHT OUTER FULL CROSS ON AS DISTINCT UNION ALL INTERSECT EXCEPT CASE WHEN THEN ELSE END COUNT SUM AVG MIN MAX CAST COALESCE NULLIF TRUE FALSE WITH RECURSIVE OVER PARTITION ROWS RANGE WINDOW FETCH NEXT ONLY FIRST LAST)
  @kdb_keywords ~w(select from where by update delete exec insert upsert if do while abs acos asin atan avg ceiling cos count cross div each enlist except exp fills first flip floor get group gtime hclose hcount hdel hopen hsym iasc idesc inter inv key keys last like lj log lower lsq ltrim mavg max maxs mcount md5 med meta min mins mmax mmin mmu mod msum neg next not null or over parse peach pj prd prds prev prior rand rank raze read0 read1 reciprocal reverse reval rotate rtrim save scan scov sdev select set show signum sin sqrt ss ssr string sublist sum sums sv system tables tan til trim type uj ungroup union upper value var view views vs wavg where within wj wsum xasc xbar xcol xcols xdesc xgroup xkey xlog xprev xrank)

  @spec highlight_line(String.t(), atom(), map()) :: [Segment.t()]
  def highlight_line(line, language, base_style) do
    regex_highlight_line(line, language, base_style)
  end

  @spec tree_sitter_available?() :: boolean()
  def tree_sitter_available?, do: @tree_sitter_available

  @spec tree_sitter_language_name(atom()) :: String.t() | nil
  def tree_sitter_language_name(language), do: Map.get(@language_name_map, language)

  @spec regex_highlight_line(String.t(), atom(), map()) :: [Segment.t()]
  defp regex_highlight_line(line, language, base_style) do
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
  def get_keywords(:sql), do: @sql_keywords
  def get_keywords(:kdb), do: @kdb_keywords
  def get_keywords(:q), do: @kdb_keywords
  def get_keywords(_), do: []

  @comment_prefixes %{
    python: "#",
    elixir: "#",
    javascript: "//",
    js: "//",
    sql: "--",
    kdb: "/",
    q: "/"
  }

  @cache :drafter_textarea_token_cache
  @cache_limit 5000

  @spec tokenize_line(String.t(), atom()) :: [{atom(), String.t()}]
  def tokenize_line(line, language) do
    ensure_cache()
    key = {language, line}

    case :ets.lookup(@cache, key) do
      [{^key, tokens}] ->
        tokens

      [] ->
        tokens = tokenize_uncached(line, language)
        cache_put(key, tokens)
        tokens
    end
  end

  defp tokenize_uncached(line, language) do
    prefix = Map.get(@comment_prefixes, language, "#")
    split_on_comment(line, prefix, language)
  end

  defp ensure_cache do
    case :ets.whereis(@cache) do
      :undefined ->
        try do
          :ets.new(@cache, [:named_table, :public, :set])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end

  defp cache_put(key, tokens) do
    if :ets.info(@cache, :size) > @cache_limit, do: :ets.delete_all_objects(@cache)
    :ets.insert(@cache, {key, tokens})
  end

  defp split_on_comment(line, prefix, language) do
    case String.split(line, prefix, parts: 2) do
      [^line] ->
        tokenize_code(line, language)

      [before, after_comment] ->
        tokenize_code(before, language) ++ [{:comment, prefix <> after_comment}]
    end
  end

  @spec tokenize_code(String.t(), atom()) :: [{atom(), String.t()}]
  def tokenize_code(code, language) do
    keywords = get_keywords(language)

    pattern = ~r/("[^"]*"|'[^']*'|\b\d+\.?\d*\b|\b\w+\b(?=\s*\()?|\b\w+\b|[^\s\w]+|\s+)/

    Regex.scan(pattern, code)
    |> Enum.map(fn [match | _] ->
      cond do
        String.starts_with?(match, "\"") or String.starts_with?(match, "'") ->
          {:string, match}

        Regex.match?(~r/^\d+\.?\d*$/, match) ->
          {:number, match}

        Regex.match?(~r/^\w+$/, match) and (match in keywords or String.upcase(match) in keywords) ->
          {:keyword, match}

        Regex.match?(~r/^\w+$/, match) ->
          {:identifier, match}

        true ->
          {:other, match}
      end
    end)
  end
end
