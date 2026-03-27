defmodule Drafter.WidgetHierarchy.HitTest do
  @moduledoc false

  alias Drafter.WidgetHierarchy

  @spec find_widget_at(WidgetHierarchy.t(), integer(), integer()) :: WidgetHierarchy.widget_id() | nil
  def find_widget_at(hierarchy, x, y) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    candidates =
      hierarchy.widget_rects
      |> Enum.reject(fn {id, _rect} -> MapSet.member?(hidden, id) end)
      |> Enum.map(fn {id, rect} ->
        {id, translate_rect_to_screen(hierarchy, id, rect)}
      end)
      |> Enum.filter(fn {_id, screen_rect} ->
        case screen_rect do
          nil ->
            false

          rect ->
            x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height
        end
      end)
      |> Enum.map(fn {id, rect} ->
        depth = widget_depth(hierarchy, id)
        area = rect.width * rect.height
        {id, rect, depth, area}
      end)

    case candidates do
      [] ->
        nil

      _ ->
        {widget_id, _rect, _depth, _area} =
          candidates
          |> Enum.sort_by(fn {_id, _rect, depth, area} -> {-depth, area} end)
          |> hd()

        widget_id
    end
  end

  def translate_rect_to_screen(hierarchy, widget_id, virtual_rect) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil -> virtual_rect
      scroll_parent_id -> clip_rect_to_scroll_viewport(hierarchy, scroll_parent_id, virtual_rect)
    end
  end

  def clip_rect_to_scroll_viewport(hierarchy, scroll_parent_id, virtual_rect) do
    scroll_info = Map.get(hierarchy.scroll_containers, scroll_parent_id)
    scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)
      compute_visible_rect(virtual_rect, viewport, scroll_y)
    else
      virtual_rect
    end
  end

  def compute_visible_rect(virtual_rect, viewport, scroll_y) do
    screen_y = virtual_rect.y - scroll_y
    screen_bottom = screen_y + virtual_rect.height

    if screen_bottom <= viewport.y or screen_y >= viewport.y + viewport.height do
      nil
    else
      visible_top = max(screen_y, viewport.y)
      visible_bottom = min(screen_bottom, viewport.y + viewport.height)
      %{x: virtual_rect.x, y: visible_top, width: virtual_rect.width, height: visible_bottom - visible_top}
    end
  end

  def widget_depth(hierarchy, id) do
    do_depth(hierarchy, id, 0)
  end

  def do_depth(_hierarchy, nil, acc), do: acc

  def do_depth(hierarchy, id, acc) do
    case Map.get(hierarchy.widgets, id) do
      nil -> acc
      %{parent: parent} -> do_depth(hierarchy, parent, acc + 1)
    end
  end
end
