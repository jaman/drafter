defmodule Drafter.Style.Selector do
  @moduledoc """
  A parsed CSS-like selector, and the rules for matching one against a widget.

  A selector constrains five things, all optional. A constraint that is `nil` or
  empty is satisfied by anything.

  - `:widget_type` — the widget's type, written bare (`"button"`). A CamelCase name
    is converted with `Macro.underscore/1`, so `"DataTable"` and `"data_table"`
    parse alike.
  - `:id` — written `#name`
  - `:classes` — written `.name`, repeatable. Every class in the selector must be
    present on the widget; the widget may carry others.
  - `:pseudo_classes` — written `:name`. Recognised names are `:hover`, `:focus`,
    `:active`, `:disabled`, `:checked`, `:selected`, `:expanded` and `:collapsed`;
    any other `:name` is dropped during parsing rather than reported.
  - `:part` — written `::name`, naming a sub-region of a widget such as
    `::border`. A selector naming a part matches only a context whose `:part` is
    equal to it; a selector naming no part matches whether or not the context has
    one, which is what lets a widget's base rules apply underneath its part rules.

  ## Match context

  `matches?/2` takes a map, not a widget. It reads `:widget_type`, `:id`,
  `:classes` and `:part` directly, and derives the active pseudo-classes from the
  boolean keys `:hovered`, `:focused`, `:active`, `:disabled`, `:checked`,
  `:selected` and `:expanded`. `:collapsed` is active when `:expanded` is exactly
  `false`. Those keys must hold `true`, `false` or `nil`; any other value raises
  `FunctionClauseError`.

      iex> alias Drafter.Style.Selector
      iex> [selector] = Selector.parse("button:focus")
      iex> Selector.matches?(selector, %{widget_type: :button, focused: true})
      true
      iex> Selector.matches?(selector, %{widget_type: :button, focused: false})
      false

  ## Names as atoms or strings

  `parse/1` converts each name with `String.to_existing_atom/1` and keeps the
  string when no such atom exists. A selector therefore holds a mix, and matching
  compares names rather than terms — see `same_name?/2`.

  ## Descendant selectors

  `parse/1` splits a space-separated selector into one selector per token and
  returns them as a list. No ancestor relationship is recorded and none is checked:
  `Drafter.Style.Stylesheet` matches a rule when *any* selector in the list
  matches, so `"container button"` behaves as the selector group
  `"container, button"` rather than as a descendant selector.
  """

  @type pseudo_class ::
          :hover | :focus | :active | :disabled | :checked | :selected | :expanded | :collapsed

  @type t :: %__MODULE__{
          widget_type: atom() | nil,
          id: atom() | nil,
          classes: [atom()],
          pseudo_classes: [pseudo_class()],
          part: atom() | nil
        }

  defstruct widget_type: nil,
            id: nil,
            classes: [],
            pseudo_classes: [],
            part: nil

  @pseudo_classes [:hover, :focus, :active, :disabled, :checked, :selected, :expanded, :collapsed]

  @pseudo_class_map Map.new(@pseudo_classes, fn pc -> {Atom.to_string(pc), pc} end)

  @typedoc """
  A widget description `matches?/2` is run against.

  Every key is optional. Absent keys are treated as unset, except that a selector
  naming classes never matches a context without a `:classes` key.
  """
  @type context :: %{
          optional(:widget_type) => atom() | String.t() | nil,
          optional(:id) => atom() | String.t() | nil,
          optional(:classes) => [atom() | String.t()],
          optional(:part) => atom() | nil,
          optional(:hovered) => boolean() | nil,
          optional(:focused) => boolean() | nil,
          optional(:active) => boolean() | nil,
          optional(:disabled) => boolean() | nil,
          optional(:checked) => boolean() | nil,
          optional(:selected) => boolean() | nil,
          optional(:expanded) => boolean() | nil
        }

  @typedoc """
  A selector's weight, as `{ids, classes, types}`.

  Ordered as an Erlang term, so the tuples compare in CSS specificity order.
  """
  @type specificity :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  Build a selector from its parts.

  Options, all defaulting to the struct default:

    * `:widget_type` — atom or string, default `nil`
    * `:id` — atom or string, default `nil`
    * `:classes` — list of atoms or strings, default `[]`
    * `:pseudo_classes` — list of `t:pseudo_class/0`, default `[]`
    * `:part` — atom, default `nil`

  Nothing is validated: an unrecognised pseudo-class is stored as given and then
  never matches.

  ## Examples

      iex> Drafter.Style.Selector.new()
      %Drafter.Style.Selector{widget_type: nil, id: nil, classes: [], pseudo_classes: [], part: nil}

      iex> Drafter.Style.Selector.new(widget_type: :button, pseudo_classes: [:focus])
      %Drafter.Style.Selector{widget_type: :button, id: nil, classes: [], pseudo_classes: [:focus], part: nil}

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      widget_type: Keyword.get(opts, :widget_type),
      id: Keyword.get(opts, :id),
      classes: Keyword.get(opts, :classes, []),
      pseudo_classes: Keyword.get(opts, :pseudo_classes, []),
      part: Keyword.get(opts, :part)
    }
  end

  @doc """
  Parse a selector into a list of selectors, one per space-separated token.

  An atom is taken as a bare widget type and gives a one-element list. Order within
  a token does not matter: type, `#id`, `.class`, `::part` and `:pseudo_class` are
  each extracted independently, so `"button:focus::border"` and
  `"button::border:focus"` parse alike.

  Unrecognised pseudo-class names are dropped, and an unrecognised part name
  becomes `nil`, which drops the part constraint rather than failing the match.

  ## Examples

      iex> Drafter.Style.Selector.parse(:button)
      [%Drafter.Style.Selector{widget_type: :button, id: nil, classes: [], pseudo_classes: [], part: nil}]

      iex> [selector] = Drafter.Style.Selector.parse("DataTable::row:selected")
      iex> {selector.widget_type, selector.part, selector.pseudo_classes}
      {:data_table, :row, [:selected]}

      iex> Drafter.Style.Selector.parse("container button") |> length()
      2

      iex> [selector] = Drafter.Style.Selector.parse(":no_such_pseudo_class")
      iex> selector.pseudo_classes
      []

  """
  @spec parse(String.t() | atom()) :: [t()]
  def parse(selector_string) when is_binary(selector_string) do
    selector_string
    |> String.split(" ")
    |> Enum.map(&parse_single/1)
  end

  def parse(selector) when is_atom(selector) do
    [new(widget_type: selector)]
  end

  defp parse_single(str) do
    {widget_type, rest} = extract_widget_type(str)
    {id, rest} = extract_id(rest)
    {classes, rest} = extract_classes(rest)
    {part, rest} = extract_part(rest)
    {pseudo_classes, _rest} = extract_pseudo_classes(rest)

    new(
      widget_type: widget_type,
      id: id,
      classes: classes,
      pseudo_classes: pseudo_classes,
      part: part
    )
  end

  defp extract_widget_type(str) do
    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_]*)/, str) do
      [match, type] ->
        {name_or_atom(Macro.underscore(type)), String.replace_prefix(str, match, "")}

      _ ->
        {nil, str}
    end
  end

  defp extract_id(str) do
    case Regex.run(~r/^#([A-Za-z_][A-Za-z0-9_]*)/, str) do
      [match, id] -> {name_or_atom(id), String.replace_prefix(str, match, "")}
      _ -> {nil, str}
    end
  end

  defp extract_classes(str) do
    case Regex.scan(~r/\.([A-Za-z][A-Za-z0-9_-]*)/, str) do
      [] ->
        {[], str}

      matches ->
        classes = Enum.map(matches, fn [_, class] -> name_or_atom(class) end)
        cleaned = Regex.replace(~r/\.[A-Za-z][A-Za-z0-9_-]*/, str, "")
        {classes, cleaned}
    end
  end

  defp name_or_atom(name), do: safe_to_atom(name) || name

  defp extract_pseudo_classes(str) do
    case Regex.scan(~r/(?<!:):([a-z]+)/, str) do
      [] ->
        {[], str}

      matches ->
        pseudo_classes =
          matches
          |> Enum.map(fn [_, pc] -> Map.get(@pseudo_class_map, pc) end)
          |> Enum.reject(&is_nil/1)

        cleaned = Regex.replace(~r/(?<!:):[a-z]+/, str, "")
        {pseudo_classes, cleaned}
    end
  end

  defp extract_part(str) do
    case Regex.run(~r/::([a-z][a-z0-9_]*)/, str) do
      [match, part] -> {safe_to_atom(part), String.replace_prefix(str, match, "")}
      _ -> {nil, str}
    end
  end

  defp safe_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  @doc """
  Whether `context` satisfies every constraint `selector` sets.

  All five constraints must hold. An unset constraint is satisfied by anything, so
  `new/0` matches every context. Names are compared by `same_name?/2`, so a context
  may use strings where the selector uses atoms.

  A selector naming classes needs `context` to have a `:classes` key; a context
  without one never matches. A selector naming a part needs `context.part` to be
  equal to it, compared with `==` rather than by name. A selector naming no part
  matches whether or not the context has one.

  ## Examples

      iex> alias Drafter.Style.Selector
      iex> Selector.matches?(Selector.new(), %{})
      true

      iex> alias Drafter.Style.Selector
      iex> Selector.matches?(Selector.new(widget_type: :button), %{widget_type: "button"})
      true

      iex> alias Drafter.Style.Selector
      iex> Selector.matches?(Selector.new(classes: [:primary]), %{classes: [:primary, :large]})
      true
      iex> Selector.matches?(Selector.new(classes: [:primary]), %{classes: [:large]})
      false
      iex> Selector.matches?(Selector.new(classes: [:primary]), %{})
      false

      iex> alias Drafter.Style.Selector
      iex> Selector.matches?(Selector.new(pseudo_classes: [:collapsed]), %{expanded: false})
      true
      iex> Selector.matches?(Selector.new(pseudo_classes: [:collapsed]), %{})
      false

      iex> alias Drafter.Style.Selector
      iex> Selector.matches?(Selector.new(part: :border), %{part: :border})
      true
      iex> Selector.matches?(Selector.new(part: :border), %{})
      false
      iex> Selector.matches?(Selector.new(), %{part: :border})
      true

  """
  @spec matches?(t(), context()) :: boolean()
  def matches?(selector, context) do
    matches_widget_type?(selector, context) and
      matches_id?(selector, context) and
      matches_classes?(selector, context) and
      matches_pseudo_classes?(selector, context) and
      matches_part?(selector, context)
  end

  defp matches_widget_type?(%{widget_type: nil}, _context), do: true

  defp matches_widget_type?(%{widget_type: type}, context),
    do: same_name?(type, Map.get(context, :widget_type))

  defp matches_id?(%{id: nil}, _context), do: true
  defp matches_id?(%{id: id}, context), do: same_name?(id, Map.get(context, :id))

  defp matches_classes?(%{classes: []}, _context), do: true

  defp matches_classes?(%{classes: selector_classes}, %{classes: context_classes}) do
    Enum.all?(selector_classes, fn class ->
      Enum.any?(context_classes, &same_name?(class, &1))
    end)
  end

  defp matches_classes?(_, _), do: false

  @doc """
  Whether two selector tokens name the same thing.

  A token is an atom or a string; the two forms compare equal when their names are
  equal, so `:button` and `"button"` match. `nil` on either side is never a match.

  Parsed selectors hold a string wherever the corresponding atom does not yet exist
  in the VM — a widget type whose module has not been loaded, or an id belonging to
  a widget that has not rendered — so callers must not assume atoms.

  A term that is neither an atom nor a binary is named by `inspect/1`, so two equal
  such terms match and unequal ones do not.

  ## Examples

      iex> Drafter.Style.Selector.same_name?(:button, "button")
      true

      iex> Drafter.Style.Selector.same_name?("button", "label")
      false

      iex> Drafter.Style.Selector.same_name?(nil, nil)
      false

  """
  @spec same_name?(term(), term()) :: boolean()
  def same_name?(nil, _other), do: false
  def same_name?(_token, nil), do: false
  def same_name?(token, other), do: to_name(token) == to_name(other)

  defp to_name(value) when is_atom(value), do: Atom.to_string(value)
  defp to_name(value) when is_binary(value), do: value
  defp to_name(value), do: inspect(value)

  defp matches_pseudo_classes?(%{pseudo_classes: []}, _context), do: true

  defp matches_pseudo_classes?(%{pseudo_classes: selector_pcs}, context) do
    context_pcs = get_active_pseudo_classes(context)
    Enum.all?(selector_pcs, &(&1 in context_pcs))
  end

  defp matches_part?(%{part: nil}, _context), do: true
  defp matches_part?(%{part: part}, %{part: part}), do: true
  defp matches_part?(_, _), do: false

  defp get_active_pseudo_classes(context) do
    []
    |> maybe_add(:hover, context[:hovered])
    |> maybe_add(:focus, context[:focused])
    |> maybe_add(:active, context[:active])
    |> maybe_add(:disabled, context[:disabled])
    |> maybe_add(:checked, context[:checked])
    |> maybe_add(:selected, context[:selected])
    |> maybe_add(:expanded, context[:expanded])
    |> maybe_add(:collapsed, context[:expanded] == false)
  end

  defp maybe_add(list, _item, nil), do: list
  defp maybe_add(list, _item, false), do: list
  defp maybe_add(list, item, true), do: [item | list]

  @doc """
  The selector's weight, as `{ids, classes, types}`.

  `ids` is 1 when the selector names an id. `classes` counts the classes, the
  pseudo-classes and the part together. `types` is 1 when the selector names a
  widget type. The tuple orders as an Erlang term, so comparing two of them
  compares specificity.

  ## Examples

      iex> alias Drafter.Style.Selector
      iex> Selector.specificity(Selector.new())
      {0, 0, 0}

      iex> alias Drafter.Style.Selector
      iex> Selector.specificity(Selector.new(widget_type: :button))
      {0, 0, 1}

      iex> alias Drafter.Style.Selector
      iex> [selector] = Selector.parse("button.primary:focus::border")
      iex> Selector.specificity(selector)
      {0, 3, 1}

  """
  @spec specificity(t()) :: specificity()
  def specificity(%__MODULE__{} = selector) do
    id_count = if selector.id, do: 1, else: 0
    class_count = length(selector.classes) + length(selector.pseudo_classes)
    type_count = if selector.widget_type, do: 1, else: 0
    part_count = if selector.part, do: 1, else: 0

    {id_count, class_count + part_count, type_count}
  end

  @doc """
  Compare two selectors by specificity, as `:gt`, `:lt` or `:eq`.

  ## Examples

      iex> alias Drafter.Style.Selector
      iex> Selector.compare_specificity(Selector.new(id: :save), Selector.new(widget_type: :button))
      :gt

      iex> alias Drafter.Style.Selector
      iex> Selector.compare_specificity(Selector.new(widget_type: :button), Selector.new(widget_type: :label))
      :eq

  """
  @spec compare_specificity(t(), t()) :: :gt | :lt | :eq
  def compare_specificity(s1, s2) do
    spec1 = specificity(s1)
    spec2 = specificity(s2)

    cond do
      spec1 > spec2 -> :gt
      spec1 < spec2 -> :lt
      true -> :eq
    end
  end
end
