defmodule Drafter.Widget.ScrollableContainer do
  @moduledoc """
  Tracks the scroll position of a viewport and renders its scrollbars.

  This widget occupies only the one-column scrollbar strip at the right edge of
  the scrollable region and draws the track and thumb there. It does not render
  the content: children are laid out separately into the remaining width, and
  the container holds the offsets that position them.

  The thumb position is a function of `:content_height`, `:viewport_height` and
  `:scroll_offset_y`. Keep all three current — `update/2` accepts them and
  clamps the offsets to the content — or the thumb will not match what is on
  screen. `get_viewport/1` returns the current scroll state for child rendering.

  Keyboard and mouse-wheel events scroll the viewport when focused.

  ## Component tag

  This module has no `component_tag/0` and is not reached through the widget
  registry. `Drafter.App` builds it as the element `{:scrollable, children, opts}`:

      scrollable(children, opts)

  `children` are the elements to scroll. The renderer measures them, sets
  `:content_height` from their combined preferred height and `:viewport_height`
  and `:viewport_width` from the allocated rect, and re-measures on every pass —
  so those three are computed for you and are not worth passing. A trailing
  `{:footer, _}` child is split off and rendered outside the scrolled region.

  ## Options

    * `:content_height` - `t:non_neg_integer/0` total content height in rows.
      Default `0`; set from the children's measured height through the element.
      Live-updatable.
    * `:content_width` - `t:non_neg_integer/0` total content width in columns.
      Default `0`. Live-updatable; used only to clamp `:scroll_offset_x`.
    * `:viewport_height` - `t:pos_integer/0` visible height in rows. Default `10`;
      set from the allocated rect through the element. Live-updatable.
    * `:viewport_width` - `t:pos_integer/0` visible width in columns. Default `80`;
      set from the allocated rect less the scrollbar column through the element.
      Live-updatable.
    * `:show_vertical_scrollbar` - `:auto | :always | :never`. Default `:auto`.
      Only `:never` changes anything: the scrollbar is drawn whenever the content
      is taller than the viewport and suppressed otherwise, so `:always` behaves
      like `:auto`. Mount-only.
    * `:show_horizontal_scrollbar` - `:auto | :always | :never`. Default `:never`.
      Held on the state and never read; no horizontal scrollbar is drawn.
      Mount-only.
    * `:click_to_scroll` - `t:boolean/0`. Default `false`. Held on the state and
      only consulted together with the internal `:scroll_locked` flag, which
      nothing sets, so it has no effect on rendering. Clicking the track above or
      below the thumb always pages the viewport. Mount-only.
    * `:focusable` - `t:boolean/0`. Default `true`. Held on the state and never
      read; the container is always focusable through its `:focusable` trait.
      Mount-only.
    * `:child_widget_ids` - list of widget IDs whose scroll events bubble through
      this container. Default `[]`. Live-updatable.
    * `:id` - identifier for the container. Default `nil`; set by the renderer
      through the element. Mount-only.
    * `:focused` - `t:boolean/0` initial focus state. Default `false`. Mount-only.

  `update/2` additionally accepts `:scroll_offset_y` and `:scroll_offset_x` to
  drive the position directly; both are clamped to the content extent, as is any
  offset already on the state, on every call. `mount/1` always starts both at `0`
  and ignores any offset in the props.

  ## Key bindings

    * `up` / `down` — one row
    * `page_up` / `page_down` — one viewport height
    * `home` / `end` — top or bottom

  The mouse wheel moves three rows. Pressing the thumb starts a drag; pressing the
  track above or below it pages the viewport on release.

  ## Usage

      scrollable([label("row 1"), label("row 2")], show_vertical_scrollbar: :always)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :scroll]

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager

  defstruct [
    :id,
    :scroll_offset_y,
    :scroll_offset_x,
    :content_height,
    :content_width,
    :viewport_height,
    :viewport_width,
    :focused,
    :focusable,
    :show_vertical_scrollbar,
    :show_horizontal_scrollbar,
    :child_widget_ids,
    :dragging_scrollbar,
    :hovering_scrollbar,
    :drag_thumb_offset,
    :click_to_scroll,
    :scroll_locked
  ]

  @type t :: %__MODULE__{
          id: term(),
          scroll_offset_y: non_neg_integer(),
          scroll_offset_x: non_neg_integer(),
          content_height: non_neg_integer(),
          content_width: non_neg_integer(),
          viewport_height: pos_integer(),
          viewport_width: pos_integer(),
          focused: boolean(),
          focusable: boolean(),
          show_vertical_scrollbar: :auto | :always | :never,
          show_horizontal_scrollbar: :auto | :always | :never,
          child_widget_ids: [term()],
          dragging_scrollbar: boolean(),
          hovering_scrollbar: boolean(),
          drag_thumb_offset: non_neg_integer(),
          click_to_scroll: boolean(),
          scroll_locked: boolean()
        }

  @type viewport :: %{
          scroll_y: non_neg_integer(),
          scroll_x: non_neg_integer(),
          viewport_height: pos_integer(),
          viewport_width: pos_integer(),
          content_height: non_neg_integer(),
          content_width: non_neg_integer()
        }

  @doc """
  Builds the widget state from `props`.

  Both scroll offsets start at `0` whatever `props` says, and so do
  `:dragging_scrollbar`, `:hovering_scrollbar`, `:drag_thumb_offset` and the
  internal `:scroll_locked` flag.

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{})
      iex> {state.content_height, state.viewport_height, state.viewport_width}
      {0, 10, 80}

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{scroll_offset_y: 5})
      iex> {state.scroll_offset_y, state.show_vertical_scrollbar, state.show_horizontal_scrollbar}
      {0, :auto, :never}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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
      focusable: Map.get(props, :focusable, true),
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

  @doc """
  Folds the measurements and offsets in `props` into `state` and re-clamps both
  scroll offsets.

  Accepts `:content_height`, `:content_width`, `:viewport_height`,
  `:viewport_width`, `:child_widget_ids`, `:scroll_offset_y` and
  `:scroll_offset_x`, and drops every other key. `:scroll_offset_y` is clamped to
  `0..(content_height - viewport_height)` and `:scroll_offset_x` to
  `0..(content_width - viewport_width)`, so shrinking the content pulls an
  out-of-range offset back into view.

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{})
      iex> updated = Drafter.Widget.ScrollableContainer.update(%{content_height: 100, scroll_offset_y: 999}, state)
      iex> updated.scroll_offset_y
      90

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> updated = Drafter.Widget.ScrollableContainer.update(%{scroll_offset_y: 50}, state)
      iex> Drafter.Widget.ScrollableContainer.update(%{content_height: 20}, updated).scroll_offset_y
      10
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  Draws the one-column scrollbar into `rect`.

  Returns `[]` — no scrollbar at all — when the content fits the viewport or
  `:show_vertical_scrollbar` is `:never`. Otherwise returns
  `min(rect.height, viewport_height)` single-cell strips, with the thumb sized as
  `viewport_height * viewport_height / content_height`, at least one row. The
  content itself is drawn by the children, not here.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
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
    styles = scrollbar_styles(state, theme)
    viewport_height = min(rect.height, state.viewport_height)
    {thumb_start, thumb_height} = get_thumb_position(state)

    Enum.map(0..(viewport_height - 1)//1, fn row ->
      is_thumb = row >= thumb_start and row < thumb_start + thumb_height
      {char, style} = scrollbar_cell(is_thumb, state, styles)
      Strip.new([Segment.new(char, style)])
    end)
  end

  defp scrollbar_styles(state, theme) do
    track_style =
      if state.click_to_scroll and state.scroll_locked,
        do: %{fg: theme.primary, bg: theme.surface},
        else: %{fg: theme.text_muted, bg: theme.surface}

    %{
      track: track_style,
      thumb: %{fg: theme.primary, bg: theme.primary},
      thumb_hover: %{fg: {255, 255, 255}, bg: {0, 150, 255}},
      thumb_drag: %{fg: {255, 255, 255}, bg: {0, 120, 200}}
    }
  end

  defp scrollbar_cell(false, _state, styles), do: {CharacterSet.scroll(:track), styles.track}

  defp scrollbar_cell(true, %{dragging_scrollbar: true}, styles),
    do: {CharacterSet.scroll(:thumb_drag), styles.thumb_drag}

  defp scrollbar_cell(true, %{hovering_scrollbar: true}, styles),
    do: {CharacterSet.scroll(:thumb_hover), styles.thumb_hover}

  defp scrollbar_cell(true, _state, styles), do: {CharacterSet.scroll(:thumb), styles.thumb}

  @doc """
  Handles the container's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  Recognised events:

    * `{:key, :up}` / `{:key, :down}` - one row
    * `{:key, :page_up}` / `{:key, :page_down}` - one viewport height
    * `{:key, :home}` / `{:key, :end}` - top or bottom
    * `{:mouse, %{type: :scroll, direction: dir}}` - three rows
    * `{:mouse, %{type: :mouse_down, x: 0, y: y}}` - start a thumb drag when `y`
      is on the thumb, otherwise `{:noreply, state}`; a press anywhere else
      bubbles
    * `{:mouse, %{type: :drag, y: y}}` while dragging - move the viewport to match
      the pointer
    * `{:mouse, %{type: :mouse_up}}` while dragging - end the drag
    * `{:mouse, %{type: :mouse_up, x: 0, y: y}}` - page up or down when `y` is off
      the thumb, otherwise bubble

  Every other event returns `{:bubble, state}`. Anything that moves the viewport
  returns `{:ok, state, [:scroll_fast_render]}`, except the `home` and `end` keys,
  which return `{:ok, state}` and are not clamped against the content.

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> {:ok, scrolled, actions} = Drafter.Widget.ScrollableContainer.handle_event({:key, :page_down}, state)
      iex> {scrolled.scroll_offset_y, actions}
      {10, [:scroll_fast_render]}

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> {:ok, scrolled, _} = Drafter.Widget.ScrollableContainer.handle_event({:key, :up}, state)
      iex> scrolled.scroll_offset_y
      0

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> {:ok, bottom} = Drafter.Widget.ScrollableContainer.handle_event({:key, :end}, state)
      iex> bottom.scroll_offset_y
      90

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> Drafter.Widget.ScrollableContainer.handle_event({:key, :tab}, state) == {:bubble, state}
      true
  """
  @spec handle_event(term(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  def handle_event({:key, :up}, state), do: scroll_by(state, 0, -1)
  def handle_event({:key, :down}, state), do: scroll_by(state, 0, 1)
  def handle_event({:key, :page_up}, state), do: scroll_by(state, 0, -state.viewport_height)
  def handle_event({:key, :page_down}, state), do: scroll_by(state, 0, state.viewport_height)
  def handle_event({:key, :home}, state), do: {:ok, %{state | scroll_offset_y: 0}}

  def handle_event({:key, :end}, state) do
    max_scroll = max(0, state.content_height - state.viewport_height)
    {:ok, %{state | scroll_offset_y: max_scroll}}
  end

  def handle_event({:mouse, %{type: :scroll, direction: :up}}, state), do: scroll_by(state, 0, -3)

  def handle_event({:mouse, %{type: :scroll, direction: :down}}, state),
    do: scroll_by(state, 0, 3)

  def handle_event({:mouse, %{type: :mouse_down, x: 0, y: y}}, state) do
    {thumb_start, thumb_height} = get_thumb_position(state)

    if y >= thumb_start and y < thumb_start + thumb_height do
      {:ok, %{state | dragging_scrollbar: true, drag_thumb_offset: y - thumb_start}}
    else
      {:noreply, state}
    end
  end

  def handle_event({:mouse, %{type: :mouse_down}}, state), do: {:bubble, state}

  def handle_event({:mouse, %{type: :drag, y: y}}, %{dragging_scrollbar: true} = state) do
    {_thumb_start, thumb_height} = get_thumb_position(state)
    desired_thumb_start = y - state.drag_thumb_offset
    max_thumb_start = max(1, state.viewport_height - thumb_height)
    scroll_ratio = desired_thumb_start / max_thumb_start
    max_scroll = max(0, state.content_height - state.viewport_height)
    new_offset = round(scroll_ratio * max_scroll)
    new_state = %{state | scroll_offset_y: max(0, min(max_scroll, new_offset))}
    {:ok, new_state, [:scroll_fast_render]}
  end

  def handle_event({:mouse, %{type: :mouse_up}}, %{dragging_scrollbar: true} = state) do
    {:ok, %{state | dragging_scrollbar: false, drag_thumb_offset: 0}}
  end

  def handle_event({:mouse, %{type: :mouse_up, x: 0, y: y}}, state) do
    {thumb_start, thumb_height} = get_thumb_position(state)

    cond do
      y < thumb_start -> scroll_by(state, 0, -state.viewport_height)
      y >= thumb_start + thumb_height -> scroll_by(state, 0, state.viewport_height)
      true -> {:bubble, state}
    end
  end

  def handle_event(_, state), do: {:bubble, state}

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

  @doc """
  The scroll state the renderer needs to position the children.

  Returns `:scroll_y`, `:scroll_x`, `:viewport_height`, `:viewport_width`,
  `:content_height` and `:content_width`.

      iex> state = Drafter.Widget.ScrollableContainer.mount(%{content_height: 100})
      iex> Drafter.Widget.ScrollableContainer.get_viewport(state)
      %{scroll_y: 0, scroll_x: 0, viewport_height: 10, viewport_width: 80, content_height: 100, content_width: 0}
  """
  @spec get_viewport(t()) :: viewport()
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
