defmodule Drafter.Widget.Sparkline do
  @moduledoc """
  Renders a compact sparkline chart using Unicode block characters.

  Each data point maps to one of the nine bar heights `▁▂▃▄▅▆▇█` (or a blank
  for the minimum). When `:min_color` and `:max_color` differ, individual bars
  are coloured by linear interpolation between those two colours based on their
  normalised value. An optional summary appends `min:X max:Y avg:Z` text to the
  right of the bars.

  When `orientation: :horizontal` is set, each data point becomes one row and
  bars grow left-to-right using left-aligned eighth-block characters.

  ## Options

    * `:data` - list of numbers to plot (default `[]`)
    * `:min_value` - explicit minimum for scaling; defaults to `Enum.min(data)`
    * `:max_value` - explicit maximum for scaling; defaults to `Enum.max(data)`
    * `:color` - `{r, g, b}` base bar colour
    * `:min_color` - `{r, g, b}` colour for the lowest bars (falls back to `:color`)
    * `:max_color` - `{r, g, b}` colour for the highest bars (falls back to `:color`)
    * `:summary` - show `min/max/avg` summary at the right edge: `true` / `false` (default)
    * `:orientation` - `:vertical` (default) or `:horizontal`
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      sparkline(data: [1, 3, 2, 8, 5, 9, 4], summary: true)
      sparkline(data: readings, min_color: {100, 200, 100}, max_color: {255, 50, 50})
      sparkline(data: readings, orientation: :horizontal)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @spark_bars [
    {" ", 0},
    {"▁", 1},
    {"▂", 2},
    {"▃", 3},
    {"▄", 4},
    {"▅", 5},
    {"▆", 6},
    {"▇", 7},
    {"█", 8}
  ]

  @horizontal_blocks [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]

  defstruct [
    :data,
    :min_value,
    :max_value,
    :style,
    :classes,
    :app_module,
    :color,
    :min_color,
    :max_color,
    :summary,
    :orientation
  ]

  @impl Drafter.Widget
  def mount(props) do
    data = Map.get(props, :data, [])

    {min_val, max_val} =
      if length(data) > 0 do
        {Enum.min(data), Enum.max(data)}
      else
        {0, 0}
      end

    %__MODULE__{
      data: data,
      min_value: Map.get(props, :min_value, min_val),
      max_value: Map.get(props, :max_value, max_val),
      color: Map.get(props, :color),
      min_color: Map.get(props, :min_color),
      max_color: Map.get(props, :max_color),
      summary: Map.get(props, :summary, false),
      orientation: Map.get(props, :orientation, :vertical),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    classes = state.classes
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:sparkline, state, computed_opts)

    bg = computed[:background] || {30, 30, 30}

    default_color = computed[:color] || {100, 200, 100}

    min_color = state.min_color || default_color
    max_color = state.max_color || default_color

    if state.orientation == :horizontal do
      render_horizontal(state, rect, bg, min_color, max_color)
    else
      summary_style = %{fg: {150, 150, 150}, bg: bg}

      spark_width = if state.summary, do: rect.width - 20, else: rect.width

      {sparkline_chars, normalized_values} =
        render_sparkline_with_values(state.data, state.min_value, state.max_value, spark_width)

      spark_segments =
        sparkline_chars
        |> String.graphemes()
        |> Enum.zip(normalized_values)
        |> Enum.map(fn {char, normalized} ->
          interpolated_color = interpolate_color(min_color, max_color, normalized)
          Segment.new(char, %{fg: interpolated_color, bg: bg})
        end)

      output =
        if state.summary and length(state.data) > 0 do
          summary_text = render_summary(state.data, state.min_value, state.max_value)

          padding_width =
            max(0, rect.width - String.length(sparkline_chars) - String.length(summary_text))

          summary_padding = String.duplicate(" ", padding_width)

          spark_segments ++
            [
              Segment.new(summary_padding, %{fg: default_color, bg: bg}),
              Segment.new(summary_text, summary_style)
            ]
        else
          padding_width = max(0, rect.width - String.length(sparkline_chars))
          padding = String.duplicate(" ", padding_width)
          spark_segments ++ [Segment.new(padding, %{fg: default_color, bg: bg})]
        end

      [Strip.new(output)]
    end
  end

  @impl Drafter.Widget
  def handle_event(_event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    {:noreply, state}
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)

    {min_val, max_val} =
      if length(new_data) > 0 do
        {Enum.min(new_data), Enum.max(new_data)}
      else
        {state.min_value, state.max_value}
      end

    use_custom_min = Map.has_key?(props, :min_value) and Map.get(props, :min_value) != nil
    use_custom_max = Map.has_key?(props, :max_value) and Map.get(props, :max_value) != nil

    %{
      state
      | data: new_data,
        min_value: if(use_custom_min, do: Map.get(props, :min_value), else: min_val),
        max_value: if(use_custom_max, do: Map.get(props, :max_value), else: max_val),
        color: Map.get(props, :color, state.color),
        min_color: Map.get(props, :min_color, state.min_color),
        max_color: Map.get(props, :max_color, state.max_color),
        summary: Map.get(props, :summary, state.summary),
        orientation: Map.get(props, :orientation, state.orientation),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :sparkline

  def from_component_opts(data, opts) do
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
      c when is_binary(c) -> String.to_atom(c)
      c when is_atom(c) -> c
    end)
    all_data = if is_list(data), do: data, else: Keyword.get(opts, :data, [])
    %{
      data: all_data,
      min_value: Keyword.get(opts, :min_value),
      max_value: Keyword.get(opts, :max_value),
      color: Keyword.get(opts, :color),
      min_color: Keyword.get(opts, :min_color),
      max_color: Keyword.get(opts, :max_color),
      summary: Keyword.get(opts, :summary, false),
      orientation: Keyword.get(opts, :orientation, :vertical),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp render_horizontal(state, rect, bg, min_color, max_color) do
    data = state.data
    min_val = state.min_value
    max_val = state.max_value
    range = max_val - min_val

    data
    |> Enum.take(rect.height)
    |> Enum.map(fn value ->
      normalized =
        if range > 0 do
          (value - min_val) / range
        else
          0.5
        end

      total_eighths = round(normalized * rect.width * 8)
      full_blocks = div(total_eighths, 8)
      remainder = rem(total_eighths, 8)

      full_str = String.duplicate("█", full_blocks)

      partial_str =
        if remainder > 0 and full_blocks < rect.width do
          Enum.at(@horizontal_blocks, remainder)
        else
          ""
        end

      bar_len = full_blocks + if(remainder > 0 and full_blocks < rect.width, do: 1, else: 0)
      padding = String.duplicate(" ", max(0, rect.width - bar_len))

      bar_text = full_str <> partial_str <> padding

      interpolated_color = interpolate_color(min_color, max_color, normalized)
      Strip.new([Segment.new(bar_text, %{fg: interpolated_color, bg: bg})])
    end)
  end

  def render_sparkline_with_values(data, min_val, max_val, width) do
    if length(data) == 0 or min_val == max_val do
      {String.duplicate(" ", width), List.duplicate(0.5, width)}
    else
      range = max_val - min_val

      result =
        data
        |> Enum.take(width)
        |> Enum.map(fn value ->
          normalized =
            if range > 0 do
              (value - min_val) / range
            else
              0.5
            end

          bar_index = round(normalized * 8)
          {bar, _} = Enum.at(@spark_bars, min(8, max(0, bar_index)))
          {bar, normalized}
        end)

      chars = Enum.map(result, fn {char, _} -> char end)
      values = Enum.map(result, fn {_, val} -> val end)

      {Enum.join(chars), values}
    end
  end

  def interpolate_color({r1, g1, b1}, {r2, g2, b2}, factor) when is_float(factor) do
    r = round(r1 + (r2 - r1) * factor)
    g = round(g1 + (g2 - g1) * factor)
    b = round(b1 + (b2 - b1) * factor)
    {r, g, b}
  end

  defp render_summary(data, min_val, max_val) do
    count = length(data)
    sum = Enum.sum(data)
    avg = if count > 0, do: sum / count, else: 0

    min_str = format_number(min_val)
    max_str = format_number(max_val)
    avg_str = format_number(avg)

    "min:#{min_str} max:#{max_str} avg:#{avg_str}"
  end

  defp format_number(n) when is_integer(n), do: "#{n}"
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_number(_), do: "0"
end
