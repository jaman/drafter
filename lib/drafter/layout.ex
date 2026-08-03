defmodule Drafter.Layout do
  @moduledoc """
  Pure layout calculation for the component tree.

  All functions are stateless. They take component descriptors and rects,
  return geometry (rects or size lists), and have no side effects.
  """

  alias Drafter.CharacterSet
  alias Drafter.Widget.Registry

  @typedoc """
  A rectangle in terminal cells.

  `x`/`y` are the top-left corner and may be negative for a component scrolled out of
  view. `width`/`height` may be `0` — `apply_margin/2` produces zero-sized rects when
  the margin exceeds the space.
  """
  @type rect :: %{
          x: integer(),
          y: integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @typedoc "A component descriptor tuple, as an app's `render/1` returns."
  @type component :: tuple()

  @typedoc "A widget hierarchy map, consulted for widgets that report their own size."
  @type hierarchy :: map()

  @typedoc """
  A size as written in a component's options.

  A non-negative integer is a cell count, `{:percent, n}` a share of the container,
  `{:fr, n}` a share of what is left after fixed siblings, and `:auto` defers to the
  component's own preferred size.
  """
  @type dimension :: non_neg_integer() | {:percent, number()} | {:fr, number()} | :auto | nil

  @typedoc "Edge insets as `{top, right, bottom, left}`."
  @type sides :: {integer(), integer(), integer(), integer()}

  @doc """
  Build a rect map from its four components.

  No clamping or validation is applied.

  ## Examples

      iex> Drafter.Layout.rect(1, 2, 30, 4)
      %{x: 1, y: 2, width: 30, height: 4}

  """
  @spec rect(integer(), integer(), non_neg_integer(), non_neg_integer()) :: rect()
  def rect(x, y, width, height), do: %{x: x, y: y, width: width, height: height}

  @doc """
  How tall a component would like to be, in cells.

  Container components sum their children plus their own chrome; a registered widget
  is asked through `Drafter.Widget.Registry`. `hierarchy` supplies live widget state
  where a widget's height depends on it, and defaults to `nil`. Anything unrecognised
  is `1`.
  """
  @spec get_preferred_height(component(), hierarchy() | nil) :: pos_integer() | :auto
  def get_preferred_height(component, hierarchy \\ nil)

  def get_preferred_height({:layout, :horizontal, children, opts}, hierarchy) do
    children
    |> Enum.map(&get_preferred_height(&1, hierarchy))
    |> Enum.max(fn -> 1 end)
    |> cap_at_max_height(opts)
  end

  def get_preferred_height({:layout, :vertical, children, opts}, hierarchy) do
    children
    |> Enum.map(&get_preferred_height(&1, hierarchy))
    |> Enum.sum()
    |> cap_at_max_height(opts)
  end

  def get_preferred_height({:scrollable, children, opts}, hierarchy) do
    Keyword.get(
      opts,
      :height,
      children |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()
    )
  end

  def get_preferred_height({:box, children, opts}, hierarchy) do
    border = Keyword.get(opts, :border, CharacterSet.style(:border) || :rounded)
    padding = Keyword.get(opts, :padding, CharacterSet.style(:padding) || 1)
    border_height = if border == :none, do: 0, else: 2

    content_height =
      children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()

    Keyword.get(opts, :height, border_height + padding * 2 + content_height)
  end

  def get_preferred_height({:card, children, opts}, hierarchy) do
    padding = Keyword.get(opts, :padding, CharacterSet.style(:padding) || 1)

    content_height =
      children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()

    Keyword.get(opts, :height, padding * 2 + content_height)
  end

  def get_preferred_height({:collapsible, title, content, opts}, hierarchy) do
    collapsible_height(hierarchy, title, content, opts)
  end

  def get_preferred_height({:split_pane, _children, opts}, _hierarchy) do
    Keyword.get(opts, :height, 1)
  end

  def get_preferred_height({:theme_selector, _opts}, _hierarchy), do: 10

  def get_preferred_height({tag, opts}, _hierarchy) when is_atom(tag) and is_list(opts) do
    case Registry.lookup(tag) do
      nil -> 1
      module -> module.preferred_height(nil, opts)
    end
  end

  def get_preferred_height({tag, args, opts}, _hierarchy) when is_atom(tag) and is_list(opts) do
    case Registry.lookup(tag) do
      nil -> 1
      module -> module.preferred_height(args, opts)
    end
  end

  def get_preferred_height(_component, _hierarchy), do: 1

  @doc """
  A child's vertical sizing inputs, as `{preferred, weight, flexes?, max_height}`.

  `weight` is the child's `:fr` count when it has one, otherwise its `:flex` value,
  never less than `1`. `flexes?` says whether the child should absorb leftover space.
  `max_height` is its `:max_height` option, or `nil`.
  """
  @spec get_child_vertical_spec(component(), hierarchy() | nil) ::
          {pos_integer() | :auto, non_neg_integer(), boolean(), pos_integer() | nil}
  def get_child_vertical_spec({:layout, _direction, _children, opts} = child, hierarchy) do
    flex_spec(opts, fn -> get_preferred_height(child, hierarchy) end)
  end

  def get_child_vertical_spec({:scrollable, _children, opts} = child, hierarchy) do
    flex_spec(opts, fn -> get_preferred_height(child, hierarchy) end)
  end

  def get_child_vertical_spec({:split_pane, _children, opts}, _hierarchy) do
    flex_spec(opts, fn -> 1 end)
  end

  def get_child_vertical_spec({:box, children, opts}, hierarchy) do
    flex_spec(opts, fn -> get_preferred_height({:box, children, opts}, hierarchy) end)
  end

  def get_child_vertical_spec({:card, children, opts}, hierarchy) do
    flex_spec(opts, fn -> get_preferred_height({:card, children, opts}, hierarchy) end)
  end

  def get_child_vertical_spec({:collapsible, title, content, opts}, hierarchy) do
    preferred = collapsible_height(hierarchy, title, content, opts)
    {preferred, 0, false, nil}
  end

  def get_child_vertical_spec(child, hierarchy) do
    opts = component_opts(child)

    if Keyword.has_key?(opts, :flex) or match?({:fr, _}, Keyword.get(opts, :height)) do
      flex_spec(opts, fn -> get_preferred_height(child, hierarchy) end)
    else
      preferred = get_preferred_height(child, hierarchy)
      if preferred == :auto, do: {1, 1, true, nil}, else: {preferred, 0, false, nil}
    end
  end

  defp collapsible_height(nil, _title, content, opts) do
    collapsible_height_from_opts(content, opts)
  end

  defp collapsible_height(hierarchy, title, content, opts) do
    case find_collapsible_state(hierarchy, title) do
      %{expanded: true} = state -> estimate_collapsible_height(state)
      nil -> collapsible_height_from_opts(content, opts)
      _ -> 1
    end
  end

  defp collapsible_height_from_opts(content, opts) do
    if Keyword.get(opts, :expanded, false) do
      estimate_collapsible_height(%{
        content: content,
        content_height: Keyword.get(opts, :content_height)
      })
    else
      1
    end
  end

  defp flex_spec(opts, preferred_fn) do
    flex = Keyword.get(opts, :flex, 0)
    fr = fr_units(Keyword.get(opts, :height))
    has_flex = flex > 0 or Keyword.has_key?(opts, :flex) or fr != nil
    max_h = Keyword.get(opts, :max_height)

    preferred =
      case Keyword.get(opts, :height) do
        nil -> if has_flex, do: 1, else: preferred_fn.()
        {:fr, _} -> 1
        height -> height
      end

    weight = fr || max(flex, 1)
    {clamp_size(cap_at_max_height(preferred, opts), opts, :height), weight, has_flex, max_h}
  end

  defp fr_units({:fr, n}) when is_number(n) and n > 0, do: round(n)
  defp fr_units(_other), do: nil

  @doc """
  Stack children down `rect`, returning a `%{y: y, height: height}` per child.

  Fixed-height children keep their preferred height; the rest share what is left in
  proportion to their flex weight, with a floor of one cell each. Every result is
  clipped to the bottom of `rect`, so a child that does not fit gets height `0`.

  ## Options

    * `:gap` - blank rows between children. Default: `0`. Gaps are subtracted from
      the space the flexing children share.

  Each child's own `:height`, `:min_height`, `:max_height`, `:flex` and `:fr` options
  are read from the child descriptor, not from `opts`.
  """
  @spec calculate_vertical_layout(
          [component()],
          rect(),
          keyword(),
          hierarchy() | nil
        ) :: [%{y: integer(), height: pos_integer()}]
  def calculate_vertical_layout(children, rect, opts, hierarchy) do
    gap = Keyword.get(opts, :gap, 0)
    num_children = length(children)
    total_gap = if num_children > 1, do: gap * (num_children - 1), else: 0

    child_specs =
      Enum.map(children, fn child ->
        {preferred, flex, has_flex, max_h} = get_child_vertical_spec(child, hierarchy)
        child_opts = component_opts(child)

        preferred =
          child_opts
          |> Keyword.get(:height)
          |> resolve_dimension(rect.height, preferred)
          |> clamp_size(child_opts, :height)

        %{preferred: preferred, flex: flex, has_flex: has_flex, max_height: max_h}
      end)

    fixed_total =
      child_specs
      |> Enum.filter(fn spec -> not spec.has_flex end)
      |> Enum.map(fn spec -> spec.preferred end)
      |> Enum.sum()

    flex_children =
      child_specs
      |> Enum.with_index()
      |> Enum.filter(fn {spec, _idx} -> spec.has_flex end)

    total_flex =
      flex_children
      |> Enum.map(fn {spec, _idx} -> spec.flex end)
      |> Enum.sum()
      |> max(1)

    available_for_flex = max(0, rect.height - fixed_total - total_gap)

    actual_heights =
      Enum.map(child_specs, fn spec ->
        height =
          if spec.has_flex do
            flex_share = spec.flex / total_flex
            max(1, round(available_for_flex * flex_share))
          else
            spec.preferred
          end

        if spec.max_height, do: min(height, spec.max_height), else: height
      end)

    max_y = rect.y + rect.height

    {sizes, _} =
      Enum.reduce(Enum.with_index(actual_heights), {[], rect.y}, fn {height, idx},
                                                                    {acc, current_y} ->
        clamped_height = max(0, min(height, max_y - current_y))
        size = %{y: current_y, height: clamped_height}
        next_y = current_y + clamped_height + if idx < num_children - 1, do: gap, else: 0
        {[size | acc], next_y}
      end)

    Enum.reverse(sizes)
  end

  @doc """
  Lay children out across `rect`, returning a `%{x: x, width: width}` per child.

  ## Options

    * `:children_opts` - list of per-child option keywords, positionally matched to
      `children`. Default: `[]`. When no entry carries `:width` or `:flex`, the rect
      is divided evenly and `:gap` applies; otherwise those per-child options drive
      the widths and `:gap` is not used.
    * `:gap` - blank columns between children. Default: `0`. Honoured only on the
      even-division path described above.

  """
  @spec calculate_horizontal_layout([component()], rect(), keyword()) ::
          [%{x: integer(), width: pos_integer()}]
  def calculate_horizontal_layout(children, rect, opts) do
    children_opts = Keyword.get(opts, :children_opts, [])
    gap = Keyword.get(opts, :gap, 0)

    has_width_or_flex =
      Enum.any?(children_opts, fn child_opts ->
        Keyword.has_key?(child_opts, :width) or Keyword.has_key?(child_opts, :flex)
      end)

    if has_width_or_flex do
      calculate_horizontal_layout_with_opts(children, rect, children_opts)
    else
      calculate_horizontal_layout_no_opts(children, rect, gap)
    end
  end

  @doc """
  Place children on a two-dimensional grid.

  `:columns` fixes the column count; without it, columns are inferred from
  `:rows`, or fall back to a single row of all children. `:gap` separates cells
  in both directions, or `{row_gap, col_gap}` separates them independently.
  Children may span with `:col_span` and `:row_span`.

  The grid always fills its rect: columns left over from uneven division are
  handed out one cell at a time to the leftmost columns.
  """
  @spec calculate_grid_layout([component()], rect(), keyword()) :: [rect()]
  def calculate_grid_layout([], _rect, _opts), do: []

  def calculate_grid_layout(children, rect, opts) do
    {row_gap, col_gap} = grid_gaps(Keyword.get(opts, :gap, 0))
    columns = grid_columns(children, opts)
    rows = ceil(length(children) / columns)

    col_edges = track_edges(rect.x, rect.width, columns, col_gap)
    row_edges = track_edges(rect.y, rect.height, rows, row_gap)

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      cell_rect(child, index, columns, rows, col_edges, row_edges, col_gap, row_gap)
    end)
  end

  defp grid_gaps({row_gap, col_gap}), do: {row_gap, col_gap}
  defp grid_gaps(gap) when is_integer(gap), do: {gap, gap}
  defp grid_gaps(_gap), do: {0, 0}

  defp grid_columns(children, opts) do
    cond do
      is_integer(opts[:columns]) and opts[:columns] > 0 -> opts[:columns]
      is_integer(opts[:rows]) and opts[:rows] > 0 -> ceil(length(children) / opts[:rows])
      true -> length(children)
    end
  end

  defp track_edges(origin, total, count, gap) when count > 0 do
    available = max(0, total - gap * (count - 1))
    base = div(available, count)
    remainder = rem(available, count)

    {edges, _} =
      Enum.map_reduce(0..(count - 1)//1, origin, fn index, pos ->
        size = base + if index < remainder, do: 1, else: 0
        {{pos, size}, pos + size + gap}
      end)

    List.to_tuple(edges)
  end

  defp cell_rect(child, index, columns, rows, col_edges, row_edges, col_gap, row_gap) do
    opts = component_opts(child)
    col = rem(index, columns)
    row = div(index, columns)

    col_span = span(opts, :col_span, columns - col)
    row_span = span(opts, :row_span, rows - row)

    {x, width} = track_extent(col_edges, col, col_span, col_gap)
    {y, height} = track_extent(row_edges, row, row_span, row_gap)

    %{x: x, y: y, width: max(0, width), height: max(0, height)}
  end

  defp span(opts, key, available) do
    case Keyword.get(opts, key, 1) do
      n when is_integer(n) and n > 0 -> min(n, available)
      _ -> 1
    end
  end

  defp track_extent(edges, start, span, _gap) do
    {origin, _size} = elem(edges, start)
    last = min(start + span - 1, tuple_size(edges) - 1)
    {last_origin, last_size} = elem(edges, last)
    {origin, last_origin + last_size - origin}
  end

  @doc """
  How many widget slots a component descriptor occupies, counting nested children.

  A layout contributes nothing of its own; a box, card, scrollable or collapsible
  contributes one plus its children. Anything else is `1`.

  ## Examples

      iex> Drafter.Layout.count_component_slots({:label, [text: "hi"]})
      1

      iex> Drafter.Layout.count_component_slots({:layout, :vertical, [{:label, []}, {:label, []}], []})
      2

      iex> Drafter.Layout.count_component_slots({:box, [{:label, []}], []})
      2

  """
  @spec count_component_slots(component()) :: pos_integer()
  def count_component_slots({:layout, _dir, children, _opts}) do
    Enum.sum(Enum.map(children, &count_component_slots/1))
  end

  def count_component_slots({:scrollable, children, _opts}) do
    1 + Enum.sum(Enum.map(children, &count_component_slots/1))
  end

  def count_component_slots({:box, children, _opts}) do
    1 + Enum.sum(Enum.map(List.wrap(children), &count_component_slots/1))
  end

  def count_component_slots({:card, children, _opts}) do
    1 + Enum.sum(Enum.map(List.wrap(children), &count_component_slots/1))
  end

  def count_component_slots({:collapsible, _title, content, _opts}) when is_list(content) do
    1 + Enum.sum(Enum.map(content, &count_component_slots/1))
  end

  def count_component_slots(_), do: 1

  @doc """
  Resolve a dimension against the space available to it.

  Accepts a plain cell count, `{:percent, n}` for a share of the container,
  `{:fr, n}` for a share of what remains after fixed siblings, or `:auto` to
  defer to the component's own preferred size.

  Returns a cell count for integers and percentages. `nil`, `:auto`, `{:fr, n}`
  and any unrecognised value return `fallback`.

  ## Examples

      iex> Drafter.Layout.resolve_dimension(10, 100, :auto)
      10

      iex> Drafter.Layout.resolve_dimension({:percent, 25}, 80, :auto)
      20

      iex> Drafter.Layout.resolve_dimension(nil, 80, 7)
      7

      iex> Drafter.Layout.resolve_dimension({:fr, 2}, 80, 7)
      7

  """
  @spec resolve_dimension(term(), non_neg_integer(), non_neg_integer() | :auto) ::
          non_neg_integer() | :auto
  def resolve_dimension(nil, _available, fallback), do: fallback
  def resolve_dimension(:auto, _available, fallback), do: fallback
  def resolve_dimension(n, _available, _fallback) when is_integer(n) and n >= 0, do: n

  def resolve_dimension({:percent, pct}, available, _fallback) when is_number(pct) do
    max(0, round(available * pct / 100))
  end

  def resolve_dimension({:fr, _n}, _available, fallback), do: fallback
  def resolve_dimension(_other, _available, fallback), do: fallback

  @doc """
  Clamp a size to the `:min_height`/`:max_height` or `:min_width`/`:max_width` in `opts`.

  A bound that is absent or not an integer is ignored. When both are present and
  contradict each other, the maximum wins.

  ## Examples

      iex> Drafter.Layout.clamp_size(3, [min_height: 5], :height)
      5

      iex> Drafter.Layout.clamp_size(30, [max_width: 20], :width)
      20

      iex> Drafter.Layout.clamp_size(3, [], :height)
      3

  """
  @spec clamp_size(non_neg_integer(), keyword(), :height | :width) :: non_neg_integer()
  def clamp_size(size, opts, :height) do
    size
    |> apply_min(Keyword.get(opts, :min_height))
    |> apply_max(Keyword.get(opts, :max_height))
  end

  def clamp_size(size, opts, :width) do
    size
    |> apply_min(Keyword.get(opts, :min_width))
    |> apply_max(Keyword.get(opts, :max_width))
  end

  defp apply_min(size, nil), do: size
  defp apply_min(size, min) when is_integer(min), do: max(size, min)
  defp apply_min(size, _min), do: size

  defp apply_max(size, nil), do: size
  defp apply_max(size, max) when is_integer(max), do: min(size, max)
  defp apply_max(size, _max), do: size

  @doc """
  Margin around a component, as `{top, right, bottom, left}`.

  Shares the shorthand forms of `get_padding/1`: a single value applies to all
  sides, a pair is vertical then horizontal.

  Returns `{0, 0, 0, 0}` when `:margin` is absent or unrecognised.

  ## Examples

      iex> Drafter.Layout.get_margin(margin: 2)
      {2, 2, 2, 2}

      iex> Drafter.Layout.get_margin(margin: {1, 4})
      {1, 4, 1, 4}

      iex> Drafter.Layout.get_margin([])
      {0, 0, 0, 0}

  """
  @spec get_margin(keyword()) :: sides()
  def get_margin(opts), do: sides(Keyword.get(opts, :margin))

  @doc """
  Padding inside a component, as `{top, right, bottom, left}`.

  A single integer applies to all four sides, a `{vertical, horizontal}` pair to two
  each, and a full four-tuple is taken as written. Returns `{0, 0, 0, 0}` when
  `:padding` is absent or unrecognised.

  ## Examples

      iex> Drafter.Layout.get_padding(padding: 1)
      {1, 1, 1, 1}

      iex> Drafter.Layout.get_padding(padding: {0, 2, 3, 4})
      {0, 2, 3, 4}

      iex> Drafter.Layout.get_padding([])
      {0, 0, 0, 0}

  """
  @spec get_padding(keyword()) :: sides()
  def get_padding(opts), do: sides(Keyword.get(opts, :padding))

  defp sides(nil), do: {0, 0, 0, 0}
  defp sides({top, right, bottom, left}), do: {top, right, bottom, left}
  defp sides({vertical, horizontal}), do: {vertical, horizontal, vertical, horizontal}
  defp sides(n) when is_integer(n), do: {n, n, n, n}
  defp sides(_other), do: {0, 0, 0, 0}

  @doc """
  Shrink a rect by a component's margin, leaving the space outside its box.

  Width and height floor at `0`, so a margin larger than the rect collapses it.

  ## Examples

      iex> Drafter.Layout.apply_margin(%{x: 0, y: 0, width: 10, height: 6}, {1, 2, 1, 2})
      %{x: 2, y: 1, width: 6, height: 4}

      iex> Drafter.Layout.apply_margin(%{x: 0, y: 0, width: 2, height: 2}, {5, 5, 5, 5})
      %{x: 5, y: 5, width: 0, height: 0}

  """
  @spec apply_margin(rect(), sides()) :: rect()
  def apply_margin(rect, {top, right, bottom, left}) do
    %{
      x: rect.x + left,
      y: rect.y + top,
      width: max(0, rect.width - left - right),
      height: max(0, rect.height - top - bottom)
    }
  end

  @doc """
  Shrink a rect by a component's padding, leaving the space inside its border.

  Unlike `apply_margin/2`, width and height floor at `1`, so a padded component always
  keeps a cell to draw in.

  ## Examples

      iex> Drafter.Layout.apply_padding(%{x: 0, y: 0, width: 10, height: 6}, {1, 2, 1, 2})
      %{x: 2, y: 1, width: 6, height: 4}

      iex> Drafter.Layout.apply_padding(%{x: 0, y: 0, width: 2, height: 2}, {5, 5, 5, 5})
      %{x: 5, y: 5, width: 1, height: 1}

  """
  @spec apply_padding(rect(), sides()) :: rect()
  def apply_padding(rect, {top, right, bottom, left}) do
    %{
      x: rect.x + left,
      y: rect.y + top,
      width: max(1, rect.width - left - right),
      height: max(1, rect.height - top - bottom)
    }
  end

  @doc """
  Which edge a component is pinned to, if any.

  A docked component is taken out of the normal flow and given the full span of
  its edge; the remaining space is what the undocked siblings share. Reads the
  `:dock` option of any component, and treats `:footer` as docked to `:bottom`.
  Returns `nil` when the component is not docked.
  """
  @spec dock_edge(component()) :: :top | :bottom | :left | :right | nil
  def dock_edge(component) do
    case component do
      {:footer, _opts} -> :bottom
      other -> other |> component_opts() |> Keyword.get(:dock) |> normalize_edge()
    end
  end

  defp normalize_edge(edge) when edge in [:top, :bottom, :left, :right], do: edge
  defp normalize_edge(_other), do: nil

  @doc """
  Split components into those docked to an edge and those in normal flow.
  """
  @spec partition_docked([component()]) :: {[{component(), atom()}], [component()]}
  def partition_docked(children) do
    {docked, flowing} = Enum.split_with(children, &(dock_edge(&1) != nil))
    {Enum.map(docked, &{&1, dock_edge(&1)}), flowing}
  end

  @doc """
  Whether a component paints.

  Distinct from `component_visible?/1`: a hidden component keeps the space it was
  allotted and simply does not draw, whereas an invisible one is removed from the
  layout entirely and its siblings close the gap.
  """
  @spec component_hidden?(component()) :: boolean()
  def component_hidden?(component) do
    component |> component_opts() |> Keyword.get(:visibility) == :hidden
  end

  @spec component_visible?(component()) :: boolean()
  def component_visible?(component) do
    component |> component_opts() |> Keyword.get(:visible, true)
  end

  defp apply_width_spec({:fixed, w}, {acc, remaining_pixels}, _base_flex_width) do
    {[w | acc], remaining_pixels}
  end

  defp apply_width_spec({:flex, _}, {acc, remaining_pixels}, base_flex_width) do
    extra = if remaining_pixels > 0, do: 1, else: 0
    {[base_flex_width + extra | acc], remaining_pixels - extra}
  end

  defp accumulate_width_spec(
         {_child_item, child_opts, available},
         {fixed_sum, flex_count, acc_specs}
       ) do
    flex = Keyword.get(child_opts, :flex, 0)

    case resolve_dimension(Keyword.get(child_opts, :width), available, nil) do
      nil when flex > 0 ->
        {fixed_sum, flex_count + 1, [{:flex, flex} | acc_specs]}

      nil ->
        {fixed_sum, flex_count + 1, [{:flex, 1} | acc_specs]}

      width ->
        width = clamp_size(width, child_opts, :width)
        {fixed_sum + width, flex_count, [{:fixed, width} | acc_specs]}
    end
  end

  defp calculate_horizontal_layout_with_opts(children, rect, children_opts) do
    child_specs =
      Enum.zip(children, children_opts) |> Enum.map(fn {c, o} -> {c, o, rect.width} end)

    {fixed_total, flexible_count, reversed_specs} =
      Enum.reduce(child_specs, {0, 0, []}, &accumulate_width_spec/2)

    width_specs = Enum.reverse(reversed_specs)

    available_for_flex = max(0, rect.width - fixed_total)

    {base_flex_width, remainder} =
      if flexible_count > 0 do
        {div(available_for_flex, flexible_count), rem(available_for_flex, flexible_count)}
      else
        {0, 0}
      end

    {reversed_widths, _} =
      Enum.reduce(width_specs, {[], remainder}, fn spec, acc ->
        apply_width_spec(spec, acc, base_flex_width)
      end)

    {reversed_sizes, _} =
      reversed_widths
      |> Enum.reverse()
      |> Enum.reduce({[], rect.x}, fn width, {acc, current_x} ->
        {[%{x: current_x, width: max(1, width)} | acc], current_x + width}
      end)

    Enum.reverse(reversed_sizes)
  end

  defp accumulate_colspan(
         {colspan, idx},
         {acc, current_x, remaining_pixels},
         gap,
         num_children,
         base_col_width
       ) do
    extra = min(colspan, remaining_pixels)
    cell_width = base_col_width * colspan + extra
    internal_gaps = gap * (colspan - 1)
    w = cell_width + internal_gaps
    next_x = current_x + w + if idx < num_children - 1, do: gap, else: 0
    {[%{x: current_x, width: w} | acc], next_x, remaining_pixels - extra}
  end

  defp accumulate_equal(
         {_child, idx},
         {acc, current_x, remaining_pixels},
         gap,
         num_children,
         base_width
       ) do
    extra = if remaining_pixels > 0, do: 1, else: 0
    w = base_width + extra
    next_x = current_x + w + if idx < num_children - 1, do: gap, else: 0
    {[%{x: current_x, width: w} | acc], next_x, remaining_pixels - extra}
  end

  defp calculate_horizontal_layout_no_opts(children, rect, gap) do
    child_colspans = Enum.map(children, &get_colspan/1)
    has_colspan = Enum.any?(child_colspans, &(&1 > 1))
    num_children = length(children)

    if has_colspan do
      total_cols = Enum.sum(child_colspans)
      total_gap_space = gap * (total_cols - 1)
      available_width = rect.width - total_gap_space
      base_col_width = div(available_width, total_cols)
      remainder = rem(available_width, total_cols)

      {sizes, _, _} =
        Enum.reduce(Enum.with_index(child_colspans), {[], rect.x, remainder}, fn item, acc ->
          accumulate_colspan(item, acc, gap, num_children, base_col_width)
        end)

      Enum.reverse(sizes)
    else
      total_gap = if num_children > 1, do: gap * (num_children - 1), else: 0
      available_width = rect.width - total_gap
      base_width = div(available_width, num_children)
      remainder = rem(available_width, num_children)

      {sizes, _, _} =
        Enum.reduce(Enum.with_index(children), {[], rect.x, remainder}, fn item, acc ->
          accumulate_equal(item, acc, gap, num_children, base_width)
        end)

      Enum.reverse(sizes)
    end
  end

  defp get_colspan(child), do: child |> component_opts() |> Keyword.get(:colspan, 1)

  @doc "The options keyword list of a component, whatever its arity."
  @spec component_opts(component()) :: keyword()
  def component_opts({:layout, _dir, _children, opts}) when is_list(opts), do: opts
  def component_opts({_type, opts}) when is_list(opts), do: opts
  def component_opts({_type, _a, opts}) when is_list(opts), do: opts
  def component_opts({_type, _a, _b, opts}) when is_list(opts), do: opts
  def component_opts(_component), do: []

  defp cap_at_max_height(preferred, opts) do
    case Keyword.get(opts, :max_height) do
      nil -> preferred
      max_h when is_integer(max_h) -> min(preferred, max_h)
      _ -> preferred
    end
  end

  defp find_collapsible_state(hierarchy, title) do
    hierarchy.widgets
    |> Enum.find_value(fn {_id, widget_info} ->
      case widget_info do
        %{module: Drafter.Widget.Collapsible, state: %{title: ^title} = state} -> state
        _ -> nil
      end
    end)
  end

  defp estimate_collapsible_height(%{content: content, content_height: content_height})
       when is_list(content) do
    1 + (content_height || 10)
  end

  defp estimate_collapsible_height(%{content: content}) when is_binary(content) do
    lines = Drafter.Text.wrap(content, 80, :word)
    1 + length(lines)
  end

  defp estimate_collapsible_height(_state), do: 2
end
