defmodule Drafter.Widget.Trait.Scrollable do
  @moduledoc """
  Trait that adds scrolling capability to a widget.

  Manages scroll offset, viewport dimensions, and scrollbar rendering.
  Handles mouse scroll events and keyboard navigation (arrow keys, Page Up/Down).
  """

  @behaviour Drafter.Widget.Trait

  alias Drafter.Draw.{Segment, Strip}

  defstruct direction: :vertical, step: 1, show_scrollbar: :auto, __spark_metadata__: nil

  @impl true
  def name, do: :scrollable

  @impl true
  def default_state do
    %{
      _scroll_offset_y: 0,
      _scroll_offset_x: 0,
      _content_height: 0,
      _content_width: 0,
      _viewport_height: 0,
      _viewport_width: 0,
      _show_scrollbar: :auto
    }
  end

  @impl true
  def dependencies, do: []

  @impl true
  def handles, do: [:scroll, :keyboard]

  @impl true
  def render_affecting_fields do
    [:_scroll_offset_y, :_scroll_offset_x, :_content_height, :_viewport_height]
  end

  @impl true
  def layout_static?, do: true

  @impl true
  def handle_event({:mouse, %{type: :scroll, direction: :up}}, trait_state, _widget_state) do
    step = 1
    new_offset = max(0, trait_state._scroll_offset_y - step)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:mouse, %{type: :scroll, direction: :down}}, trait_state, _widget_state) do
    step = 1
    max_offset = max(0, trait_state._content_height - trait_state._viewport_height)
    new_offset = min(max_offset, trait_state._scroll_offset_y + step)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:up, :"ArrowUp"] do
    new_offset = max(0, trait_state._scroll_offset_y - 1)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:down, :"ArrowDown"] do
    max_offset = max(0, trait_state._content_height - trait_state._viewport_height)
    new_offset = min(max_offset, trait_state._scroll_offset_y + 1)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:key, :page_up}, trait_state, _widget_state) do
    jump = max(1, trait_state._viewport_height - 1)
    new_offset = max(0, trait_state._scroll_offset_y - jump)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:key, :page_down}, trait_state, _widget_state) do
    jump = max(1, trait_state._viewport_height - 1)
    max_offset = max(0, trait_state._content_height - trait_state._viewport_height)
    new_offset = min(max_offset, trait_state._scroll_offset_y + jump)
    {:ok, %{trait_state | _scroll_offset_y: new_offset}}
  end

  def handle_event({:key, :home}, _trait_state, _widget_state) do
    {:ok, %{_scroll_offset_y: 0, _scroll_offset_x: 0}}
  end

  def handle_event({:key, :end}, trait_state, _widget_state) do
    max_offset = max(0, trait_state._content_height - trait_state._viewport_height)
    {:ok, %{trait_state | _scroll_offset_y: max_offset}}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end

  @impl true
  def pre_render(trait_state, _widget_state, rect) do
    updated = %{trait_state | _viewport_height: rect.height, _viewport_width: rect.width}

    show_scrollbar =
      case trait_state._show_scrollbar do
        :always -> true
        :never -> false
        :auto -> trait_state._content_height > rect.height
      end

    adjusted_rect =
      if show_scrollbar do
        %{rect | width: max(1, rect.width - 1)}
      else
        rect
      end

    {updated, adjusted_rect}
  end

  @impl true
  def post_render(strips, trait_state, _widget_state, rect) do
    offset = trait_state._scroll_offset_y
    visible = Enum.slice(strips, offset, rect.height)

    padding_count = rect.height - length(visible)

    padded =
      if padding_count > 0 do
        empty = Strip.new([Segment.new(String.duplicate(" ", rect.width))])
        visible ++ List.duplicate(empty, padding_count)
      else
        visible
      end

    content_height = length(strips)

    if content_height > rect.height do
      append_scrollbar(padded, offset, content_height, rect.height)
    else
      padded
    end
  end

  defp append_scrollbar(strips, offset, content_height, viewport_height) do
    thumb_height = max(1, div(viewport_height * viewport_height, content_height))
    thumb_start = div(offset * viewport_height, max(1, content_height))

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, idx} ->
      char =
        if idx >= thumb_start and idx < thumb_start + thumb_height do
          "┃"
        else
          "│"
        end

      scrollbar_segment = Segment.new(char)
      Strip.append(strip, scrollbar_segment)
    end)
  end
end
