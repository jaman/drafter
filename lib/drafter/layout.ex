defmodule Drafter.Layout do
  @moduledoc """
  Pure layout calculation for the component tree.

  All functions are stateless. They take component descriptors and rects,
  return geometry (rects or size lists), and have no side effects.
  """

  alias Drafter.CharacterSet
  alias Drafter.Widget.Registry

  @type rect :: %{x: integer(), y: integer(), width: pos_integer(), height: pos_integer()}
  @type component :: tuple()
  @type hierarchy :: map()

  @spec rect(non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()) :: rect()
  def rect(x, y, width, height), do: %{x: x, y: y, width: width, height: height}

  @spec get_preferred_height(component(), hierarchy() | nil) :: pos_integer() | :auto
  def get_preferred_height(component, hierarchy \\ nil)

  def get_preferred_height({:layout, :horizontal, children, _opts}, _hierarchy) do
    children |> Enum.map(&get_preferred_height(&1, nil)) |> Enum.max(fn -> 1 end)
  end

  def get_preferred_height({:layout, :vertical, children, _opts}, _hierarchy) do
    children |> Enum.map(&get_preferred_height(&1, nil)) |> Enum.sum()
  end

  def get_preferred_height({:scrollable, children, opts}, _hierarchy) do
    Keyword.get(opts, :height, children |> Enum.map(&get_preferred_height(&1, nil)) |> Enum.sum())
  end

  def get_preferred_height({:box, children, opts}, hierarchy) do
    border = Keyword.get(opts, :border, CharacterSet.style(:border) || :rounded)
    padding = Keyword.get(opts, :padding, CharacterSet.style(:padding) || 1)
    border_height = if border == :none, do: 0, else: 2
    content_height = children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()
    Keyword.get(opts, :height, border_height + padding * 2 + content_height)
  end

  def get_preferred_height({:card, children, opts}, hierarchy) do
    padding = Keyword.get(opts, :padding, CharacterSet.style(:padding) || 1)
    content_height = children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()
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

  @spec get_child_vertical_spec(component(), hierarchy() | nil) ::
          {pos_integer() | :auto, non_neg_integer(), boolean()}
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
    {preferred, 0, false}
  end

  def get_child_vertical_spec(child, hierarchy) do
    preferred = get_preferred_height(child, hierarchy)
    if preferred == :auto, do: {1, 1, true}, else: {preferred, 0, false}
  end

  defp collapsible_height(nil, _title, _content, _opts), do: 1

  defp collapsible_height(hierarchy, title, content, opts) do
    case find_collapsible_state(hierarchy, title) do
      %{expanded: true} = state -> estimate_collapsible_height(state)
      nil -> collapsible_height_from_opts(content, opts)
      _ -> 1
    end
  end

  defp collapsible_height_from_opts(content, opts) do
    if Keyword.get(opts, :expanded, false) do
      estimate_collapsible_height(%{content: content, content_height: Keyword.get(opts, :content_height)})
    else
      1
    end
  end

  defp flex_spec(opts, preferred_fn) do
    flex = Keyword.get(opts, :flex, 0)
    has_flex = flex > 0 or Keyword.has_key?(opts, :flex)

    preferred =
      case Keyword.get(opts, :height) do
        nil -> if has_flex, do: 1, else: preferred_fn.()
        height -> height
      end

    {preferred, max(flex, 1), has_flex}
  end

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
        {preferred, flex, has_flex} = get_child_vertical_spec(child, hierarchy)
        %{preferred: preferred, flex: flex, has_flex: has_flex}
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
        if spec.has_flex do
          flex_share = spec.flex / total_flex
          max(1, round(available_for_flex * flex_share))
        else
          spec.preferred
        end
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

  @spec get_padding(keyword()) :: {integer(), integer(), integer(), integer()}
  def get_padding(opts) do
    case Keyword.get(opts, :padding) do
      nil -> {0, 0, 0, 0}
      {top, right, bottom, left} -> {top, right, bottom, left}
      {vertical, horizontal} -> {vertical, horizontal, vertical, horizontal}
      n when is_integer(n) -> {n, n, n, n}
      _ -> {0, 0, 0, 0}
    end
  end

  @spec apply_padding(rect(), {integer(), integer(), integer(), integer()}) :: rect()
  def apply_padding(rect, {top, right, bottom, left}) do
    %{
      x: rect.x + left,
      y: rect.y + top,
      width: max(1, rect.width - left - right),
      height: max(1, rect.height - top - bottom)
    }
  end

  @spec component_visible?(component()) :: boolean()
  def component_visible?(component) do
    case component do
      {_type, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      {_type, _children, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      {_type, _a, _b, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      _ -> true
    end
  end

  defp apply_width_spec({:fixed, w}, {acc, remaining_pixels}, _base_flex_width) do
    {acc ++ [w], remaining_pixels}
  end

  defp apply_width_spec({:flex, _}, {acc, remaining_pixels}, base_flex_width) do
    extra = if remaining_pixels > 0, do: 1, else: 0
    {acc ++ [base_flex_width + extra], remaining_pixels - extra}
  end

  defp accumulate_width_spec({_child_item, child_opts}, {fixed_sum, flex_count, acc_specs}) do
    width = Keyword.get(child_opts, :width)
    flex = Keyword.get(child_opts, :flex, 0)

    cond do
      width -> {fixed_sum + width, flex_count, acc_specs ++ [{:fixed, width}]}
      flex > 0 -> {fixed_sum, flex_count + 1, acc_specs ++ [{:flex, flex}]}
      true -> {fixed_sum, flex_count + 1, acc_specs ++ [{:flex, 1}]}
    end
  end

  defp calculate_horizontal_layout_with_opts(children, rect, children_opts) do
    child_specs = Enum.zip(children, children_opts)

    {fixed_total, flexible_count, width_specs} =
      Enum.reduce(child_specs, {0, 0, []}, &accumulate_width_spec/2)

    available_for_flex = max(0, rect.width - fixed_total)

    {base_flex_width, remainder} =
      if flexible_count > 0 do
        {div(available_for_flex, flexible_count), rem(available_for_flex, flexible_count)}
      else
        {0, 0}
      end

    {final_widths, _} =
      Enum.reduce(width_specs, {[], remainder}, fn spec, acc ->
        apply_width_spec(spec, acc, base_flex_width)
      end)

    {sizes, _} =
      Enum.reduce(final_widths, {[], rect.x}, fn width, {acc, current_x} ->
        size = %{x: current_x, width: max(1, width)}
        {acc ++ [size], current_x + width}
      end)

    sizes
  end

  defp accumulate_colspan({colspan, idx}, {acc, current_x, remaining_pixels}, gap, num_children, base_col_width) do
    extra = min(colspan, remaining_pixels)
    cell_width = base_col_width * colspan + extra
    internal_gaps = gap * (colspan - 1)
    w = cell_width + internal_gaps
    next_x = current_x + w + if idx < num_children - 1, do: gap, else: 0
    {[%{x: current_x, width: w} | acc], next_x, remaining_pixels - extra}
  end

  defp accumulate_equal({_child, idx}, {acc, current_x, remaining_pixels}, gap, num_children, base_width) do
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

  defp get_colspan(child) do
    opts =
      case child do
        {:layout, _, _, opts} -> opts
        {_, opts} when is_list(opts) -> opts
        {_, _, opts} when is_list(opts) -> opts
        {_, _, _, opts} when is_list(opts) -> opts
        _ -> []
      end

    Keyword.get(opts, :colspan, 1)
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

  defp estimate_collapsible_height(%{content: content, content_height: content_height}) when is_list(content) do
    1 + (content_height || 10)
  end

  defp estimate_collapsible_height(%{content: content}) when is_binary(content) do
    lines = Drafter.Text.wrap(content, 80, :word)
    1 + length(lines)
  end

  defp estimate_collapsible_height(_state), do: 2
end
