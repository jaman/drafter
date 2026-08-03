defmodule Drafter.Event.Delegation do
  @moduledoc """
  Routes an event to widgets related to a given widget in the hierarchy.

  Every function takes a `Drafter.WidgetHierarchy`, the id of the widget the
  relation is measured from, and an event tuple, and returns
  `{updated_hierarchy, actions}` where `actions` is the concatenation of the
  actions each recipient produced.

  Each recipient is focused before the event is handed to it, so the hierarchy
  returned has focus on the last widget dispatched to, not on the widget the call
  started from.

  A *selector* narrows the recipients:

  - an atom — matches widgets whose module's last name segment, downcased, equals
    the atom (`:button` matches `Drafter.Widget.Button`)
  - `{:class, class}` — matches widgets whose state map has `class` in its
    `:classes` list
  - `{:id, id}` — matches the widget with that id

  Anything else matches nothing. `delegate_to_siblings/4` additionally accepts
  `:all`, its default, meaning every sibling.

  - `delegate_to_children/4` — direct children of `parent_id` matching a selector
  - `delegate_to_parent/3` — the direct parent of `child_id`, if it has one
  - `delegate_to_siblings/4` — the other children of `widget_id`'s parent
  - `broadcast_to_descendants/3` — every descendant of `root_id`, unfiltered
  """

  alias Drafter.WidgetHierarchy

  @typedoc """
  Narrows which related widgets receive the event.

  An atom matches on widget type, `{:class, class}` on the widget state's
  `:classes` list, and `{:id, id}` on the widget id. Any other term matches
  nothing.
  """
  @type selector :: atom() | {:class, atom()} | {:id, WidgetHierarchy.widget_id()}

  @typedoc "The hierarchy after every dispatch, and the actions the recipients returned."
  @type result :: {WidgetHierarchy.t(), [term()]}

  @doc """
  Dispatch `event` to the direct children of `parent_id` that match `selector`.

  `selector` is required and grandchildren are never matched. Children that do not
  match are left untouched. Returns `{hierarchy, actions}` with the actions
  concatenated in child order.

  A `parent_id` that is not in the hierarchy has no children, so nothing is
  dispatched.
  """
  @spec delegate_to_children(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id(),
          term(),
          selector()
        ) :: result()
  def delegate_to_children(hierarchy, parent_id, event, selector) do
    children = WidgetHierarchy.get_children(hierarchy, parent_id)

    matching_children = filter_by_selector(children, hierarchy, selector)

    Enum.reduce(matching_children, {hierarchy, []}, fn child_id, {h, actions} ->
      hierarchy_with_focus = WidgetHierarchy.focus_widget(h, child_id)
      {new_h, new_actions} = WidgetHierarchy.handle_event(hierarchy_with_focus, event)
      {new_h, actions ++ new_actions}
    end)
  end

  @doc """
  Dispatch `event` to the direct parent of `child_id`.

  Returns `{hierarchy, []}` unchanged when `child_id` has no parent, which is the
  case for a root widget and for an id not in the hierarchy.
  """
  @spec delegate_to_parent(WidgetHierarchy.t(), WidgetHierarchy.widget_id(), term()) :: result()
  def delegate_to_parent(hierarchy, child_id, event) do
    case WidgetHierarchy.get_parent(hierarchy, child_id) do
      nil ->
        {hierarchy, []}

      parent_id ->
        hierarchy_with_focus = WidgetHierarchy.focus_widget(hierarchy, parent_id)
        WidgetHierarchy.handle_event(hierarchy_with_focus, event)
    end
  end

  @doc """
  Dispatch `event` to the other children of `widget_id`'s parent.

  `widget_id` itself never receives the event. `selector` defaults to `:all`,
  meaning every sibling, and is otherwise a `t:selector/0`. Returns
  `{hierarchy, []}` unchanged when `widget_id` has no parent.
  """
  @spec delegate_to_siblings(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id(),
          term(),
          selector() | :all
        ) :: result()
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

  @doc """
  Dispatch `event` to every descendant of `root_id`, at every depth.

  `root_id` itself does not receive it, and no selector is applied. A widget always
  receives the event before anything beneath it does.
  """
  @spec broadcast_to_descendants(WidgetHierarchy.t(), WidgetHierarchy.widget_id(), term()) ::
          result()
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
