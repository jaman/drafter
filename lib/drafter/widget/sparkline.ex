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

  ## Component tag

  Tag `:sparkline`, built by `Drafter.App` as `{:sparkline, data, opts}`:

      sparkline(data, opts)

  The positional argument becomes `:data` when it is a non-empty list that is not
  a keyword list; otherwise `:data` is read from `opts`. Both
  `sparkline(values, summary: true)` and `sparkline(data: values, summary: true)`
  are therefore valid.

  ## Options

    * `:data` - `[number()]` to plot. Default `[]`. Only the first `width` values
      of a vertical sparkline and the first `rect.height` values of a horizontal
      one are drawn.
    * `:min_value` - `t:number/0` explicit minimum for scaling. Default:
      `Enum.min(data)`, or `0` when the data is empty. A `nil` value falls back to
      the same default.
    * `:max_value` - `t:number/0` explicit maximum for scaling. Default:
      `Enum.max(data)`, or `0` when the data is empty. A `nil` value falls back to
      the same default.
    * `:min_color` - `{r, g, b}` colour for the lowest bars. Default `nil`, which
      uses the sparkline's computed theme colour, itself falling back to
      `{100, 200, 100}`.
    * `:max_color` - `{r, g, b}` colour for the highest bars. Default `nil`, with
      the same fallback as `:min_color`. Equal min and max colours make every bar
      that colour.
    * `:color` - `{r, g, b}`. Default `nil`. Held on the state and never read by
      `render/2`, which takes its base colour from the theme.
    * `:summary` - `t:boolean/0`, append `min:X max:Y avg:Z` at the right edge.
      Default `false`. Reserves 20 columns of the rect for the text. Only drawn for
      a vertical sparkline, though `apply_data_buffer/3` reserves the same 20
      columns either way.
    * `:orientation` - `:vertical | :horizontal`. Default `:vertical`; any value
      other than `:horizontal` renders vertically.
    * `:style` - `t:map/0` of style overrides passed to the theme computation.
      Default `%{}`.
    * `:class` - theme class atom or list of them, normalised by
      `Drafter.Style.normalize_classes/1` and reaching `mount/1` as `:classes`.
      Default `[]`.
    * `:height` - `t:pos_integer/0` read only by `preferred_height/2`, never by
      `mount/1`. Default `3`.

  Every option except `:height` is live-updatable: `update_props_from_mount/3`
  passes the full mount props through. Supplying `:data` without `:min_value` or
  `:max_value` rescales the sparkline to the new data.

  ## Usage

      sparkline(data: [1, 3, 2, 8, 5, 9, 4], summary: true)
      sparkline(data: readings, min_color: {100, 200, 100}, max_color: {255, 50, 50})
      sparkline(data: readings, orientation: :horizontal)
  """

  use Drafter.Widget

  alias Drafter.{CharacterSet, RingBuffer, Visualization}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

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

  @type rgb :: {0..255, 0..255, 0..255}

  @type t :: %__MODULE__{
          data: [number()],
          min_value: number(),
          max_value: number(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          color: rgb() | nil,
          min_color: rgb() | nil,
          max_color: rgb() | nil,
          summary: boolean(),
          orientation: :vertical | :horizontal
        }

  @doc """
  Builds the widget state from `props`.

  `:min_value` and `:max_value` are taken from `props` when present and not `nil`,
  and otherwise from the data — `Enum.min/1` and `Enum.max/1`, or `0` and `0` for
  empty data.

      iex> state = Drafter.Widget.Sparkline.mount(%{data: [1, 3, 2, 8]})
      iex> {state.min_value, state.max_value, state.summary, state.orientation}
      {1, 8, false, :vertical}

      iex> state = Drafter.Widget.Sparkline.mount(%{})
      iex> {state.data, state.min_value, state.max_value}
      {[], 0, 0}

      iex> Drafter.Widget.Sparkline.mount(%{data: [1, 2], max_value: 100}).max_value
      100
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    data = Map.get(props, :data, [])

    {min_val, max_val} =
      if data != [] do
        {Enum.min(data), Enum.max(data)}
      else
        {0, 0}
      end

    %__MODULE__{
      data: data,
      min_value: Map.get(props, :min_value) || min_val,
      max_value: Map.get(props, :max_value) || max_val,
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

  @doc """
  Draws the sparkline into `rect`.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. A vertical sparkline returns a single strip. A horizontal one returns one
  strip per data point, capped at `rect.height`, so it returns `[]` for empty data.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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
      render_vertical(state, rect, bg, min_color, max_color, default_color)
    end
  end

  @doc """
  Replaces `:data` with the newest entries of a `Drafter.RingBuffer` and rescales
  `:min_value` and `:max_value` to them.

  Takes the last `rect.width` values, or `rect.width - 20` when `:summary` is set,
  with a floor of one value. Returns `state` unchanged for an empty buffer, which
  is the only case where an explicit `:min_value` or `:max_value` survives.
  """
  @spec apply_data_buffer(t(), RingBuffer.t(), Drafter.Widget.rect()) :: t()
  @impl Drafter.Widget
  def apply_data_buffer(state, %RingBuffer{count: 0}, _rect), do: state

  def apply_data_buffer(state, buffer, rect) do
    width = if state.summary, do: rect.width - 20, else: rect.width
    data = RingBuffer.last_n(buffer, max(1, width))

    {min_val, max_val} = {Enum.min(data), Enum.max(data)}

    %{state | data: data, min_value: min_val, max_value: max_val}
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`.

  A plain props map is passed through `mount/1` first, so the returned state is
  always a `t:t/0`. The sparkline is not focusable.
  """
  @spec handle_event(Drafter.Event.t(), t() | Drafter.Widget.props()) :: {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(_event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    {:noreply, state}
  end

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  New `:data` rescales `:min_value` and `:max_value` to it unless `props` carries a
  non-`nil` `:min_value` or `:max_value` of its own. Empty new data keeps the
  existing scale.

      iex> state = Drafter.Widget.Sparkline.mount(%{data: [1, 2, 3]})
      iex> updated = Drafter.Widget.Sparkline.update(%{data: [10, 20]}, state)
      iex> {updated.data, updated.min_value, updated.max_value}
      {[10, 20], 10, 20}

      iex> state = Drafter.Widget.Sparkline.mount(%{data: [1, 2, 3]})
      iex> updated = Drafter.Widget.Sparkline.update(%{data: [10, 20], max_value: 50}, state)
      iex> {updated.min_value, updated.max_value}
      {10, 50}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)

    {min_val, max_val} =
      if new_data != [] do
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

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `3`.

      iex> Drafter.Widget.Sparkline.preferred_height(nil, [])
      3

      iex> Drafter.Widget.Sparkline.preferred_height([1, 2, 3], height: 8)
      8
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 3)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Sparkline.component_tag()
      :sparkline
  """
  @spec component_tag() :: :sparkline
  def component_tag, do: :sparkline

  @doc """
  Builds the props map for a `{:sparkline, data, opts}` element.

  `data` becomes `:data` when it is a non-empty list that is not a keyword list;
  otherwise `opts[:data]` is used, defaulting to `[]`. `:class` is normalised into
  `:classes` and `:__app_module__` becomes `:app_module`.

      iex> props = Drafter.Widget.Sparkline.from_component_opts([1, 3, 2], summary: true)
      iex> {props.data, props.summary, props.min_value}
      {[1, 3, 2], true, nil}

      iex> props = Drafter.Widget.Sparkline.from_component_opts([data: [4, 5]], [])
      iex> props.data
      []

      iex> Drafter.Widget.Sparkline.from_component_opts(nil, data: [4, 5]).data
      [4, 5]
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(data, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    all_data =
      if is_list(data) and data != [] and not Keyword.keyword?(data) do
        data
      else
        Keyword.get(opts, :data, [])
      end

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

  @doc """
  Passes the mount props through unchanged, so every option is live-updatable
  through the component tree.

      iex> props = Drafter.Widget.Sparkline.from_component_opts([1, 2], [])
      iex> Drafter.Widget.Sparkline.update_props_from_mount(props, %{}, []) == props
      true
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp render_vertical(state, rect, bg, min_color, max_color, default_color) do
    spark_width = if state.summary, do: rect.width - 20, else: rect.width

    {sparkline_chars, normalized_values} =
      render_sparkline_with_values(state.data, state.min_value, state.max_value, spark_width)

    spark_segments =
      sparkline_chars
      |> String.graphemes()
      |> Enum.zip(normalized_values)
      |> Enum.map(fn {char, normalized} ->
        Segment.new(char, %{fg: interpolate_color(min_color, max_color, normalized), bg: bg})
      end)

    output =
      append_sparkline_tail(spark_segments, state, rect.width, sparkline_chars, default_color, bg)

    [Strip.new(output)]
  end

  defp append_sparkline_tail(
         segments,
         %{summary: true, data: data},
         width,
         sparkline_chars,
         _default_color,
         bg
       )
       when data != [] do
    summary_text = render_summary(data, Enum.min(data), Enum.max(data))
    padding_width = max(0, width - String.length(sparkline_chars) - String.length(summary_text))

    segments ++
      [
        Segment.new(String.duplicate(" ", padding_width), %{bg: bg}),
        Segment.new(summary_text, %{fg: {150, 150, 150}, bg: bg})
      ]
  end

  defp append_sparkline_tail(segments, _state, width, sparkline_chars, default_color, bg) do
    padding_width = max(0, width - String.length(sparkline_chars))
    segments ++ [Segment.new(String.duplicate(" ", padding_width), %{fg: default_color, bg: bg})]
  end

  defp render_horizontal(state, rect, bg, min_color, max_color) do
    levels = CharacterSet.sparkline_levels_h()
    full = CharacterSet.fill(:full)
    level_count = length(levels)

    state.data
    |> Enum.take(rect.height)
    |> Enum.map(fn value ->
      normalized = Visualization.normalize(value, state.min_value, state.max_value)
      total_steps = round(normalized * rect.width * (level_count - 1))
      full_blocks = div(total_steps, level_count - 1)
      remainder = rem(total_steps, level_count - 1)

      full_str = Visualization.safe_duplicate(full, full_blocks)

      partial_str =
        if remainder > 0 and full_blocks < rect.width do
          Enum.at(levels, remainder)
        else
          ""
        end

      bar_len = full_blocks + if(remainder > 0 and full_blocks < rect.width, do: 1, else: 0)
      padding = Visualization.safe_duplicate(" ", rect.width - bar_len)

      interpolated_color = interpolate_color(min_color, max_color, normalized)

      Strip.new([
        Segment.new(full_str <> partial_str <> padding, %{fg: interpolated_color, bg: bg})
      ])
    end)
  end

  @doc """
  Turns `data` into `{bar_characters, normalized_values}`.

  Takes at most `width` values, normalises each into `0.0..1.0` against `min_val`
  and `max_val`, and picks the matching character from the current skin's vertical
  sparkline levels. Empty data returns `width` spaces and `width` values of `0.5`.
  The two elements of the result always have the same length, which is
  `min(length(data), width)` for non-empty data.

      iex> Drafter.Widget.Sparkline.render_sparkline_with_values([], 0, 0, 3)
      {"   ", [0.5, 0.5, 0.5]}

      iex> {chars, values} = Drafter.Widget.Sparkline.render_sparkline_with_values([1, 5, 10], 1, 10, 2)
      iex> {String.length(chars), values}
      {2, [0.0, 0.4444444444444444]}
  """
  @spec render_sparkline_with_values([number()], number(), number(), non_neg_integer()) ::
          {String.t(), [float()]}
  def render_sparkline_with_values(data, min_val, max_val, width) do
    levels = CharacterSet.sparkline_levels_v()

    if data == [] do
      {String.duplicate(" ", width), List.duplicate(0.5, width)}
    else
      result =
        data
        |> Enum.take(width)
        |> Enum.map(fn value ->
          normalized = Visualization.normalize(value, min_val, max_val)
          idx = Visualization.level_index(normalized, levels)
          {Enum.at(levels, idx), normalized}
        end)

      {Enum.map_join(result, fn {char, _} -> char end), Enum.map(result, fn {_, val} -> val end)}
    end
  end

  @doc """
  Blends two `{r, g, b}` colours, rounding each channel.

  `factor` must be a float — an integer raises `FunctionClauseError`. `0.0` returns
  the first colour and `1.0` the second; values outside `0.0..1.0` extrapolate.

      iex> Drafter.Widget.Sparkline.interpolate_color({0, 0, 0}, {200, 100, 50}, 0.5)
      {100, 50, 25}

      iex> Drafter.Widget.Sparkline.interpolate_color({10, 20, 30}, {200, 100, 50}, 0.0)
      {10, 20, 30}
  """
  @spec interpolate_color(rgb(), rgb(), float()) :: rgb()
  def interpolate_color({r1, g1, b1}, {r2, g2, b2}, factor) when is_float(factor) do
    r = round(r1 + (r2 - r1) * factor)
    g = round(g1 + (g2 - g1) * factor)
    b = round(b1 + (b2 - b1) * factor)
    {r, g, b}
  end

  defp render_summary(data, min_val, max_val) do
    avg = if data != [], do: Enum.sum(data) / length(data), else: 0

    "min:#{Visualization.format_number(min_val)} max:#{Visualization.format_number(max_val)} avg:#{Visualization.format_number(avg)}"
  end
end
