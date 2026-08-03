defmodule Drafter.WidgetHierarchy.Query do
  @moduledoc false

  alias Drafter.Style
  alias Drafter.WidgetHierarchy

  @doc """
  Every widget id matching a CSS-like `selector`.

  The selector is parsed by `Drafter.Style.Selector.parse/1`, so a comma-separated
  list matches any of its parts. Results come back in map order, which is not the
  render order.
  """
  @spec query_all(WidgetHierarchy.t(), String.t()) :: [WidgetHierarchy.widget_id()]
  def query_all(hierarchy, selector) do
    parsed = Style.Selector.parse(selector)

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      matches_selector?(widget_id, widget_info, parsed)
    end)
    |> Enum.map(fn {widget_id, _} -> widget_id end)
  end

  @doc """
  The first widget id matching `selector`, or `nil`.

  "First" is whichever `query_all/2` returns first, which is not necessarily the
  first in render order.
  """
  @spec query_one(WidgetHierarchy.t(), String.t()) :: WidgetHierarchy.widget_id() | nil
  def query_one(hierarchy, selector) do
    case query_all(hierarchy, selector) do
      [widget_id | _] -> widget_id
      [] -> nil
    end
  end

  @doc "Whether a widget matches any selector in the parsed list."
  @spec matches_selector?(WidgetHierarchy.widget_id(), map(), [Style.Selector.t()]) :: boolean()
  def matches_selector?(widget_id, widget_info, selectors) when is_list(selectors) do
    Enum.any?(selectors, &matches_single_selector?(widget_id, widget_info, &1))
  end

  @doc "Whether a widget matches one selector's type, id and class parts, all of which must hold."
  @spec matches_single_selector?(WidgetHierarchy.widget_id(), map(), Style.Selector.t()) ::
          boolean()
  def matches_single_selector?(widget_id, widget_info, %Style.Selector{} = selector) do
    matches_type?(widget_info.module, selector.widget_type) and
      matches_id?(widget_id, selector.id) and
      matches_classes?(widget_info.state, selector.classes)
  end

  @doc "Whether a widget module's underscored short name matches `type`. A `nil` type matches anything."
  @spec matches_type?(module(), atom() | String.t() | nil) :: boolean()
  def matches_type?(_module, nil), do: true

  def matches_type?(module, type) do
    Style.Selector.same_name?(module_to_type_name(module), type)
  end

  @doc "Whether a widget id matches `id`. A `nil` id matches anything."
  @spec matches_id?(WidgetHierarchy.widget_id(), atom() | String.t() | nil) :: boolean()
  def matches_id?(_widget_id, nil), do: true

  def matches_id?(widget_id, id) do
    Style.Selector.same_name?(widget_id, id)
  end

  @doc """
  Whether a widget's state carries every class in `classes`.

  Classes are read from the state's `:classes` list, defaulting to `[]`. An empty
  `classes` list matches anything.
  """
  @spec matches_classes?(map(), [atom() | String.t()]) :: boolean()
  def matches_classes?(_state, []), do: true

  def matches_classes?(state, classes) do
    widget_classes = Map.get(state, :classes, [])

    Enum.all?(classes, fn class ->
      Enum.any?(widget_classes, &Style.Selector.same_name?(class, &1))
    end)
  end

  @doc """
  The selector type name for a widget module: its last segment, underscored, as an atom.

  ## Examples

      iex> Drafter.WidgetHierarchy.Query.module_to_type_name(Drafter.Widget.ProgressBar)
      :progress_bar

  """
  @spec module_to_type_name(module()) :: atom()
  def module_to_type_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
