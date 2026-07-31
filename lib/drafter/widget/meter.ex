defmodule Drafter.Widget.Meter do
  @moduledoc """
  Renders a horizontal or vertical meter with threshold-based color zones.

  Uses Unicode eighth-block characters for sub-character precision on horizontal
  meters and vertical block characters for vertical meters. Color zones are
  defined via configurable thresholds.

  ## Options

    * `:value` - float in `0.0..1.0` (default `0.0`)
    * `:label` - optional title string
    * `:orientation` - `:horizontal` (default) or `:vertical`
    * `:thresholds` - list of `{value, {r, g, b}}` tuples defining color zone
      boundaries (default: green to 60%, yellow to 80%, red above)
    * `:show_value` - display percentage text (default `true`)
    * `:show_label` - display the label (default `true`)
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      meter(value: 0.72)
      meter(value: 0.45, label: "CPU", orientation: :vertical)
      meter(value: 0.95, thresholds: [{0.5, {0, 200, 0}}, {0.75, {255, 200, 0}}, {1.0, {255, 0, 0}}])
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}

  @horizontal_blocks ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
  @vertical_blocks ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  @default_thresholds [
    {0.6, {80, 200, 100}},
    {0.8, {255, 200, 0}},
    {1.0, {255, 60, 60}}
  ]

  defstruct [
    :value,
    :label,
    :orientation,
    :thresholds,
    :show_value,
    :show_label,
    :style,
    :classes,
    :app_module
  ]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      value: Map.get(props, :value, 0.0),
      label: Map.get(props, :label),
      orientation: Map.get(props, :orientation, :horizontal),
      thresholds: Map.get(props, :thresholds, @default_thresholds),
      show_value: Map.get(props, :show_value, true),
      show_label: Map.get(props, :show_label, true),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case state.orientation do
      :vertical -> render_vertical(state, rect)
      _horizontal -> render_horizontal(state, rect)
    end
  end

  @impl Drafter.Widget
  def handle_event(_event, state), do: {:noreply, state}

  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | value: Map.get(props, :value, state.value),
        label: Map.get(props, :label, state.label),
        orientation: Map.get(props, :orientation, state.orientation),
        thresholds: Map.get(props, :thresholds, state.thresholds),
        show_value: Map.get(props, :show_value, state.show_value),
        show_label: Map.get(props, :show_label, state.show_label),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  def preferred_height(_args, opts) do
    if Keyword.get(opts, :orientation, :horizontal) == :vertical do
      Keyword.get(opts, :height, 8)
    else
      has_label = Keyword.get(opts, :label) != nil and Keyword.get(opts, :show_label, true)
      if has_label, do: 2, else: 1
    end
  end

  def component_tag, do: :meter

  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      value: Keyword.get(opts, :value, 0.0),
      label: Keyword.get(opts, :label),
      orientation: Keyword.get(opts, :orientation, :horizontal),
      thresholds: Keyword.get(opts, :thresholds, @default_thresholds),
      show_value: Keyword.get(opts, :show_value, true),
      show_label: Keyword.get(opts, :show_label, true),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      value: mount_props.value,
      label: mount_props.label,
      orientation: mount_props.orientation,
      thresholds: mount_props.thresholds,
      show_value: mount_props.show_value,
      show_label: mount_props.show_label
    }
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    case Drafter.RingBuffer.last(buffer) do
      nil -> state
      value -> %{state | value: value}
    end
  end

  defp render_horizontal(state, rect) do
    clamped = clamp(state.value, 0.0, 1.0)
    color = color_for_value(clamped, state.thresholds)
    track_color = {55, 55, 55}

    value_text = if state.show_value, do: " #{percentage_text(clamped)}", else: ""
    value_width = String.length(value_text)
    bar_width = max(0, rect.width - value_width)

    total_eighths = round(clamped * bar_width * 8)
    full_blocks = div(total_eighths, 8)
    remainder = rem(total_eighths, 8)

    filled_str = String.duplicate("█", full_blocks)

    partial_str =
      if remainder > 0 and full_blocks < bar_width do
        Enum.at(@horizontal_blocks, remainder - 1)
      else
        ""
      end

    filled_width = full_blocks + if(partial_str != "", do: 1, else: 0)
    empty_width = max(0, bar_width - filled_width)
    empty_str = String.duplicate(" ", empty_width)

    bar_segments = [
      Segment.new(filled_str <> partial_str, %{fg: color, bg: track_color}),
      Segment.new(empty_str, %{fg: track_color, bg: track_color})
    ]

    bar_segments =
      if state.show_value do
        bar_segments ++ [Segment.new(value_text, %{fg: {180, 180, 180}})]
      else
        bar_segments
      end

    bar_strip = Strip.new(bar_segments)

    if state.show_label and state.label do
      label_str = truncate(state.label, rect.width)
      padding = max(0, rect.width - String.length(label_str))

      label_strip =
        Strip.new([
          Segment.new(label_str <> String.duplicate(" ", padding), %{fg: {160, 160, 160}})
        ])

      [label_strip, bar_strip]
    else
      [bar_strip]
    end
  end

  defp render_vertical(state, rect) do
    clamped = clamp(state.value, 0.0, 1.0)
    color = color_for_value(clamped, state.thresholds)
    track_color = {55, 55, 55}

    label_rows = if state.show_label and state.label, do: 1, else: 0
    value_rows = if state.show_value, do: 1, else: 0
    bar_height = max(1, rect.height - label_rows - value_rows)

    bar_strips = build_vertical_bars(clamped, bar_height, color, track_color, rect.width)

    vertical_label_strips(state, rect.width) ++
      bar_strips ++
      vertical_value_strips(state, clamped, rect.width)
  end

  defp build_vertical_bars(clamped, bar_height, color, track_color, width) do
    total_eighths = round(clamped * bar_height * 8)
    full_rows = div(total_eighths, 8)
    remainder = rem(total_eighths, 8)

    for row <- 0..(bar_height - 1)//1 do
      row_from_bottom = bar_height - 1 - row
      {char, fg} = vertical_row_char(row_from_bottom, full_rows, remainder, color, track_color)
      bar_str = center_text(char, width)
      Strip.new([Segment.new(bar_str, %{fg: fg, bg: track_color})])
    end
  end

  defp vertical_row_char(row_from_bottom, full_rows, _remainder, color, _track_color)
       when row_from_bottom < full_rows do
    {"█", color}
  end

  defp vertical_row_char(row_from_bottom, full_rows, remainder, color, _track_color)
       when row_from_bottom == full_rows and remainder > 0 do
    {Enum.at(@vertical_blocks, remainder - 1), color}
  end

  defp vertical_row_char(_row_from_bottom, _full_rows, _remainder, _color, track_color) do
    {" ", track_color}
  end

  defp vertical_label_strips(%{show_label: true, label: label}, width) when not is_nil(label) do
    [center_strip(truncate(label, width), width, {160, 160, 160})]
  end

  defp vertical_label_strips(_state, _width), do: []

  defp vertical_value_strips(%{show_value: true}, clamped, width) do
    [center_strip(percentage_text(clamped), width, {180, 180, 180})]
  end

  defp vertical_value_strips(_state, _clamped, _width), do: []

  defp color_for_value(value, thresholds) do
    sorted = Enum.sort_by(thresholds, &elem(&1, 0))
    find_threshold_color(value, sorted)
  end

  defp find_threshold_color(_value, []), do: {80, 200, 100}
  defp find_threshold_color(_value, [{_threshold, color}]), do: color

  defp find_threshold_color(value, [{threshold, color} | rest]) do
    if value <= threshold, do: color, else: find_threshold_color(value, rest)
  end

  defp percentage_text(value), do: "#{round(value * 100)}%"

  defp clamp(value, min_val, max_val), do: max(min_val, min(max_val, value))

  defp truncate(text, max_len) when byte_size(text) > 0 do
    if String.length(text) > max_len, do: String.slice(text, 0, max_len), else: text
  end

  defp truncate(_text, _max_len), do: ""

  defp center_text(text, width) do
    len = String.length(text)
    pad = max(0, width - len)
    left = div(pad, 2)
    right = pad - left
    String.duplicate(" ", left) <> text <> String.duplicate(" ", right)
  end

  defp center_strip(text, width, color) do
    padded = center_text(text, width)
    Strip.new([Segment.new(padded, %{fg: color})])
  end
end
