defmodule Drafter.WidgetHierarchy.Scroll do
  @moduledoc false

  alias Drafter.WidgetHierarchy

  @spec register_scroll_container(WidgetHierarchy.t(), WidgetHierarchy.widget_id(), WidgetHierarchy.rect(), integer(), integer(), boolean()) :: WidgetHierarchy.t()
  def register_scroll_container(
        hierarchy,
        scroll_id,
        viewport_rect,
        content_height,
        content_width,
        click_to_scroll \\ false
      ) do
    scroll_info = %{
      viewport_rect: viewport_rect,
      content_height: content_height,
      content_width: content_width,
      click_to_scroll: click_to_scroll,
      scroll_exceptions: MapSet.new()
    }

    updated_containers = Map.put(hierarchy.scroll_containers, scroll_id, scroll_info)

    updated_containers =
      Enum.reduce(updated_containers, updated_containers, fn {existing_id, existing_info}, acc ->
        update_scroll_exceptions(acc, scroll_id, viewport_rect, click_to_scroll, existing_id, existing_info)
      end)

    %{hierarchy | scroll_containers: updated_containers}
  end

  def update_scroll_exceptions(acc, scroll_id, _viewport_rect, _click_to_scroll, scroll_id, _existing_info), do: acc

  def update_scroll_exceptions(acc, scroll_id, viewport_rect, _click_to_scroll, existing_id, %{click_to_scroll: true} = existing_info) do
    if viewport_rect_contains?(existing_info.viewport_rect, viewport_rect) do
      add_scroll_exception(acc, existing_id, scroll_id)
    else
      acc
    end
  end

  def update_scroll_exceptions(acc, scroll_id, viewport_rect, true, existing_id, existing_info) do
    if viewport_rect_contains?(viewport_rect, existing_info.viewport_rect) do
      add_scroll_exception(acc, scroll_id, existing_id)
    else
      acc
    end
  end

  def update_scroll_exceptions(acc, _scroll_id, _viewport_rect, _click_to_scroll, _existing_id, _existing_info), do: acc

  def add_scroll_exception(containers, container_id, exception_id) do
    Map.update!(containers, container_id, fn info ->
      %{info | scroll_exceptions: MapSet.put(info.scroll_exceptions, exception_id)}
    end)
  end

  def viewport_rect_contains?(outer, inner) do
    inner.x >= outer.x and
      inner.y >= outer.y and
      inner.x + inner.width <= outer.x + outer.width and
      inner.y + inner.height <= outer.y + outer.height
  end

  @spec set_widget_scroll_parent(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id(),
          WidgetHierarchy.widget_id()
        ) :: WidgetHierarchy.t()
  def set_widget_scroll_parent(hierarchy, widget_id, scroll_parent_id) do
    new_parents = Map.put(hierarchy.widget_scroll_parents, widget_id, scroll_parent_id)
    %{hierarchy | widget_scroll_parents: new_parents}
  end

  @spec get_widget_scroll_parent(WidgetHierarchy.t(), WidgetHierarchy.widget_id()) :: WidgetHierarchy.widget_id() | nil
  def get_widget_scroll_parent(hierarchy, widget_id) do
    Map.get(hierarchy.widget_scroll_parents, widget_id)
  end

  @spec get_scroll_container_info(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id()
        ) :: WidgetHierarchy.scroll_info() | nil
  def get_scroll_container_info(hierarchy, scroll_id) do
    Map.get(hierarchy.scroll_containers, scroll_id)
  end

  @spec update_scroll_container_content(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id(),
          integer(),
          integer()
        ) :: WidgetHierarchy.t()
  def update_scroll_container_content(hierarchy, scroll_id, content_height, content_width) do
    case Map.get(hierarchy.scroll_containers, scroll_id) do
      nil ->
        hierarchy

      info ->
        updated_info = %{info | content_height: content_height, content_width: content_width}
        new_scroll_containers = Map.put(hierarchy.scroll_containers, scroll_id, updated_info)
        %{hierarchy | scroll_containers: new_scroll_containers}
    end
  end

  def find_scroll_container_at(hierarchy, x, y) do
    candidates =
      Enum.filter(hierarchy.scroll_containers, fn {_id, info} ->
        v = info.viewport_rect
        x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height
      end)

    resolve_scroll_candidate(hierarchy, candidates)
  end

  def resolve_scroll_candidate(_hierarchy, []), do: nil
  def resolve_scroll_candidate(_hierarchy, [{id, %{click_to_scroll: false}}]), do: id

  def resolve_scroll_candidate(hierarchy, candidates) do
    sorted = Enum.sort_by(candidates, fn {_id, info} -> info.viewport_rect.width * info.viewport_rect.height end)
    Enum.find_value(sorted, &pick_scroll_candidate(hierarchy, candidates, &1))
  end

  def pick_scroll_candidate(hierarchy, candidates, {id, %{click_to_scroll: false}}) do
    if claimed_by_outer_click_to_scroll?(hierarchy, candidates, id), do: nil, else: id
  end

  def pick_scroll_candidate(hierarchy, _candidates, {id, _info}) do
    state = WidgetHierarchy.get_widget_state(hierarchy, id)
    if state && Map.get(state, :scroll_locked, false), do: id, else: nil
  end

  def claimed_by_outer_click_to_scroll?(hierarchy, candidates, inner_id) do
    Enum.any?(candidates, fn {outer_id, outer_info} ->
      outer_id != inner_id and
        outer_info.click_to_scroll and
        MapSet.member?(outer_info.scroll_exceptions, inner_id) and
        not scroll_locked?(hierarchy, outer_id)
    end)
  end

  def scroll_locked?(hierarchy, scroll_id) do
    state = WidgetHierarchy.get_widget_state(hierarchy, scroll_id)
    state != nil and Map.get(state, :scroll_locked, false)
  end

  def toggle_scroll_lock_at(hierarchy, x, y) do
    click_to_scroll_containers =
      Enum.filter(hierarchy.scroll_containers, fn {_id, info} ->
        info.click_to_scroll
      end)

    innermost =
      click_to_scroll_containers
      |> Enum.filter(fn {_id, info} ->
        v = info.viewport_rect
        x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height
      end)
      |> Enum.min_by(fn {_id, info} ->
        info.viewport_rect.width * info.viewport_rect.height
      end, fn -> nil end)

    case innermost do
      nil -> hierarchy
      {scroll_id, _info} -> toggle_scroll_lock(hierarchy, scroll_id)
    end
  end

  def toggle_scroll_lock(hierarchy, scroll_id) do
    case WidgetHierarchy.get_widget_state(hierarchy, scroll_id) do
      nil -> hierarchy
      state ->
        updated = %{state | scroll_locked: not state.scroll_locked}
        WidgetHierarchy.update_widget_state_in_hierarchy(hierarchy, scroll_id, updated)
    end
  end

  def clear_scroll_locks_outside(hierarchy, x, y) do
    Enum.reduce(hierarchy.scroll_containers, hierarchy, fn {scroll_id, info}, h ->
      maybe_clear_scroll_lock(h, scroll_id, info, x, y)
    end)
  end

  def maybe_clear_scroll_lock(h, _scroll_id, %{click_to_scroll: false}, _x, _y), do: h

  def maybe_clear_scroll_lock(h, scroll_id, info, x, y) do
    v = info.viewport_rect
    outside = not (x >= v.x and x < v.x + v.width and y >= v.y and y < v.y + v.height)
    clear_lock_if_outside(h, scroll_id, outside)
  end

  def clear_lock_if_outside(h, _scroll_id, false), do: h

  def clear_lock_if_outside(h, scroll_id, true) do
    case WidgetHierarchy.get_widget_state(h, scroll_id) do
      %{scroll_locked: true} = state ->
        updated = %{state | scroll_locked: false}
        WidgetHierarchy.update_widget_state_in_hierarchy(h, scroll_id, updated)
      _ -> h
    end
  end
end
