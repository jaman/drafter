defmodule Drafter.Widget.Grid do
  @moduledoc """
  Arranges child widgets in a uniform column grid, wrapping into multiple rows.

  Children are laid out left-to-right, top-to-bottom. The number of columns is
  set via `:grid_size`. Column width is `floor(total_width / columns)` and row
  height is divided evenly across the number of rows required. Each child widget
  is mounted fresh on every render pass from its `{module, props}` tuple.

  ## Component tag

  This module has no `component_tag/0` and no `Drafter.App` helper. It is used by
  placing it in a render tree as a `{module, props}` pair, or by the renderer's
  `{:grid, children, opts}` element.

  ## Options

    * `:children` - list of `{module, props}` tuples. Default `[]`. Each child is
      re-mounted from its props on every render pass, so a child holding its own
      state will lose it between frames
    * `:grid_size` - number of columns. Default `2`
    * `:grid_rows` - `t:pos_integer/0` or `:auto`. Default `:auto`. Carried on the
      state but not consulted: the row count is always
      `ceil(child_count / grid_size)`
    * `:padding` - Default `1`. Carried on the state but not consulted while
      rendering
    * `:style` - `t:map/0` of style properties. Default `%{}`. Carried on the state
      but not consulted while rendering

  `update/2` merges the props map into the state, so every option is live.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`.

  ## Usage

      grid(children: [
        {Drafter.Widget.Label, %{text: "A"}},
        {Drafter.Widget.Label, %{text: "B"}},
        {Drafter.Widget.Label, %{text: "C"}},
        {Drafter.Widget.Label, %{text: "D"}}
      ], grid_size: 2)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}

  @type child_spec :: {module(), Drafter.Widget.props()}

  @type t :: %{
          children: [child_spec()],
          grid_size: pos_integer(),
          grid_rows: pos_integer() | :auto,
          style: map(),
          padding: non_neg_integer()
        }

  @doc """
  Builds the grid state from `props`. The state is a plain map, not a struct.

      iex> Drafter.Widget.Grid.mount(%{})
      %{children: [], grid_size: 2, grid_rows: :auto, style: %{}, padding: 1}

      iex> g = Drafter.Widget.Grid.mount(%{grid_size: 3, children: [{Drafter.Widget.Label, %{}}]})
      iex> {g.grid_size, length(g.children)}
      {3, 1}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    %{
      children: Map.get(props, :children, []),
      grid_size: Map.get(props, :grid_size, 2),
      grid_rows: Map.get(props, :grid_rows, :auto),
      style: Map.get(props, :style, %{}),
      padding: Map.get(props, :padding, 1)
    }
  end

  @doc """
  Renders every child into its cell and returns one strip per row of `rect.height`.

  Returns `[]` when there are no children. Each cell is `div(rect.width, grid_size)`
  columns wide and `div(rect.height, rows_needed)` rows tall, where `rows_needed` is
  `ceil(child_count / grid_size)`; `rect.height` smaller than `rows_needed` gives a
  cell height of `0` and raises `ArithmeticError`. A child strip's segments are
  taken only up to the first one wider than the cell, so an over-wide segment ends
  the row early rather than being cropped.

      iex> Drafter.Widget.Grid.render(Drafter.Widget.Grid.mount(%{}), %{x: 0, y: 0, width: 10, height: 2})
      []
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    if Enum.empty?(state.children) do
      []
    else
      render_grid(state, rect)
    end
  end

  @doc """
  Merges `props` into `state`, so every option is live-updatable.

      iex> g = Drafter.Widget.Grid.mount(%{})
      iex> Drafter.Widget.Grid.update(%{grid_size: 4}, g).grid_size
      4
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The grid is not focusable and
  does not forward events to its children.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_grid(state, rect) do
    cols = state.grid_size
    children_count = length(state.children)

    if children_count == 0 do
      []
    else
      col_width = div(rect.width, cols)
      rows_needed = div(children_count + cols - 1, cols)
      row_height = if rows_needed > 0, do: div(rect.height, rows_needed), else: rect.height

      grid_ctx = %{
        children: state.children,
        children_count: children_count,
        cols: cols,
        col_width: col_width,
        row_height: row_height
      }

      Enum.map(0..(rect.height - 1)//1, fn y ->
        row = div(y, row_height)
        cell_y = rem(y, row_height)
        segments = Enum.flat_map(0..(cols - 1)//1, &render_grid_cell(grid_ctx, row, &1, cell_y))
        Strip.new(segments)
      end)
    end
  end

  defp render_grid_cell(ctx, row, col, cell_y) do
    child_index = row * ctx.cols + col

    if child_index < ctx.children_count do
      {module, props} = Enum.at(ctx.children, child_index)
      child_rect = %{x: 0, y: 0, width: ctx.col_width, height: ctx.row_height}
      child_strips = render_child({module, props}, child_rect)
      extract_cell_segments(child_strips, cell_y, ctx.col_width)
    else
      [Segment.new(String.duplicate(" ", ctx.col_width))]
    end
  end

  defp extract_cell_segments(child_strips, cell_y, col_width) do
    if cell_y < length(child_strips) do
      Enum.at(child_strips, cell_y).segments
      |> Enum.take_while(fn segment -> String.length(segment.text) <= col_width end)
    else
      [Segment.new(String.duplicate(" ", col_width))]
    end
  end

  defp render_child({module, props}, rect) do
    state = module.mount(props)

    case module.render(state, rect) do
      strips when is_list(strips) -> strips
      {:error, _} -> []
    end
  end
end
