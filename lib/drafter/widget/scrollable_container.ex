defmodule Drafter.Widget.ScrollableContainer do
  @moduledoc """
  Renders a scrollbar track and thumb that represent a viewport into larger content.

  This widget renders only the scrollbar column itself; the scrollable content is
  managed externally. Update `:content_height`, `:viewport_height`, and
  `:scroll_offset_y` to keep the thumb position in sync with the visible region.
  Use `get_viewport/1` to read the current scroll state for passing to child
  rendering logic.

  Keyboard and mouse-wheel events scroll the viewport when focused.

  ## Options

    * `:content_height` - total content height in rows (default `0`)
    * `:content_width` - total content width in columns (default `0`)
    * `:viewport_height` - visible height in rows (default `10`)
    * `:viewport_width` - visible width in columns (default `80`)
    * `:show_vertical_scrollbar` - `:auto` (default, visible when needed), `:always`, `:never`
    * `:show_horizontal_scrollbar` - `:auto`, `:always`, `:never` (default)
    * `:child_widget_ids` - list of widget IDs whose scroll events bubble through this container
    * `:focused` - initial focus state (default `false`)

  ## Usage

      scrollable(content_height: 200, viewport_height: 20)
  """

  use Drafter.Widget,
    handles: [:keyboard, :scroll],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager
  alias Drafter.CharacterSet

  defstruct [
    :id,
    :scroll_offset_y,
    :scroll_offset_x,
    :content_height,
    :content_width,
    :viewport_height,
    :viewport_width,
    :focused,
    :show_vertical_scrollbar,
    :show_horizontal_scrollbar,
    :child_widget_ids,
    :dragging_scrollbar,
    :hovering_scrollbar,
    :drag_thumb_offset,
    :click_to_scroll,
    :scroll_locked
  ]

  def mount(props) do
    %__MODULE__{
      id: Map.get(props, :id),
      scroll_offset_y: 0,
      scroll_offset_x: 0,
      content_height: Map.get(props, :content_height, 0),
      content_width: Map.get(props, :content_width, 0),
      viewport_height: Map.get(props, :viewport_height, 10),
      viewport_width: Map.get(props, :viewport_width, 80),
      focused: Map.get(props, :focused, false),
      show_vertical_scrollbar: Map.get(props, :show_vertical_scrollbar, :auto),
      show_horizontal_scrollbar: Map.get(props, :show_horizontal_scrollbar, :never),
      child_widget_ids: Map.get(props, :child_widget_ids, []),
      dragging_scrollbar: false,
      hovering_scrollbar: false,
      drag_thumb_offset: 0,
      click_to_scroll: Map.get(props, :click_to_scroll, false),
      scroll_locked: false
    }
  end

  def update(props, state) do
    %{
      state
      | content_height: Map.get(props, :content_height, state.content_height),
        content_width: Map.get(props, :content_width, state.content_width),
        viewport_height: Map.get(props, :viewport_height, state.viewport_height),
        viewport_width: Map.get(props, :viewport_width, state.viewport_width),
        child_widget_ids: Map.get(props, :child_widget_ids, state.child_widget_ids),
        scroll_offset_y: Map.get(props, :scroll_offset_y, state.scroll_offset_y),
        scroll_offset_x: Map.get(props, :scroll_offset_x, state.scroll_offset_x)
    }
    |> clamp_scroll()
  end

  def render(state, rect) do
    theme = ThemeManager.get_current_theme()

    needs_scrollbar =
      state.content_height > state.viewport_height and
        state.show_vertical_scrollbar != :never

    if needs_scrollbar do
      render_with_scrollbar(state, rect, theme)
    else
      []
    end
  end

  defp render_with_scrollbar(state, rect, theme) do
    track_style =
      if state.click_to_scroll and state.scroll_locked,
        do: %{fg: theme.primary, bg: theme.surface},
        else: %{fg: theme.text_muted, bg: theme.surface}

    thumb_style = %{fg: theme.primary, bg: theme.primary}
    thumb_hover_style = %{fg: {255, 255, 255}, bg: {0, 150, 255}}
    thumb_drag_style = %{fg: {255, 255, 255}, bg: {0, 120, 200}}

    viewport_height = min(rect.height, state.viewport_height)
    {thumb_start, thumb_height} = get_thumb_position(state)

    Enum.map(0..(viewport_height - 1), fn row ->
      is_thumb = row >= thumb_start and row < thumb_start + thumb_height

      {char, style} =
        cond do
          is_thumb and state.dragging_scrollbar -> {CharacterSet.scroll(:thumb_drag), thumb_drag_style}
          is_thumb and state.hovering_scrollbar -> {CharacterSet.scroll(:thumb_hover), thumb_hover_style}
          is_thumb -> {CharacterSet.scroll(:thumb), thumb_style}
          true -> {CharacterSet.scroll(:track), track_style}
        end

      Strip.new([Segment.new(char, style)])
    end)
  end

  def handle_event(event, state) do
    case event do
      {:key, :up} ->
        scroll_by(state, 0, -1)

      {:key, :down} ->
        scroll_by(state, 0, 1)

      {:key, :page_up} ->
        scroll_by(state, 0, -state.viewport_height)

      {:key, :page_down} ->
        scroll_by(state, 0, state.viewport_height)

      {:key, :home} ->
        {:ok, %{state | scroll_offset_y: 0}}

      {:key, :end} ->
        max_scroll = max(0, state.content_height - state.viewport_height)
        {:ok, %{state | scroll_offset_y: max_scroll}}

      {:mouse, %{type: :scroll, direction: :up}} ->
        scroll_by(state, 0, -3)

      {:mouse, %{type: :scroll, direction: :down}} ->
        scroll_by(state, 0, 3)

      {:mouse, %{type: :mouse_down, x: x, y: y}} ->
        if x == 0 do
          {thumb_start, thumb_height} = get_thumb_position(state)

          if y >= thumb_start and y < thumb_start + thumb_height do
            {:ok, %{state | dragging_scrollbar: true, drag_thumb_offset: y - thumb_start}}
          else
            {:noreply, state}
          end
        else
          {:bubble, state}
        end

      {:mouse, %{type: :drag, y: y}} when state.dragging_scrollbar ->
        {_thumb_start, thumb_height} = get_thumb_position(state)
        desired_thumb_start = y - state.drag_thumb_offset
        max_thumb_start = max(1, state.viewport_height - thumb_height)
        scroll_ratio = desired_thumb_start / max_thumb_start
        max_scroll = max(0, state.content_height - state.viewport_height)
        new_offset = round(scroll_ratio * max_scroll)
        new_state = %{state | scroll_offset_y: max(0, min(max_scroll, new_offset))}
        {:ok, new_state, [:scroll_fast_render]}

      {:mouse, %{type: :mouse_up, x: x, y: y}} ->
        if state.dragging_scrollbar do
          {:ok, %{state | dragging_scrollbar: false, drag_thumb_offset: 0}}
        else
          if x == 0 do
            {thumb_start, thumb_height} = get_thumb_position(state)

            cond do
              y < thumb_start ->
                scroll_by(state, 0, -state.viewport_height)

              y >= thumb_start + thumb_height ->
                scroll_by(state, 0, state.viewport_height)

              true ->
                {:bubble, state}
            end
          else
            {:bubble, state}
          end
        end

      _ ->
        {:bubble, state}
    end
  end


  defp get_thumb_position(state) do
    viewport_height = state.viewport_height
    content_height = max(state.content_height, 1)

    viewport_ratio = min(1.0, viewport_height / content_height)
    thumb_height = max(1, round(viewport_height * viewport_ratio))

    max_scroll = max(1, content_height - viewport_height)
    scroll_ratio = if max_scroll > 0, do: state.scroll_offset_y / max_scroll, else: 0.0
    thumb_start = round(scroll_ratio * (viewport_height - thumb_height))

    {thumb_start, thumb_height}
  end

  defp scroll_by(state, dx, dy) do
    new_state = %{
      state
      | scroll_offset_x: state.scroll_offset_x + dx,
        scroll_offset_y: state.scroll_offset_y + dy
    }

    {:ok, clamp_scroll(new_state), [:scroll_fast_render]}
  end

  defp clamp_scroll(state) do
    max_scroll_y = max(0, state.content_height - state.viewport_height)
    max_scroll_x = max(0, state.content_width - state.viewport_width)

    %{
      state
      | scroll_offset_y: state.scroll_offset_y |> max(0) |> min(max_scroll_y),
        scroll_offset_x: state.scroll_offset_x |> max(0) |> min(max_scroll_x)
    }
  end

  def get_viewport(state) do
    %{
      scroll_y: state.scroll_offset_y,
      scroll_x: state.scroll_offset_x,
      viewport_height: state.viewport_height,
      viewport_width: state.viewport_width,
      content_height: state.content_height,
      content_width: state.content_width
    }
  end
end
