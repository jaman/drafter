defmodule Drafter.Widget.Grid do
  @moduledoc """
  Arranges child widgets in a uniform column grid, wrapping into multiple rows.

  Children are laid out left-to-right, top-to-bottom. The number of columns is
  set via `:grid_size`. Column width is `floor(total_width / columns)` and row
  height is divided evenly across the number of rows required. Each child widget
  is mounted fresh on every render pass from its `{module, props}` tuple.

  ## Options

    * `:children` - list of `{module, props}` tuples (default `[]`)
    * `:grid_size` - number of columns (default `2`)
    * `:grid_rows` - number of rows or `:auto` (default `:auto`)
    * `:padding` - inner cell padding in columns (default `1`)
    * `:style` - map of style properties

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

  def mount(props) do
    %{
      children: Map.get(props, :children, []),
      grid_size: Map.get(props, :grid_size, 2),
      grid_rows: Map.get(props, :grid_rows, :auto),
      style: Map.get(props, :style, %{}),
      padding: Map.get(props, :padding, 1)
    }
  end

  def render(state, rect) do
    if Enum.empty?(state.children) do
      []
    else
      render_grid(state, rect)
    end
  end

  def update(props, state) do
    Map.merge(state, props)
  end

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
