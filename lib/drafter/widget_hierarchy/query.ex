defmodule Drafter.WidgetHierarchy.Query do
  @moduledoc false

  alias Drafter.Style
  alias Drafter.WidgetHierarchy

  @spec query_all(WidgetHierarchy.t(), String.t()) :: [WidgetHierarchy.widget_id()]
  def query_all(hierarchy, selector) do
    parsed = Style.Selector.parse(selector)

    hierarchy.widgets
    |> Enum.filter(fn {widget_id, widget_info} ->
      matches_selector?(widget_id, widget_info, parsed)
    end)
    |> Enum.map(fn {widget_id, _} -> widget_id end)
  end

  @spec query_one(WidgetHierarchy.t(), String.t()) :: WidgetHierarchy.widget_id() | nil
  def query_one(hierarchy, selector) do
    case query_all(hierarchy, selector) do
      [widget_id | _] -> widget_id
      [] -> nil
    end
  end

  def matches_selector?(widget_id, widget_info, selectors) when is_list(selectors) do
    Enum.any?(selectors, &matches_single_selector?(widget_id, widget_info, &1))
  end

  def matches_single_selector?(widget_id, widget_info, %Style.Selector{} = selector) do
    matches_type?(widget_info.module, selector.widget_type) and
      matches_id?(widget_id, selector.id) and
      matches_classes?(widget_info.state, selector.classes)
  end

  def matches_type?(_module, nil), do: true

  def matches_type?(module, type) when is_atom(type) do
    type_name = module_to_type_name(module)
    type_name == type
  end

  def matches_id?(_widget_id, nil), do: true

  def matches_id?(widget_id, id) when is_atom(id) do
    widget_id == id
  end

  def matches_classes?(_state, []), do: true

  def matches_classes?(state, classes) do
    widget_classes = Map.get(state, :classes, [])
    Enum.all?(classes, &(&1 in widget_classes))
  end

  def module_to_type_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
