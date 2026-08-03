defmodule Drafter.Widget.Container do
  @moduledoc """
  Holds and arranges child widgets using vertical, horizontal, or stack layouts.

  In `:vertical` layout children share height equally; in `:horizontal` they share
  width equally. `:stack` overlays all children at the same position, rendering only
  the last child's output. Events are forwarded to every child on each dispatch.

  Children are widget modules, not element tuples. Each is mounted during
  `mount/1` and its state is retained across renders.

  ## Component tag

  This module has no `component_tag/0` and no `Drafter.App` helper. It is used by
  placing it in a render tree as a `{module, props}` pair:

      {Drafter.Widget.Container,
       %{
         layout: :vertical,
         children: [
           {Drafter.Widget.Label, %{text: "Top section"}},
           {Drafter.Widget.Label, %{text: "Bottom section"}}
         ]
       }}

  The `vertical/2` and `horizontal/2` helpers in `Drafter.App` do not build this
  widget — they produce `{:layout, direction, children, opts}` elements that the
  component renderer lays out itself.

  ## Options

    * `:children` - list of `{module, props}` or `{module, props, state}` tuples.
      Default `[]`. A two-element pair is mounted; a three-element one is taken as
      already mounted
    * `:layout` - arrangement: `:vertical` (default), `:horizontal`, `:stack`
    * `:padding` - inner padding in columns and rows. Default `0`
    * `:border_style` - `:none` (default) or any other atom. Any value other than
      `:none` insets the content rect by one cell on every side; no border
      characters are drawn
    * `:style` - `t:map/0` of style properties. Default `%{}`. Carried on the state
      and not consulted while rendering

  `update/2` re-reads every option. Supplying `:children` re-mounts each entry given
  as a `{module, props}` pair, discarding whatever state that child had accumulated;
  pass `{module, props, state}` triples to keep it.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`.

  ## Usage

      Drafter.Widget.Container.mount(%{
        layout: :horizontal,
        padding: 1,
        children: [
          {Drafter.Widget.Label, %{text: "Left"}},
          {Drafter.Widget.Label, %{text: "Right"}}
        ]
      })
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget

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

  @doc """
  Builds a container struct directly from `children` and `opts`.

  Unlike `mount/1` this stores `children` exactly as given, so a `{module, props}`
  pair is *not* mounted and `render/2` will fail on it. Use `mount/1` unless the
  children are already `{module, props, state}` triples.

  Options: `:layout` (default `:vertical`), `:padding` (default `0`),
  `:border_style` (default `:none`), `:style` (default `%{}`).

      iex> c = Drafter.Widget.Container.new([], layout: :horizontal, padding: 2)
      iex> {c.children, c.layout, c.padding, c.border_style, c.style}
      {[], :horizontal, 2, :none, %{}}
  """
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

  @doc """
  Builds the container state from `props`, mounting every `{module, props}` child
  and leaving `{module, props, state}` triples alone.

      iex> c = Drafter.Widget.Container.mount(%{children: [{Drafter.Widget.Label, %{text: "Hi"}}]})
      iex> [{module, _props, child_state}] = c.children
      iex> {module, child_state.text, c.layout}
      {Drafter.Widget.Label, "Hi", :vertical}

      iex> c = Drafter.Widget.Container.mount(%{})
      iex> {c.children, c.layout, c.padding, c.border_style, c.style}
      {[], :vertical, 0, :none, %{}}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Renders every child into its share of `rect` and stacks the results.

  The content rect is inset by `:padding`, plus one further cell on each side when
  `:border_style` is not `:none`. `:vertical` gives each child
  `div(height, child_count)` rows, `:horizontal` gives each
  `div(width, child_count)` columns, and `:stack` gives every child the full rect
  but returns only the last child's strips. Returns exactly `rect.height` strips,
  each padded to `rect.width`. A child returning `{:error, reason}` contributes no
  rows.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    content_rect = calculate_content_rect(rect, state.padding, state.border_style)

    child_rects = calculate_child_layouts(state.children, content_rect, state.layout)

    child_strips = render_children(state.children, child_rects)

    combined_strips = combine_child_strips(child_strips, content_rect, state.layout)

    final_strips = apply_container_styling(combined_strips, rect, state)

    final_strips
  end

  @doc """
  Offers the event to every child in order.

  Every child sees the event, even after an earlier one handled it. A child
  returning `{:ok, _}` or `{:ok, _, _}` marks the event handled; `{:bubble, _}` and
  `{:noreply, _}` keep the child's new state without marking it handled, and any
  other return leaves that child's state alone. Returns `{:ok, state}` if any child
  handled the event and `{:bubble, state}` otherwise; child states are updated
  either way. Actions returned by children are discarded.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_event(event, state) do
    {children, handled?} =
      Enum.map_reduce(state.children, false, fn {module, props, child_state}, taken ->
        offer_to_child(module, props, child_state, event, taken)
      end)

    updated = %{state | children: children}

    if handled?, do: {:ok, updated}, else: {:bubble, updated}
  end

  defp offer_to_child(module, props, child_state, event, taken) do
    case module.handle_event(event, child_state) do
      {:ok, new_child_state} -> {{module, props, new_child_state}, true}
      {:ok, new_child_state, _actions} -> {{module, props, new_child_state}, true}
      {:bubble, new_child_state} -> {{module, props, new_child_state}, taken}
      {:noreply, new_child_state} -> {{module, props, new_child_state}, taken}
      _other -> {{module, props, child_state}, taken}
    end
  end

  @doc """
  Folds fresh props into `state`.

  Re-reads `:layout`, `:padding`, `:border_style` and `:style`. When `:children` is
  present the whole child list is rebuilt, mounting each `{module, props}` pair
  afresh, so any state those children held is lost.

      iex> c = Drafter.Widget.Container.mount(%{layout: :vertical})
      iex> Drafter.Widget.Container.update(%{layout: :stack, padding: 1}, c).layout
      :stack
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  Calls `unmount/1` on every child that exports it and returns `:ok`.
  """
  @spec unmount(t()) :: :ok
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

    Enum.map(0..(max_height - 1)//1, fn line_index ->
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
    cond do
      line_index >= 0 and line_index < length(strips) -> Enum.at(strips, line_index).segments
      is_map(child_rect) -> [Segment.new(String.duplicate(" ", child_rect.width))]
      true -> []
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
