defmodule Drafter.Event.Delegation do
  @moduledoc """
  Utilities for routing events across the widget hierarchy.

  All functions accept a `WidgetHierarchy`, an event, and an optional selector, and
  return an updated `{hierarchy, actions}` pair after dispatching. Selectors can be
  an atom matching the lowercase widget type name, `{:class, class}` to match
  widgets whose state includes the class in a `:classes` list, or `{:id, id}` to
  match a specific widget id.

  Available dispatch functions:

  - `delegate_to_children/4` — send to matching direct children of a widget
  - `delegate_to_parent/3` — send to the direct parent of a widget
  - `delegate_to_siblings/4` — send to siblings (other children of the same parent)
  - `broadcast_to_descendants/3` — send to all descendants of a widget
  """

  alias Drafter.WidgetHierarchy

  def delegate_to_children(hierarchy, parent_id, event, selector) do
    children = WidgetHierarchy.get_children(hierarchy, parent_id)

    matching_children = filter_by_selector(children, hierarchy, selector)

    Enum.reduce(matching_children, {hierarchy, []}, fn child_id, {h, actions} ->
      hierarchy_with_focus = WidgetHierarchy.focus_widget(h, child_id)
      {new_h, new_actions} = WidgetHierarchy.handle_event(hierarchy_with_focus, event)
      {new_h, actions ++ new_actions}
    end)
  end

  def delegate_to_parent(hierarchy, child_id, event) do
    case WidgetHierarchy.get_parent(hierarchy, child_id) do
      nil ->
        {hierarchy, []}

      parent_id ->
        hierarchy_with_focus = WidgetHierarchy.focus_widget(hierarchy, parent_id)
        WidgetHierarchy.handle_event(hierarchy_with_focus, event)
    end
  end

  def delegate_to_siblings(hierarchy, widget_id, event, selector \\ :all) do
    case WidgetHierarchy.get_parent(hierarchy, widget_id) do
      nil ->
        {hierarchy, []}

      parent_id ->
        children = WidgetHierarchy.get_children(hierarchy, parent_id)
        siblings = Enum.reject(children, &(&1 == widget_id))

        matching_siblings =
          case selector do
            :all -> siblings
            _ -> filter_by_selector(siblings, hierarchy, selector)
          end

        Enum.reduce(matching_siblings, {hierarchy, []}, fn sibling_id, {h, actions} ->
          hierarchy_with_focus = WidgetHierarchy.focus_widget(h, sibling_id)
          {new_h, new_actions} = WidgetHierarchy.handle_event(hierarchy_with_focus, event)
          {new_h, actions ++ new_actions}
        end)
    end
  end

  def broadcast_to_descendants(hierarchy, root_id, event) do
    descendants = collect_descendants(hierarchy, root_id)

    Enum.reduce(descendants, {hierarchy, []}, fn widget_id, {h, actions} ->
      hierarchy_with_focus = WidgetHierarchy.focus_widget(h, widget_id)
      {new_h, new_actions} = WidgetHierarchy.handle_event(hierarchy_with_focus, event)
      {new_h, actions ++ new_actions}
    end)
  end

  defp collect_descendants(hierarchy, widget_id, acc \\ []) do
    children = WidgetHierarchy.get_children(hierarchy, widget_id)

    Enum.reduce(children, acc ++ children, fn child_id, descendants ->
      collect_descendants(hierarchy, child_id, descendants)
    end)
  end

  defp filter_by_selector(widget_ids, hierarchy, selector) do
    Enum.filter(widget_ids, fn widget_id ->
      matches_selector?(hierarchy, widget_id, selector)
    end)
  end

  defp matches_selector?(hierarchy, widget_id, selector) when is_atom(selector) do
    case WidgetHierarchy.get_widget_info(hierarchy, widget_id) do
      nil ->
        false

      widget_info ->
        widget_type = get_widget_type(widget_info.module)
        widget_type == Atom.to_string(selector)
    end
  end

  defp matches_selector?(hierarchy, widget_id, {:class, class}) do
    case WidgetHierarchy.get_widget_state(hierarchy, widget_id) do
      nil ->
        false

      state when is_map(state) ->
        classes = Map.get(state, :classes, [])
        class in classes

      _ ->
        false
    end
  end

  defp matches_selector?(_hierarchy, widget_id, {:id, id}) do
    widget_id == id
  end

  defp matches_selector?(_hierarchy, _widget_id, _selector), do: false

  defp get_widget_type(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end
end
