defmodule Drafter.Widget.SplitPaneDivider do
  @moduledoc """
  Renders a resizable divider between two panes in a split layout.

  The divider position starts as a ratio (0.0–1.0) for the initial draw and after
  screen resize. Once the user drags the divider, it switches to an absolute pixel
  position so that resizing an outer split pane does not affect this divider.

  Once `:fixed_pos` is set it takes precedence over `:ratio`; a parent that wants
  to reposition the divider from the outside must clear it.

  ## Component tag

  This module has no `component_tag/0` and no `Drafter.App` helper of its own.
  The renderer creates one divider per gap in a `{:split_pane, children, opts}`
  element, built by `Drafter.App.split_pane/2`.

  ## Options

    * `:id` - identifier for the divider. Default `nil`; set by the renderer.
      Mount-only.
    * `:ratio` - `t:float/0` in `0.0..1.0` giving the initial split point. Default
      `0.5`. Mount-only — `update/2` never changes it.
    * `:orientation` - `:horizontal` (side-by-side panes) or `:vertical` (stacked
      panes). Default `:horizontal`. Live-updatable. Any other value raises a
      `CaseClauseError` from `render/2`.
    * `:total_size` - `t:pos_integer/0` size in cells of the axis being split.
      Default `100`. Live-updatable; changing it re-clamps a `:fixed_pos` that has
      already been set.
    * `:show_handle` - `t:boolean/0`, draw the grip marker in the middle of the
      divider. Default `true`. Live-updatable. The marker is only drawn while the
      divider is focused.
    * `:resize_mode` - `:quick | :live`. Default `:quick`, which emits
      `{:divider_move, :quick}` on each drag step and `{:widget_layout_needed,
      :all}` on mouse up. `:live` emits `{:widget_layout_needed, :all}` on every
      drag step and nothing on mouse up. Mount-only.

  ## Key bindings

  Arrow keys move the divider by one cell, and only with `alt` or `shift` held:
  left/right for a `:horizontal` divider, up/down for a `:vertical` one. Every
  other key bubbles.

  ## Position clamping

  Both dragging and nudging clamp the position to
  `max(1, round(total_size * 0.1))..min(total_size - 2, round(total_size * 0.9))`,
  so with the default `:total_size` of `100` the divider stays within columns
  10 through 90.

  ## State fields (read via `WidgetHierarchy.get_widget_state/2`)

    * `:ratio` - float 0.0–1.0; used for initial layout and screen resize fallback
    * `:fixed_pos` - integer column/row offset from start of parent rect; `nil`
      until the first drag or nudge, after which it overrides `:ratio`
    * `:orientation` - `:horizontal` (side-by-side) or `:vertical` (top-bottom)
    * `:dragging` - `true` between a press and the matching mouse up
    * `:drag_start_pos` - the position at the moment of the press; `nil` otherwise
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :press, :mouse_up, :drag],
    layout_impact: :all

  alias Drafter.{CharacterSet, ThemeManager}
  alias Drafter.Draw.{Segment, Strip}

  @nudge_px 1

  defstruct [
    :id,
    :ratio,
    :fixed_pos,
    :orientation,
    :focused,
    :dragging,
    :total_size,
    :show_handle,
    :drag_start_pos,
    resize_mode: :quick
  ]

  @type t :: %__MODULE__{
          id: term(),
          ratio: float(),
          fixed_pos: integer() | nil,
          orientation: :horizontal | :vertical,
          focused: boolean(),
          dragging: boolean(),
          total_size: pos_integer(),
          show_handle: boolean(),
          drag_start_pos: integer() | nil,
          resize_mode: :quick | :live
        }

  @doc """
  Builds the widget state from `props`.

  Reads `:id` (default `nil`), `:ratio` (default `0.5`), `:orientation` (default
  `:horizontal`), `:total_size` (default `100`), `:show_handle` (default `true`)
  and `:resize_mode` (default `:quick`). `:fixed_pos` always starts as `nil` and
  `:focused` and `:dragging` as `false`, whatever `props` says.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> {state.ratio, state.orientation, state.total_size, state.resize_mode}
      {0.5, :horizontal, 100, :quick}

      iex> Drafter.Widget.SplitPaneDivider.mount(%{fixed_pos: 40}).fixed_pos
      nil
  """
  @spec mount(map()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      id: Map.get(props, :id),
      ratio: Map.get(props, :ratio, 0.5),
      fixed_pos: nil,
      orientation: Map.get(props, :orientation, :horizontal),
      focused: false,
      dragging: false,
      total_size: Map.get(props, :total_size, 100),
      show_handle: Map.get(props, :show_handle, true),
      resize_mode: Map.get(props, :resize_mode, :quick)
    }
  end

  @doc """
  Folds `:orientation`, `:total_size` and `:show_handle` into `state`.

  `:id`, `:ratio` and `:resize_mode` are ignored, so they are mount-only. A
  `:fixed_pos` that has already been set is re-clamped when `:total_size` changes
  and otherwise kept, so a parent that wants to reposition the divider from the
  outside has to clear `:fixed_pos` itself.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> Drafter.Widget.SplitPaneDivider.update(%{ratio: 0.9, show_handle: false}, state)
      ...> |> then(&{&1.ratio, &1.show_handle})
      {0.5, false}

      iex> state = %{Drafter.Widget.SplitPaneDivider.mount(%{}) | fixed_pos: 90}
      iex> Drafter.Widget.SplitPaneDivider.update(%{total_size: 50}, state).fixed_pos
      45
  """
  @spec update(map(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    new_total = Map.get(props, :total_size, state.total_size)

    fixed_pos =
      cond do
        is_nil(state.fixed_pos) ->
          nil

        new_total != state.total_size ->
          clamp_pos(state.fixed_pos, new_total)

        true ->
          state.fixed_pos
      end

    %{
      state
      | orientation: Map.get(props, :orientation, state.orientation),
        total_size: new_total,
        fixed_pos: fixed_pos,
        show_handle: Map.get(props, :show_handle, state.show_handle)
    }
  end

  @doc """
  Draws the divider into `rect`, using the current theme's `:primary` colour while
  focused and `:text_muted` otherwise.

  A `:horizontal` divider is a one-column vertical line of `rect.height` strips; a
  `:vertical` divider is one strip `rect.width` wide. The grip marker replaces the
  middle character only while the divider is focused and `:show_handle` is set.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    theme = ThemeManager.get_current_theme()
    color = if state.focused, do: theme.primary, else: theme.text_muted

    case state.orientation do
      :horizontal -> render_vertical_divider(state, rect, color)
      :vertical -> render_horizontal_divider(state, rect, color)
    end
  end

  @doc """
  Nudges the divider one cell when `alt` or `shift` is held and the arrow key
  matches the orientation.

  Returns `{:ok, state}` with `:fixed_pos` moved and clamped, or `{:bubble, state}`
  when no modifier is held or the key does not match the axis.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> {:ok, moved} = Drafter.Widget.SplitPaneDivider.handle_key(:left, [:alt], state)
      iex> moved.fixed_pos
      49

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> Drafter.Widget.SplitPaneDivider.handle_key(:left, [], state) == {:bubble, state}
      true

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> Drafter.Widget.SplitPaneDivider.handle_key(:up, [:alt], state) == {:bubble, state}
      true
  """
  @impl Drafter.Widget
  @spec handle_key(term(), Drafter.Widget.modifiers(), t()) ::
          {:ok, t()} | {:bubble, t()}
  def handle_key(direction, mods, state) when is_list(mods) do
    if resize_modifier?(mods) do
      nudge_toward(direction, state)
    else
      {:bubble, state}
    end
  end

  @doc """
  Bubbles every unmodified key press. Resizing needs `alt` or `shift`; see
  `handle_key/3`.
  """
  @impl Drafter.Widget
  @spec handle_key(term(), t()) :: {:bubble, t()}
  def handle_key(_key, state), do: {:bubble, state}

  defp resize_modifier?(mods), do: Enum.any?(mods, &(&1 in [:alt, :shift]))

  defp nudge_toward(:left, %{orientation: :horizontal} = state),
    do: {:ok, nudge(state, -@nudge_px)}

  defp nudge_toward(:right, %{orientation: :horizontal} = state),
    do: {:ok, nudge(state, @nudge_px)}

  defp nudge_toward(:up, %{orientation: :vertical} = state), do: {:ok, nudge(state, -@nudge_px)}
  defp nudge_toward(:down, %{orientation: :vertical} = state), do: {:ok, nudge(state, @nudge_px)}
  defp nudge_toward(_direction, state), do: {:bubble, state}

  @doc """
  Starts a drag: sets `:dragging` and records `:drag_start_pos` as the current
  effective position. The press coordinates are ignored.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> {:ok, pressed} = Drafter.Widget.SplitPaneDivider.handle_press(0, 0, state)
      iex> {pressed.dragging, pressed.drag_start_pos}
      {true, 50}
  """
  @spec handle_press(integer(), integer(), t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_press(_x, _y, state) do
    {:ok, %{state | dragging: true, drag_start_pos: effective_pos(state)}}
  end

  @doc """
  Moves the divider by the drag delta and clamps it.

  `x` is used for a `:horizontal` divider and `y` for a `:vertical` one; the other
  coordinate is ignored. Both are deltas, not absolute positions. Returns
  `{:ok, state, [{:widget_layout_needed, :all}]}` in `:live` resize mode and
  `{:ok, state, [{:divider_move, :quick}]}` otherwise.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> {:ok, dragged, actions} = Drafter.Widget.SplitPaneDivider.handle_drag(5, 0, state)
      iex> {dragged.fixed_pos, actions}
      {55, [{:divider_move, :quick}]}

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{resize_mode: :live})
      iex> {:ok, _dragged, actions} = Drafter.Widget.SplitPaneDivider.handle_drag(5, 0, state)
      iex> actions
      [{:widget_layout_needed, :all}]
  """
  @spec handle_drag(integer(), integer(), t()) :: {:ok, t(), list()}
  @impl Drafter.Widget
  def handle_drag(x, y, %{resize_mode: :live} = state) do
    delta = if state.orientation == :horizontal, do: x, else: y
    new_pos = clamp_pos(effective_pos(state) + delta, state.total_size)
    {:ok, %{state | fixed_pos: new_pos}, [{:widget_layout_needed, :all}]}
  end

  def handle_drag(x, y, state) do
    delta = if state.orientation == :horizontal, do: x, else: y
    new_pos = clamp_pos(effective_pos(state) + delta, state.total_size)
    {:ok, %{state | fixed_pos: new_pos}, [{:divider_move, state.resize_mode}]}
  end

  @doc """
  Ends a drag by clearing `:dragging`. The coordinates are ignored.

  In `:live` resize mode returns `{:ok, state}` and keeps `:drag_start_pos`,
  because the layout was already refreshed on every drag step. In `:quick` mode it
  also clears `:drag_start_pos` and returns
  `{:ok, state, [{:widget_layout_needed, :all}]}`.

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{})
      iex> {:ok, released, actions} = Drafter.Widget.SplitPaneDivider.handle_mouse_up(0, 0, state)
      iex> {released.dragging, actions}
      {false, [{:widget_layout_needed, :all}]}

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{resize_mode: :live})
      iex> {:ok, released} = Drafter.Widget.SplitPaneDivider.handle_mouse_up(0, 0, state)
      iex> released.dragging
      false
  """
  @spec handle_mouse_up(integer(), integer(), t()) :: {:ok, t()} | {:ok, t(), list()}
  @impl Drafter.Widget
  def handle_mouse_up(_x, _y, %{resize_mode: :live} = state) do
    {:ok, %{state | dragging: false}}
  end

  def handle_mouse_up(_x, _y, state) do
    {:ok, %{state | dragging: false, drag_start_pos: nil}, [{:widget_layout_needed, :all}]}
  end

  @doc """
  The divider's current offset in cells from the start of the parent rect.

  Returns `:fixed_pos` when it is an integer, and `round(ratio * (total_size - 1))`
  otherwise. Not clamped — an out-of-range `:fixed_pos` is returned as it stands.

      iex> Drafter.Widget.SplitPaneDivider.effective_pos(Drafter.Widget.SplitPaneDivider.mount(%{}))
      50

      iex> state = Drafter.Widget.SplitPaneDivider.mount(%{ratio: 0.25, total_size: 41})
      iex> Drafter.Widget.SplitPaneDivider.effective_pos(state)
      10

      iex> state = %{Drafter.Widget.SplitPaneDivider.mount(%{}) | fixed_pos: 7}
      iex> Drafter.Widget.SplitPaneDivider.effective_pos(state)
      7
  """
  @spec effective_pos(t()) :: integer()
  def effective_pos(%{fixed_pos: fp}) when is_integer(fp), do: fp
  def effective_pos(%{ratio: r, total_size: t}), do: round(r * (t - 1))

  defp nudge(state, delta) do
    new_pos = clamp_pos(effective_pos(state) + delta, state.total_size)
    %{state | fixed_pos: new_pos}
  end

  defp clamp_pos(pos, total) do
    min_pos = max(1, round(total * 0.1))
    max_pos = min(total - 2, round(total * 0.9))
    pos |> max(min_pos) |> min(max_pos)
  end

  defp render_vertical_divider(state, rect, color) do
    char = CharacterSet.box(:v_line)
    mid_row = div(rect.height, 2)

    Enum.map(0..(rect.height - 1)//1, fn row ->
      display_char =
        if state.show_handle && state.focused && row == mid_row do
          CharacterSet.box(:cross)
        else
          char
        end

      Strip.new([Segment.new(display_char, %{fg: color})])
    end)
  end

  defp render_horizontal_divider(state, rect, color) do
    char = CharacterSet.box(:h_line)
    line = String.duplicate(char, rect.width)

    line =
      if state.show_handle && state.focused && rect.width > 1 do
        mid = div(rect.width, 2)

        String.slice(line, 0, mid) <>
          CharacterSet.box(:cross) <> String.slice(line, mid + 1, rect.width)
      else
        line
      end

    [Strip.new([Segment.new(line, %{fg: color})])]
  end
end
