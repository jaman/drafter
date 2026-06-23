defmodule Drafter.Widget.PieChart do
  @moduledoc """
  Renders a circular pie chart using Unicode block and braille characters.

  Each slice is proportional to its value relative to the total. The chart uses
  quarter-block and half-block Unicode characters for sub-cell resolution rendering,
  and braille characters where finer detail is needed.

  ## Options

    * `:data` - list of `{label, value}` or `{label, value, color}` tuples
    * `:show_legend` - display a legend with labels and percentages (default `true`)
    * `:show_percentages` - show percentage values in the legend (default `true`)
    * `:colors` - list of `{r, g, b}` tuples for the color palette
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      pie_chart([{"Elixir", 45}, {"Rust", 30}, {"Go", 25}])
      pie_chart([{"A", 60, {255, 100, 100}}, {"B", 40, {100, 100, 255}}])
      pie_chart([{"X", 10}, {"Y", 20}], show_legend: false)
  """

  use Drafter.Widget

  import Bitwise, only: [bor: 2]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Chart.Pixel

  @default_palette [
    {100, 180, 255},
    {255, 130, 80},
    {100, 220, 140},
    {220, 100, 220},
    {255, 220, 80},
    {120, 220, 220},
    {255, 100, 100},
    {180, 140, 255}
  ]

  @braille_base 0x2800
  @braille_dots %{
    {0, 0} => 0x01,
    {0, 1} => 0x02,
    {0, 2} => 0x04,
    {0, 3} => 0x40,
    {1, 0} => 0x08,
    {1, 1} => 0x10,
    {1, 2} => 0x20,
    {1, 3} => 0x80
  }

  defstruct [
    :data,
    :show_legend,
    :show_percentages,
    :colors,
    :style,
    :classes,
    :app_module,
    renderer: :text
  ]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      data: Map.get(props, :data, []),
      show_legend: Map.get(props, :show_legend, true),
      show_percentages: Map.get(props, :show_percentages, true),
      colors: Map.get(props, :colors, @default_palette),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      renderer: Map.get(props, :renderer, :text)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    computed =
      Computed.for_widget(:pie_chart, state,
        classes: state.classes,
        style: state.style,
        app_module: state.app_module
      )

    bg = computed[:background] || {20, 20, 30}

    slices = build_slices(state)

    legend_width = if state.show_legend, do: compute_legend_width(slices, state), else: 0
    chart_width = max(1, rect.width - legend_width)
    chart_height = rect.height

    chart_strips = render_chart(slices, chart_width, chart_height, bg)

    if state.show_legend and legend_width > 0 do
      legend_strips = render_legend(slices, state, legend_width, chart_height, bg)
      merge_strips(chart_strips, legend_strips, chart_height, bg)
    else
      pad_strips(chart_strips, chart_height)
    end
  end

  @doc false
  def image(state, rect, id) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if pie_pixel?(state) do
      slices = build_slices(state)
      legend_width = if state.show_legend, do: compute_legend_width(slices, state), else: 0
      chart_width = max(1, rect.width - legend_width)
      chart_height = rect.height
      spec = %{type: :pie, slices: pie_slices(slices)}

      case Pixel.image(spec, Pixel.protocol(state.renderer), {chart_width, chart_height}, id) do
        nil -> nil
        {paint, clear} -> {paint, clear, %{dx: 0, dy: 0, cols: chart_width, rows: chart_height}}
      end
    else
      nil
    end
  end

  defp pie_pixel?(state) do
    state.renderer != :text and Pixel.protocol(state.renderer) != nil
  end

  defp pie_slices(slices) do
    Enum.map(slices, fn %{value: value, color: color} -> {value, to_rgba(color)} end)
  end

  defp to_rgba({r, g, b}), do: {r, g, b, 255}
  defp to_rgba({r, g, b, a}), do: {r, g, b, a}
  defp to_rgba(_color), do: {150, 150, 150, 255}

  @impl Drafter.Widget
  def handle_event(_event, state), do: {:bubble, state}

  @impl Drafter.Widget
  def update(props, state) do
    %{state |
      data: Map.get(props, :data, state.data),
      show_legend: Map.get(props, :show_legend, state.show_legend),
      show_percentages: Map.get(props, :show_percentages, state.show_percentages),
      colors: Map.get(props, :colors, state.colors),
      style: Map.get(props, :style, state.style),
      classes: Map.get(props, :classes, state.classes),
      app_module: Map.get(props, :app_module, state.app_module),
      renderer: Map.get(props, :renderer, state.renderer)
    }
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, data, _rect) when is_list(data) and data != [] do
    normalized =
      Enum.map(data, fn
        {label, value} -> {label, value}
        {label, value, color} -> {label, value, color}
        other -> {"", other}
      end)

    %{state | data: normalized}
  end

  def apply_data_buffer(state, _data, _rect), do: state

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 10)

  def component_tag, do: :pie_chart

  def from_component_opts(data, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    all_data =
      if is_list(data) and data != [] and not Keyword.keyword?(data) do
        data
      else
        Keyword.get(opts, :data, [])
      end

    %{
      data: all_data,
      show_legend: Keyword.get(opts, :show_legend, true),
      show_percentages: Keyword.get(opts, :show_percentages, true),
      colors: Keyword.get(opts, :colors, @default_palette),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__),
      renderer: Keyword.get(opts, :renderer, :text)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp build_slices(state) do
    total = Enum.reduce(state.data, 0, fn entry, acc -> acc + elem(entry, 1) end)

    state.data
    |> Enum.with_index()
    |> Enum.map(fn {entry, idx} ->
      {label, value, color} = extract_entry(entry, idx, state.colors)
      percentage = if total > 0, do: value / total, else: 0.0
      %{label: label, value: value, percentage: percentage, color: color}
    end)
  end

  defp extract_entry({label, value, color}, _idx, _palette), do: {label, value, color}

  defp extract_entry({label, value}, idx, palette) do
    color = Enum.at(palette, rem(idx, length(palette)))
    {label, value, color}
  end

  defp compute_legend_width(slices, state) do
    max_label =
      slices
      |> Enum.map(fn slice ->
        base = String.length("  #{slice.label}")
        pct = if state.show_percentages, do: String.length(" (#{format_pct(slice.percentage)})"), else: 0
        base + pct
      end)
      |> Enum.max(fn -> 0 end)

    min(max_label + 4, 30)
  end

  defp render_chart(slices, width, height, bg) do
    dots_w = width * 2
    dots_h = height * 4

    cx = (dots_w - 1) / 2.0
    cy = (dots_h - 1) / 2.0
    radius = min(dots_w, dots_h) / 2.0 * 0.9

    angles = build_angles(slices)
    braille_map = build_braille_map(cx, cy, radius, dots_w, dots_h, angles)

    for row <- 0..(height - 1) do
      segments =
        Enum.map(0..(width - 1), fn col ->
          render_braille_cell(braille_map, col, row, bg)
        end)

      Strip.new(segments)
    end
  end

  defp build_angles(slices) do
    {angles, _} =
      Enum.map_reduce(slices, -90.0, fn slice, start_angle ->
        sweep = slice.percentage * 360.0
        end_angle = start_angle + sweep
        entry = %{start: start_angle, finish: end_angle, color: slice.color}
        {entry, end_angle}
      end)

    angles
  end

  defp build_braille_map(cx, cy, radius, dots_w, dots_h, angles) do
    max_bx = dots_w - 1
    max_by = dots_h - 1

    for bx <- 0..max_bx,
        by <- 0..max_by,
        dx = bx - cx,
        dy = by - cy,
        dist2 = dx * dx + dy * dy,
        dist2 <= radius * radius,
        reduce: %{} do
      acc ->
        angle_deg = normalize_angle(:math.atan2(dy, dx) * 180.0 / :math.pi())
        color = find_slice_color(angle_deg, angles)
        key = {div(bx, 2), div(by, 4)}
        bit = Map.get(@braille_dots, {rem(bx, 2), rem(by, 4)}, 0)
        Map.update(acc, key, [{bit, color}], &[{bit, color} | &1])
    end
  end

  defp normalize_angle(deg) when deg < -90.0, do: deg + 360.0
  defp normalize_angle(deg), do: deg

  defp find_slice_color(angle, angles) do
    Enum.find_value(angles, {128, 128, 128}, fn entry ->
      norm_start = entry.start
      norm_finish = entry.finish

      if angle_in_range?(angle, norm_start, norm_finish) do
        entry.color
      end
    end)
  end

  defp angle_in_range?(angle, start_angle, end_angle) when end_angle > start_angle do
    angle >= start_angle and angle < end_angle
  end

  defp angle_in_range?(angle, start_angle, end_angle) do
    angle >= start_angle or angle < end_angle
  end

  defp render_braille_cell(braille_map, col, row, bg) do
    case Map.get(braille_map, {col, row}) do
      nil ->
        Segment.new(" ", %{bg: bg})

      dots ->
        {bits, color} = merge_dots(dots)
        char = if bits == 0, do: " ", else: <<@braille_base + bits::utf8>>
        Segment.new(char, %{fg: color, bg: bg})
    end
  end

  defp merge_dots(dots) do
    bits = Enum.reduce(dots, 0, fn {b, _}, acc -> bor(acc, b) end)

    color_groups =
      dots
      |> Enum.group_by(fn {_, c} -> c end)
      |> Enum.max_by(fn {_, entries} -> length(entries) end)

    {bits, elem(color_groups, 0)}
  end

  defp render_legend(slices, state, legend_width, chart_height, bg) do
    legend_start_row = max(0, div(chart_height - length(slices), 2))

    for row <- 0..(chart_height - 1) do
      slice_idx = row - legend_start_row

      if slice_idx >= 0 and slice_idx < length(slices) do
        slice = Enum.at(slices, slice_idx)
        render_legend_entry(slice, state, legend_width, bg)
      else
        Strip.new([Segment.new(String.duplicate(" ", legend_width), %{bg: bg})])
      end
    end
  end

  defp render_legend_entry(slice, state, legend_width, bg) do
    swatch = Segment.new(" ■", %{fg: slice.color, bg: bg})

    label_text =
      if state.show_percentages do
        " #{slice.label} (#{format_pct(slice.percentage)})"
      else
        " #{slice.label}"
      end

    available = legend_width - 2
    truncated = String.slice(label_text, 0, available)
    padded = String.pad_trailing(truncated, available)

    label_seg = Segment.new(padded, %{fg: {200, 200, 200}, bg: bg})
    Strip.new([swatch, label_seg])
  end

  defp format_pct(fraction) do
    pct = Float.round(fraction * 100, 1)

    if pct == Float.round(pct, 0) do
      "#{trunc(pct)}%"
    else
      "#{pct}%"
    end
  end

  defp merge_strips(chart_strips, legend_strips, height, bg) do
    chart_padded = pad_strips(chart_strips, height)
    legend_padded = pad_strip_list(legend_strips, height, bg)

    Enum.zip(chart_padded, legend_padded)
    |> Enum.map(fn {chart_strip, legend_strip} ->
      Strip.combine(chart_strip, legend_strip)
    end)
  end

  defp pad_strips(strips, target_height) do
    current = length(strips)

    if current < target_height do
      padding = for _ <- 1..(target_height - current), do: Strip.new([Segment.new("", %{})])
      strips ++ padding
    else
      Enum.take(strips, target_height)
    end
  end

  defp pad_strip_list(strips, target_height, bg) do
    current = length(strips)

    if current < target_height do
      padding = for _ <- 1..(target_height - current), do: Strip.new([Segment.new(" ", %{bg: bg})])
      strips ++ padding
    else
      Enum.take(strips, target_height)
    end
  end
end
