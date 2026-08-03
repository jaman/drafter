defmodule Drafter.Style.Stylesheet do
  @moduledoc """
  An ordered list of `{selectors, style}` rules, and the cascade that resolves them.

  A rule pairs a list of `Drafter.Style.Selector` structs with a `Drafter.Style`
  map. `compute_style/2` keeps the rules whose selectors match, sorts them by
  ascending specificity, and merges them left to right, so the most specific rule
  wins. Rules of equal specificity keep insertion order, so the one added last wins.

  A rule matches when *any* of its selectors matches — the list is a selector
  group, as written `"a, b"` in CSS.

      iex> alias Drafter.Style.Stylesheet
      iex> sheet = Stylesheet.new(%{"button" => %{color: :red}, "button:focus" => %{bold: true}})
      iex> Stylesheet.compute_style(sheet, %{widget_type: :button})
      %{color: :red}
      iex> Stylesheet.compute_style(sheet, %{widget_type: :button, focused: true})
      %{bold: true, color: :red}

  """

  alias Drafter.Style
  alias Drafter.Style.Selector

  @typedoc """
  Anything `new/1`, `add_rule/3` and `add_rules/2` accept where a selector is
  expected.

  A string or atom is handed to `Drafter.Style.Selector.parse/1`; a `Selector`
  struct is wrapped in a one-element list; a list is taken as already parsed.
  """
  @type selector_source :: String.t() | atom() | Selector.t() | [Selector.t()]

  @type rule :: {Selector.t() | [Selector.t()], Style.t()}

  @type t :: %__MODULE__{
          rules: [rule()]
        }

  defstruct rules: []

  @doc """
  A stylesheet holding `rules`.

  `rules` is a map or a list of `{selector, style}` pairs, `[]` by default. Each
  selector is parsed as `t:selector_source/0` and each style is filtered through
  `Drafter.Style.new/1`, which drops keys that are not style properties. A list
  entry that is not a two-element tuple is stored unchanged and will fail later in
  `compute_style/2`.

  Map order is undefined, so pass a list when rules of equal specificity must
  resolve in a known order.

  ## Examples

      iex> Drafter.Style.Stylesheet.new()
      %Drafter.Style.Stylesheet{rules: []}

      iex> sheet = Drafter.Style.Stylesheet.new([{"label", %{color: :red, nonsense: 1}}])
      iex> [{_selectors, style}] = sheet.rules
      iex> style
      %{color: :red}

  """
  @spec new(map() | [{selector_source(), map()}]) :: t()
  def new(rules \\ []) do
    %__MODULE__{rules: normalize_rules(rules)}
  end

  @doc """
  The stylesheet with one more rule appended.

  Appending, rather than prepending, is what makes a later rule win a specificity
  tie. `style` is filtered through `Drafter.Style.new/1`.

  ## Examples

      iex> alias Drafter.Style.Stylesheet
      iex> sheet =
      ...>   Stylesheet.new()
      ...>   |> Stylesheet.add_rule("label", %{color: :red})
      ...>   |> Stylesheet.add_rule("label", %{color: :blue})
      iex> Stylesheet.compute_style(sheet, %{widget_type: :label})
      %{color: :blue}

  """
  @spec add_rule(t(), selector_source(), map()) :: t()
  def add_rule(%__MODULE__{} = stylesheet, selector, style) do
    parsed_selector = parse_selector(selector)
    rule = {parsed_selector, Style.new(style)}
    %{stylesheet | rules: stylesheet.rules ++ [rule]}
  end

  @doc """
  The stylesheet with every rule in `rules` appended, in order.

  `rules` is a map or a list of `{selector, style}` pairs. Map order is undefined.

  ## Examples

      iex> alias Drafter.Style.Stylesheet
      iex> Stylesheet.new()
      ...> |> Stylesheet.add_rules([{"label", %{color: :red}}, {"button", %{bold: true}}])
      ...> |> Map.fetch!(:rules)
      ...> |> length()
      2

  """
  @spec add_rules(t(), map() | [{selector_source(), map()}]) :: t()
  def add_rules(%__MODULE__{} = stylesheet, rules) when is_list(rules) do
    Enum.reduce(rules, stylesheet, fn {selector, style}, acc ->
      add_rule(acc, selector, style)
    end)
  end

  def add_rules(%__MODULE__{} = stylesheet, rules) when is_map(rules) do
    rules
    |> Enum.to_list()
    |> then(&add_rules(stylesheet, &1))
  end

  @doc """
  A stylesheet holding the first's rules followed by the second's.

  Nothing is deduplicated, and the second sheet's rules win ties because they come
  later.

  ## Examples

      iex> alias Drafter.Style.Stylesheet
      iex> base = Stylesheet.new([{"label", %{color: :red}}])
      iex> override = Stylesheet.new([{"label", %{color: :blue}}])
      iex> Stylesheet.merge(base, override) |> Stylesheet.compute_style(%{widget_type: :label})
      %{color: :blue}

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = s1, %__MODULE__{} = s2) do
    %__MODULE__{rules: s1.rules ++ s2.rules}
  end

  @doc """
  The style `context` resolves to under this stylesheet.

  Matching rules are merged in ascending specificity order, so a more specific rule
  overrides a less specific one key by key. Returns `%{}` when nothing matches. See
  `Drafter.Style.Selector.matches?/2` for what a context may hold.

  ## Examples

      iex> alias Drafter.Style.Stylesheet
      iex> sheet = Stylesheet.new([{"button", %{color: :red}}, {"button.primary", %{color: :blue}}])
      iex> Stylesheet.compute_style(sheet, %{widget_type: :button, classes: [:primary]})
      %{color: :blue}
      iex> Stylesheet.compute_style(sheet, %{widget_type: :label})
      %{}

  """
  @spec compute_style(t(), Selector.context()) :: Style.t()
  def compute_style(%__MODULE__{} = stylesheet, context) do
    stylesheet.rules
    |> Enum.filter(fn {selectors, _style} -> matches_any?(selectors, context) end)
    |> Enum.sort_by(fn {selectors, _style} -> max_specificity(selectors) end)
    |> Enum.map(fn {_selectors, style} -> style end)
    |> Style.merge()
  end

  @doc """
  The style a named sub-region of a widget resolves to.

  Equivalent to `compute_style/2` on `context` with `:part` set to `part`,
  overwriting any `:part` already there. Rules naming no part still match, so the
  widget's own rules apply underneath the part's.

  ## Examples

      iex> alias Drafter.Style.Stylesheet
      iex> sheet =
      ...>   Stylesheet.new([
      ...>     {"text_input", %{color: :red}},
      ...>     {"text_input::border", %{bold: true}}
      ...>   ])
      iex> Stylesheet.compute_style_for_part(sheet, %{widget_type: :text_input}, :border)
      %{bold: true, color: :red}

  """
  @spec compute_style_for_part(t(), Selector.context(), atom()) :: Style.t()
  def compute_style_for_part(%__MODULE__{} = stylesheet, context, part) do
    part_context = Map.put(context, :part, part)
    compute_style(stylesheet, part_context)
  end

  defp normalize_rules(rules) when is_list(rules) do
    Enum.map(rules, fn
      {selector, style} -> {parse_selector(selector), Style.new(style)}
      other -> other
    end)
  end

  defp normalize_rules(rules) when is_map(rules) do
    rules
    |> Enum.map(fn {selector, style} -> {parse_selector(selector), Style.new(style)} end)
  end

  defp parse_selector(selector) when is_binary(selector), do: Selector.parse(selector)
  defp parse_selector(selector) when is_atom(selector), do: Selector.parse(selector)
  defp parse_selector(%Selector{} = selector), do: [selector]
  defp parse_selector(selectors) when is_list(selectors), do: selectors

  defp matches_any?(selectors, context) when is_list(selectors) do
    Enum.any?(selectors, &Selector.matches?(&1, context))
  end

  defp matches_any?(selector, context) do
    Selector.matches?(selector, context)
  end

  defp max_specificity(selectors) when is_list(selectors) do
    selectors
    |> Enum.map(&Selector.specificity/1)
    |> Enum.max()
  end

  defp max_specificity(selector) do
    Selector.specificity(selector)
  end
end
