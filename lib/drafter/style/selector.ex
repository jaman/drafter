defmodule Drafter.Style.Selector do
  @moduledoc false

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

  def new(opts \\ []) do
    %__MODULE__{
      widget_type: Keyword.get(opts, :widget_type),
      id: Keyword.get(opts, :id),
      classes: Keyword.get(opts, :classes, []),
      pseudo_classes: Keyword.get(opts, :pseudo_classes, []),
      part: Keyword.get(opts, :part)
    }
  end

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
  Whether two selector tokens name the same thing, comparing atoms and strings alike.

  A token stays a string when its atom does not exist yet — a widget type whose module
  has not been loaded, or an id belonging to a widget that has not rendered. Comparing
  by name means such a selector matches what it names and nothing else, rather than
  collapsing to `nil` and matching everything.
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

  def specificity(%__MODULE__{} = selector) do
    id_count = if selector.id, do: 1, else: 0
    class_count = length(selector.classes) + length(selector.pseudo_classes)
    type_count = if selector.widget_type, do: 1, else: 0
    part_count = if selector.part, do: 1, else: 0

    {id_count, class_count + part_count, type_count}
  end

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
