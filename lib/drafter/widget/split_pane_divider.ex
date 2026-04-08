defmodule Drafter.Widget.SplitPaneDivider do
  @moduledoc """
  Renders a resizable divider between two panes in a split layout.

  The divider position starts as a ratio (0.0–1.0) for the initial draw and after
  screen resize. Once the user drags the divider, it switches to an absolute pixel
  position so that resizing an outer split pane does not affect this divider.

  ## State fields (read via `WidgetHierarchy.get_widget_state/2`)

    * `:ratio` - float 0.0–1.0; used for initial layout and screen resize fallback
    * `:fixed_pos` - integer column/row offset from start of parent rect; set after first drag
    * `:orientation` - `:horizontal` (side-by-side) or `:vertical` (top-bottom)

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

  @spec mount(map()) :: %__MODULE__{}
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

  @spec update(map(), %__MODULE__{}) :: %__MODULE__{}
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

  @spec render(%__MODULE__{}, map()) :: [Strip.t()]
  def render(state, rect) do
    theme = ThemeManager.get_current_theme()
    color = if state.focused, do: theme.primary, else: theme.text_muted

    case state.orientation do
      :horizontal -> render_vertical_divider(state, rect, color)
      :vertical -> render_horizontal_divider(state, rect, color)
    end
  end

  @spec handle_key(term(), %__MODULE__{}) :: {:ok, %__MODULE__{}} | {:bubble, %__MODULE__{}}
  def handle_key({:alt, :left}, %{orientation: :horizontal} = state) do
    {:ok, nudge(state, -@nudge_px)}
  end

  def handle_key({:alt, :right}, %{orientation: :horizontal} = state) do
    {:ok, nudge(state, @nudge_px)}
  end

  def handle_key({:alt, :up}, %{orientation: :vertical} = state) do
    {:ok, nudge(state, -@nudge_px)}
  end

  def handle_key({:alt, :down}, %{orientation: :vertical} = state) do
    {:ok, nudge(state, @nudge_px)}
  end

  def handle_key(_key, state), do: {:bubble, state}

  @spec handle_press(integer(), integer(), %__MODULE__{}) :: {:ok, %__MODULE__{}}
  def handle_press(_x, _y, state) do
    {:ok, %{state | dragging: true, drag_start_pos: effective_pos(state)}}
  end

  @spec handle_drag(integer(), integer(), %__MODULE__{}) :: {:ok, %__MODULE__{}, list()}
  def handle_drag(x, y, %{resize_mode: :live} = state) do
    delta = if state.orientation == :horizontal, do: x, else: y
    new_pos = clamp_pos(effective_pos(state) + delta, state.total_size)
    {:ok, %{state | fixed_pos: new_pos}, [{:widget_layout_needed, :all}]}
  end

  def handle_drag(x, y, state) do
    delta = if state.orientation == :horizontal, do: x, else: y
    new_pos = clamp_pos(effective_pos(state) + delta, state.total_size)
    {:ok, %{state | fixed_pos: new_pos}, [:divider_move]}
  end

  @spec handle_mouse_up(integer(), integer(), %__MODULE__{}) :: {:ok, %__MODULE__{}, list()}
  def handle_mouse_up(_x, _y, %{resize_mode: :live} = state) do
    {:ok, %{state | dragging: false}}
  end

  def handle_mouse_up(_x, _y, state) do
    {:ok, %{state | dragging: false}, [{:widget_layout_needed, :all}]}
  end

  @spec effective_pos(%__MODULE__{}) :: integer()
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

    Enum.map(0..(rect.height - 1), fn row ->
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
        String.slice(line, 0, mid) <> CharacterSet.box(:cross) <> String.slice(line, mid + 1, rect.width)
      else
        line
      end

    [Strip.new([Segment.new(line, %{fg: color})])]
  end
end
