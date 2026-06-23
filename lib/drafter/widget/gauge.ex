defmodule Drafter.Widget.Gauge do
  @moduledoc """
  A semi-circular gauge chart rendered using Unicode braille characters.

  The arc spans 260° (from ~8 o'clock to ~4 o'clock through the top). The
  filled portion is coloured green below the low threshold, orange between
  thresholds, and red above the high threshold. The unfilled track is rendered
  in dim grey. The numeric percentage is displayed centred below the arc.

  ## Options

    * `:value` - float in `0.0..1.0` (default `0.0`)
    * `:label` - optional title string displayed at the top
    * `:low_threshold` - fraction where colour changes to orange (default `0.8`)
    * `:high_threshold` - fraction where colour changes to red (default `0.9`)
    * `:low_color` - `{r, g, b}` for the low range (default green)
    * `:mid_color` - `{r, g, b}` for the mid range (default orange)
    * `:high_color` - `{r, g, b}` for the high range (default red)
    * `:track_color` - `{r, g, b}` for the unfilled arc (default dim grey)

  ## Usage

      gauge(value: 0.72)
      gauge(value: cpu_usage, label: "CPU", low_threshold: 0.6, high_threshold: 0.8)
  """

  use Drafter.Widget

  import Bitwise, only: [bor: 2]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Pixel

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

  @arc_start -130.0
  @arc_sweep 260.0

  defstruct [
    :value,
    :label,
    :low_threshold,
    :high_threshold,
    :low_color,
    :mid_color,
    :high_color,
    :track_color,
    renderer: :text
  ]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      value: Map.get(props, :value, 0.0),
      label: Map.get(props, :label),
      low_threshold: Map.get(props, :low_threshold, 0.8),
      high_threshold: Map.get(props, :high_threshold, 0.9),
      low_color: Map.get(props, :low_color, {80, 200, 80}),
      mid_color: Map.get(props, :mid_color, {220, 140, 0}),
      high_color: Map.get(props, :high_color, {220, 60, 60}),
      track_color: Map.get(props, :track_color, {55, 55, 55}),
      renderer: Map.get(props, :renderer, :text)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    if gauge_pixel?(state), do: render_pixel_base(state, rect), else: render_text(state, rect)
  end

  @doc false
  def image(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if gauge_pixel?(state) do
      label_rows = if state.label, do: 1, else: 0
      arc_rows = max(1, rect.height - label_rows - 1)
      gauge_image(state, rect.width, arc_rows, label_rows)
    else
      nil
    end
  end

  defp gauge_pixel?(state) do
    state.renderer != :text and Pixel.protocol(state.renderer) != nil
  end

  defp render_pixel_base(state, rect) do
    label_strips = if state.label, do: [center_strip(state.label, rect.width, {160, 160, 160})], else: []
    arc_rows = max(0, rect.height - length(label_strips) - 1)
    blank = Strip.new([Segment.new(String.duplicate(" ", rect.width))])
    value_strip = center_strip(format_value(state.value), rect.width, fill_rgb(state))
    label_strips ++ List.duplicate(blank, arc_rows) ++ [value_strip]
  end

  defp fill_rgb(state) do
    {r, g, b, _a} = gauge_fill(state)
    {r, g, b}
  end

  defp gauge_image(state, cols, rows, label_rows) do
    spec = %{type: :gauge, value: state.value, fill: gauge_fill(state), track: to_rgba(state.track_color)}

    case Pixel.image(spec, Pixel.protocol(state.renderer), {cols, rows}) do
      nil -> nil
      bytes -> {bytes, %{dx: 0, dy: label_rows, cols: cols, rows: rows}}
    end
  end

  defp gauge_fill(state) do
    cond do
      state.value >= state.high_threshold -> to_rgba(state.high_color)
      state.value >= state.low_threshold -> to_rgba(state.mid_color)
      true -> to_rgba(state.low_color)
    end
  end

  defp to_rgba({r, g, b}), do: {r, g, b, 255}
  defp to_rgba({r, g, b, a}), do: {r, g, b, a}
  defp to_rgba(_color), do: {180, 180, 180, 255}

  defp render_text(state, rect) do
    w = rect.width
    h = rect.height
    dots_w = w * 2
    label_rows = if state.label, do: 1, else: 0
    arc_char_rows = h - label_rows
    arc_dots_h = arc_char_rows * 4

    cx = (dots_w - 1) / 2.0
    cy = arc_dots_h * 0.50
    radius = min(dots_w / 2.0, arc_dots_h * 0.58) * 0.84
    thickness = max(2.0, radius * 0.22)

    braille_map = build_arc_map(state, cx, cy, radius, thickness)

    value_row = round((cy + radius * 0.25) / 4)

    label_strips =
      if state.label do
        [center_strip(state.label, w, {160, 160, 160})]
      else
        []
      end

    arc_strips =
      for row <- 0..(arc_char_rows - 1) do
        if row == value_row do
          value_overlay_strip(braille_map, row, w, state)
        else
          row_strip(braille_map, row, w)
        end
      end

    label_strips ++ arc_strips
  end

  @impl Drafter.Widget
  def handle_event(_event, state), do: {:bubble, state}

  @impl Drafter.Widget
  def update(props, state) do
    %{state |
      value: Map.get(props, :value, state.value),
      label: Map.get(props, :label, state.label),
      renderer: Map.get(props, :renderer, state.renderer)
    }
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  def component_tag, do: :gauge

  def from_component_opts(_args, opts) do
    %{
      value: Keyword.get(opts, :value, 0.0),
      label: Keyword.get(opts, :label),
      low_threshold: Keyword.get(opts, :low_threshold, 0.8),
      high_threshold: Keyword.get(opts, :high_threshold, 0.9),
      low_color: Keyword.get(opts, :low_color, {80, 200, 80}),
      mid_color: Keyword.get(opts, :mid_color, {220, 140, 0}),
      high_color: Keyword.get(opts, :high_color, {220, 60, 60}),
      track_color: Keyword.get(opts, :track_color, {55, 55, 55}),
      renderer: Keyword.get(opts, :renderer, :text)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      value: mount_props.value,
      label: mount_props.label
    }
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    case Drafter.RingBuffer.last(buffer) do
      nil -> state
      value -> %{state | value: value}
    end
  end

  defp build_arc_map(state, cx, cy, radius, thickness) do
    value_angle = @arc_start + state.value * @arc_sweep
    inner_r2 = (radius - thickness / 2.0) ** 2
    outer_r2 = (radius + thickness / 2.0) ** 2
    max_bx = trunc(cx + radius + thickness) + 1
    max_by = trunc(cy + radius + thickness) + 1

    for bx <- 0..max_bx,
        by <- 0..max_by,
        dx = bx - cx,
        dy = by - cy,
        dist2 = dx * dx + dy * dy,
        dist2 >= inner_r2 and dist2 <= outer_r2,
        angle_deg = :math.atan2(dx, -dy) * 180.0 / :math.pi(),
        angle_deg >= @arc_start and angle_deg <= @arc_start + @arc_sweep,
        reduce: %{} do
      acc ->
        {color, filled} = dot_color(angle_deg, value_angle, state)
        key = {div(bx, 2), div(by, 4)}
        bit = Map.get(@braille_dots, {rem(bx, 2), rem(by, 4)}, 0)
        Map.update(acc, key, [{bit, color, filled}], &[{bit, color, filled} | &1])
    end
  end

  defp dot_color(angle_deg, value_angle, state) do
    if angle_deg <= value_angle do
      frac = (angle_deg - @arc_start) / @arc_sweep

      color =
        cond do
          frac >= state.high_threshold -> state.high_color
          frac >= state.low_threshold -> state.mid_color
          true -> state.low_color
        end

      {color, true}
    else
      {state.track_color, false}
    end
  end

  defp row_strip(braille_map, row, width) do
    segments = Enum.map(0..(width - 1), &render_braille_cell(braille_map, &1, row))
    Strip.new(segments)
  end

  defp render_braille_cell(braille_map, col, row) do
    case Map.get(braille_map, {col, row}) do
      nil ->
        Segment.new(" ", %{})

      dots ->
        {bits, color} = merge_dots(dots)
        char = if bits == 0, do: " ", else: <<@braille_base + bits::utf8>>
        Segment.new(char, %{fg: color})
    end
  end

  defp merge_dots(dots) do
    bits = Enum.reduce(dots, 0, fn {b, _, _}, acc -> bor(acc, b) end)
    {_, color, _} = Enum.find(dots, hd(dots), fn {_, _, filled} -> filled end)
    {bits, color}
  end

  defp value_overlay_strip(braille_map, row, width, state) do
    text = format_value(state.value)
    color = value_color(state.value, state)
    text_len = String.length(text)
    text_start = div(width - text_len, 2)
    text_chars = String.graphemes(text)

    segments =
      Enum.map(0..(width - 1), fn col ->
        text_offset = col - text_start
        render_overlay_cell(text_offset, text_len, text_chars, color, braille_map, col, row)
      end)

    Strip.new(segments)
  end

  defp render_overlay_cell(text_offset, text_len, text_chars, color, _braille_map, _col, _row)
       when text_offset >= 0 and text_offset < text_len do
    Segment.new(Enum.at(text_chars, text_offset), %{fg: color})
  end

  defp render_overlay_cell(_text_offset, _text_len, _text_chars, _color, braille_map, col, row) do
    render_braille_cell(braille_map, col, row)
  end

  defp center_strip(text, width, color) do
    len = String.length(text)
    pad = max(0, width - len)
    left = div(pad, 2)
    right = pad - left
    padded = String.duplicate(" ", left) <> text <> String.duplicate(" ", right)
    Strip.new([Segment.new(padded, %{fg: color})])
  end

  defp format_value(value) do
    pct = round(value * 100)
    "#{pct}%"
  end

  defp value_color(value, state) do
    cond do
      value >= state.high_threshold -> state.high_color
      value >= state.low_threshold -> state.mid_color
      true -> state.low_color
    end
  end
end
