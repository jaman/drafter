defmodule Drafter.WidgetHierarchy.HitTest do
  @moduledoc false

  alias Drafter.WidgetHierarchy

  @doc """
  The widget at screen position `{x, y}`, or `nil` when none covers it.

  Hidden widgets are skipped and widgets scrolled out of their container's viewport
  do not match. Where several overlap, the deepest wins, and among equally deep ones
  the smallest by area.
  """
  @spec find_widget_at(WidgetHierarchy.t(), integer(), integer()) ::
          WidgetHierarchy.widget_id() | nil
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

  @doc """
  A widget's rect in screen coordinates, or `nil` when it is scrolled out of view.

  A widget with no scroll parent has its virtual rect returned unchanged.
  """
  @spec translate_rect_to_screen(WidgetHierarchy.t(), WidgetHierarchy.widget_id(), map()) ::
          map() | nil
  def translate_rect_to_screen(hierarchy, widget_id, virtual_rect) do
    case Map.get(hierarchy.widget_scroll_parents, widget_id) do
      nil -> virtual_rect
      scroll_parent_id -> clip_rect_to_scroll_viewport(hierarchy, scroll_parent_id, virtual_rect)
    end
  end

  @doc """
  Clip a rect to its scroll container's viewport, returning `nil` when nothing is left.

  The rect is returned unchanged when the container has no registered scroll info or
  its widget state is unavailable.
  """
  @spec clip_rect_to_scroll_viewport(
          WidgetHierarchy.t(),
          WidgetHierarchy.widget_id(),
          map()
        ) :: map() | nil
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

  @doc """
  The visible part of a rect scrolled by `scroll_y` within `viewport`.

  Only the vertical extent is clipped; `x` and `width` pass through. Returns `nil`
  when the rect falls entirely above or below the viewport.
  """
  @spec compute_visible_rect(map(), map(), integer()) :: map() | nil
  def compute_visible_rect(virtual_rect, viewport, scroll_y) do
    screen_y = virtual_rect.y - scroll_y
    screen_bottom = screen_y + virtual_rect.height

    if screen_bottom <= viewport.y or screen_y >= viewport.y + viewport.height do
      nil
    else
      visible_top = max(screen_y, viewport.y)
      visible_bottom = min(screen_bottom, viewport.y + viewport.height)

      %{
        x: virtual_rect.x,
        y: visible_top,
        width: virtual_rect.width,
        height: visible_bottom - visible_top
      }
    end
  end

  @doc """
  How many widgets deep `id` sits, counting itself.

  A widget the hierarchy does not hold is depth `0`; a root widget is depth `1`.
  """
  @spec widget_depth(WidgetHierarchy.t(), WidgetHierarchy.widget_id()) :: non_neg_integer()
  def widget_depth(hierarchy, id) do
    do_depth(hierarchy, id, 0)
  end

  @doc "Walk up the parent chain from `id`, adding one to `acc` per widget found."
  @spec do_depth(WidgetHierarchy.t(), WidgetHierarchy.widget_id() | nil, non_neg_integer()) ::
          non_neg_integer()
  def do_depth(_hierarchy, nil, acc), do: acc

  def do_depth(hierarchy, id, acc) do
    case Map.get(hierarchy.widgets, id) do
      nil -> acc
      %{parent: parent} -> do_depth(hierarchy, parent, acc + 1)
    end
  end
end
