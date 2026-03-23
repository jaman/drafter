defmodule Drafter.Widget.Container do
  @moduledoc """
  Holds and arranges child widgets using vertical, horizontal, or stack layouts.

  In `:vertical` layout children share height equally; in `:horizontal` they share
  width equally. `:stack` overlays all children at the same position, rendering only
  the last child's output. Events are forwarded to every child on each dispatch.
  The DSL exposes this widget as `vertical/2` and `horizontal/2`.

  ## Options

    * `:children` - list of `{module, props}` or `{module, props, state}` tuples
    * `:layout` - arrangement: `:vertical` (default), `:horizontal`, `:stack`
    * `:padding` - inner padding in columns/rows (default `0`)
    * `:border_style` - border drawn around the content: `:none` (default) or any atom
    * `:style` - map of style properties

  ## Usage

      vertical([
        label("Top section"),
        label("Bottom section")
      ])

      horizontal([
        label("Left"),
        label("Right")
      ], padding: 1)
  """

  use Drafter.Widget

  alias Drafter.Widget
  alias Drafter.Draw.Strip

  defstruct children: [],
            layout: :vertical,
            padding: 0,
            border_style: :none,
            style: %{}

  @type child_spec :: {module(), Widget.props()} | {module(), Widget.props(), Widget.state()}
  @type layout_type :: :vertical | :horizontal | :stack

  @type t :: %__MODULE__{
          children: [child_spec()],
          layout: layout_type(),
          padding: non_neg_integer(),
          border_style: atom(),
          style: map()
        }

  @doc "Create a new container"
  @spec new([child_spec()], keyword()) :: t()
  def new(children, opts \\ []) do
    %__MODULE__{
      children: children,
      layout: Keyword.get(opts, :layout, :vertical),
      padding: Keyword.get(opts, :padding, 0),
      border_style: Keyword.get(opts, :border_style, :none),
      style: Keyword.get(opts, :style, %{})
    }
  end

  @impl Drafter.Widget
  def mount(props) do
    children = Map.get(props, :children, [])

    mounted_children =
      Enum.map(children, fn
        {module, child_props} ->
          child_state = module.mount(child_props)
          {module, child_props, child_state}

        {module, child_props, child_state} ->
          {module, child_props, child_state}
      end)

    %__MODULE__{
      children: mounted_children,
      layout: Map.get(props, :layout, :vertical),
      padding: Map.get(props, :padding, 0),
      border_style: Map.get(props, :border_style, :none),
      style: Map.get(props, :style, %{})
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    content_rect = calculate_content_rect(rect, state.padding, state.border_style)

    child_rects = calculate_child_layouts(state.children, content_rect, state.layout)

    child_strips = render_children(state.children, child_rects)

    combined_strips = combine_child_strips(child_strips, content_rect, state.layout)

    final_strips = apply_container_styling(combined_strips, rect, state)

    final_strips
  end

  @impl Drafter.Widget
  def handle_event(event, state) do
    updated_children =
      Enum.map(state.children, fn {module, props, child_state} ->
        case module.handle_event(event, child_state) do
          {:ok, new_child_state} ->
            {module, props, new_child_state}

          {:error, _reason} ->
            {module, props, child_state}

          {:noreply, new_child_state} ->
            {module, props, new_child_state}
        end
      end)

    {:ok, %{state | children: updated_children}}
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_state = %{
      state
      | layout: Map.get(props, :layout, state.layout),
        padding: Map.get(props, :padding, state.padding),
        border_style: Map.get(props, :border_style, state.border_style),
        style: Map.get(props, :style, state.style)
    }

    case Map.get(props, :children) do
      nil ->
        new_state

      new_children ->
        updated_children =
          Enum.map(new_children, fn
            {module, child_props} ->
              child_state = module.mount(child_props)
              {module, child_props, child_state}

            {module, child_props, child_state} ->
              {module, child_props, child_state}
          end)

        %{new_state | children: updated_children}
    end
  end

  @impl Drafter.Widget
  def unmount(state) do
    Enum.each(state.children, fn {module, _props, child_state} ->
      if function_exported?(module, :unmount, 1) do
        module.unmount(child_state)
      end
    end)

    :ok
  end

  defp calculate_content_rect(rect, padding, border_style) do
    border_size = if border_style == :none, do: 0, else: 1
    total_offset = padding + border_size

    %{
      x: rect.x + total_offset,
      y: rect.y + total_offset,
      width: max(0, rect.width - total_offset * 2),
      height: max(0, rect.height - total_offset * 2)
    }
  end

  defp calculate_child_layouts(children, content_rect, layout) do
    case layout do
      :vertical ->
        calculate_vertical_layout(children, content_rect)

      :horizontal ->
        calculate_horizontal_layout(children, content_rect)

      :stack ->
        calculate_stack_layout(children, content_rect)
    end
  end

  defp calculate_vertical_layout(children, content_rect) do
    child_count = length(children)

    if child_count == 0 do
      []
    else
      child_height = div(content_rect.height, child_count)

      Enum.with_index(children, fn _child, index ->
        %{
          x: content_rect.x,
          y: content_rect.y + index * child_height,
          width: content_rect.width,
          height: child_height
        }
      end)
    end
  end

  defp calculate_horizontal_layout(children, content_rect) do
    child_count = length(children)

    if child_count == 0 do
      []
    else
      child_width = div(content_rect.width, child_count)

      Enum.with_index(children, fn _child, index ->
        %{
          x: content_rect.x + index * child_width,
          y: content_rect.y,
          width: child_width,
          height: content_rect.height
        }
      end)
    end
  end

  defp calculate_stack_layout(children, content_rect) do
    List.duplicate(content_rect, length(children))
  end

  defp render_children(children, child_rects) do
    children
    |> Enum.zip(child_rects)
    |> Enum.map(fn {{module, _props, child_state}, child_rect} ->
      case module.render(child_state, child_rect) do
        strips when is_list(strips) -> {child_rect, strips}
        {:error, _reason} -> {child_rect, []}
      end
    end)
  end

  defp combine_child_strips(child_strips, content_rect, :vertical) do
    all_strips = Enum.flat_map(child_strips, fn {_rect, strips} -> strips end)

    target_height = content_rect.height
    current_height = length(all_strips)

    if current_height < target_height do
      empty_strip = Strip.from_text(String.duplicate(" ", content_rect.width))
      padding_strips = List.duplicate(empty_strip, target_height - current_height)
      all_strips ++ padding_strips
    else
      Enum.take(all_strips, target_height)
    end
  end

  defp combine_child_strips(child_strips, _content_rect, :horizontal) do
    max_height =
      Enum.reduce(child_strips, 0, fn {_rect, strips}, acc ->
        max(acc, length(strips))
      end)

    Enum.map(0..(max_height - 1), fn line_index ->
      line_segments = Enum.flat_map(child_strips, &horizontal_line_segments(&1, line_index))
      Strip.new(line_segments)
    end)
  end

  defp combine_child_strips(child_strips, _content_rect, :stack) do
    case List.last(child_strips) do
      {_rect, strips} -> strips
      nil -> []
    end
  end

  defp horizontal_line_segments({child_rect, strips}, line_index) do
    if line_index < length(strips) do
      Enum.at(strips, line_index).segments
    else
      [Drafter.Draw.Segment.new(String.duplicate(" ", child_rect.width))]
    end
  end

  defp apply_container_styling(strips, rect, _state) do
    target_height = rect.height
    current_height = length(strips)

    padded_strips =
      if current_height < target_height do
        empty_strip = Strip.from_text(String.duplicate(" ", rect.width))
        padding_strips = List.duplicate(empty_strip, target_height - current_height)
        strips ++ padding_strips
      else
        Enum.take(strips, target_height)
      end

    Enum.map(padded_strips, fn strip ->
      Strip.pad(strip, rect.width)
    end)
  end
end
