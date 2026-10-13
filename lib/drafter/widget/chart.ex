defmodule Drafter.Widget.Chart do
  @moduledoc """
  Renders time-series and financial data as interactive charts with multiple styles.

  Supported chart types: `:line`, `:braille`, `:step`, `:area`, `:braille_area`,
  `:bar`, `:clustered_bar`, `:stacked_bar`, `:range_bar`, `:scatter`, `:bubble`,
  `:histogram`, `:heatmap`, and `:candlestick`. Any unrecognised value renders as
  `:line`.

  Every chart is drawn once as shapes and then painted at the resolution of the
  renderer in use (see `:renderer`): a terminal image at the terminal's own pixels
  per cell, braille at two by four dots per cell, or block characters of a
  `FrenchCurve.Backend.Cells` glyph set. Axis, bar and value labels are drawn as
  text around and over the plot.

  Each chart type reads `:data` in its own shape:

    * `:line`, `:braille`, `:step`, `:area`, `:braille_area`, `:bar` — a list of
      numbers, or a list of such lists for multiple series
    * `:clustered_bar`, `:stacked_bar` — a list of series, each a list of numbers
    * `:range_bar` — a list of `[low, high]` pairs, one per bar
    * `:scatter` — `[x, y]` lists, `{x, y}` tuples, or weighted variants
      `[x, y, weight]` / `{x, y, weight}` where weight is a float between 0.0 and
      1.0. Higher weights produce denser braille dot clusters and brighter colors.
      A list of point-lists renders multiple series
    * `:bubble` — points carrying a magnitude, rendered as sized dots; a list of
      point-lists renders multiple series
    * `:histogram` — a flat list of raw values, binned automatically
    * `:heatmap` — a list of rows, each a list of numbers, forming a matrix
    * `:candlestick` — `[open, high, low, close]` lists or maps with `:open`,
      `:high`, `:low`, `:close` keys

  ## Component tag

  Tag `:chart`, built by `Drafter.App` as `{:chart, data, opts}`:

      chart(data, opts)

  The positional argument becomes `:data` when it is a list; otherwise `:data` is
  read from `opts`. Because a bare keyword list in the first position is treated
  as `opts`, both `chart(values, chart_type: :line)` and
  `chart(data: values, chart_type: :line)` are valid. `:width` and `:height`
  default to the rect the parent allocated.

  ## Negative Values

  All chart types (except candlestick) support negative values natively. The Y-axis
  range is derived from the data including any negative values. For charts that span
  both positive and negative territory a zero-line is drawn automatically when
  `show_axes: true`. Set `min_value` and `max_value` explicitly to pin a symmetric
  range:

      chart(io_data, chart_type: :line, min_value: -150, max_value: 150, show_axes: true)

  ## Multi-Series Charts

  Pass a list of series (each a list of values) to `:data` for `:line`,
  `:clustered_bar`, `:stacked_bar`, and `:scatter`. Each series is rendered in its
  own colour cycling through `:colors`. If `:colors` is empty a built-in palette of
  six hues is used.

      chart([series_a, series_b, series_c],
        chart_type: :line,
        height: 8,
        colors: [{100, 200, 255}, {255, 150, 80}, {80, 255, 150}]
      )

  For `:scatter`, multi-series data is a list of point-lists where each point-list
  contains `[x, y]` pairs:

      chart([series_a_points, series_b_points], chart_type: :scatter, height: 8)

  On `:line`, `:braille`, `:step`, `:area` and `:braille_area` charts a `nil` in a
  series is a gap: nothing is drawn at that position and the series resumes after
  it, so series sampled on a shared time grid stay aligned. Bar charts draw a gap
  as zero.

      chart([[nil, nil, 3, 4, 6], [1, 2, 2, 3, 2]], chart_type: :line, height: 8)

  For `:range_bar`, data is a list of `[low, high]` pairs — one pair per bar:

      chart([[10, 40], [25, 65], [5, 55]], chart_type: :range_bar, height: 8)

  ## Bar Chart Types

    * `:bar` — one bar per data point; a list of series draws as `:clustered_bar`
    * `:clustered_bar` — grouped bars; each group shows one bar per series side
      by side
    * `:stacked_bar` — multi-row stacked bars; series accumulate from the
      baseline (supports negatives — positive series stack upward, negative
      series stack downward)
    * `:range_bar` — one bar per data point spanning a low→high range

  ## Keyboard Controls (when focused)

    * `←` / `→` — scroll the X-axis by 5 data points, clamped at 0 on the left
    * `↑` / `↓` — pan the Y-axis up/down by a tenth of its span per press
    * `?c` — reset the Y-axis pan offset to `0`
    * Click and drag — pan both axes simultaneously

  Every other key bubbles.

  ## Options

    * `:data` — numeric list; list of series for multi-series types; `[low, high]`
      pairs for `:range_bar`. Default `[]`
    * `:chart_type` — `:line` (default), `:step`, `:area`, `:braille`,
      `:braille_area`, `:bar`, `:clustered_bar`, `:stacked_bar`, `:range_bar`,
      `:scatter`, `:bubble`, `:histogram`, `:heatmap`, `:candlestick`. Any other
      value renders as `:line`
    * `:pixel_style` — how a chart whose renderer resolves to `:text` draws:
      `:braille` (default) or `:quadrant`, the `:quad` block characters
    * `:min_value` — explicit Y minimum. Default `nil`, auto-detected from the data
      with 5% padding on each side
    * `:max_value` — explicit Y maximum. Default `nil`, auto-detected from the data
      with 5% padding on each side. When the resolved minimum equals the maximum the
      range is widened by `0.001` either way
    * `:color` — `{r, g, b}` primary colour for single-series charts. Default `nil`,
      falling back to the theme and then to `{100, 200, 255}`
    * `:colors` — list of `{r, g, b}` tuples, one per series for multi-series types;
      the first entry overrides `:color` for single-series bar/scatter/area.
      Default `[]`
    * `:show_axes` — `t:boolean/0`, draw axis lines and the zero-line when the range
      spans zero. Default `false`. Reserves two rows and a labelled left column
    * `:show_labels` — `t:boolean/0`, draw axis tick labels. Default `false`
    * `:title` — `t:String.t/0` displayed on a row above the chart. Default `nil`;
      an empty string is treated the same as `nil`
    * `:x_labels` — list of strings for X-axis tick labels. Default `[]`
    * `:y_labels` — list of strings for Y-axis tick labels. Default `[]`
    * `:orientation` — `:vertical` (default) or `:horizontal`; applies to
      `:bar`, `:clustered_bar`, `:stacked_bar` and `:range_bar` only, and every
      other chart type falls back to the vertical renderer
    * `:bar_labels` — list of strings labelling each bar or group, shown when
      `show_labels: true`. Default `[]`
    * `:show_values` — `t:boolean/0`, show the numeric value after each bar of a
      horizontal bar chart. Default `false`
    * `:fill_opacity` — how strongly an area's fill shows its series colour over
      the chart background, `0.0` (background) to `1.0` (the series colour).
      Default `0.6`
    * `:animated` — `t:boolean/0`. A `:line`, `:area` or `:step` chart of one series
      rotates its points by one every `:animation_speed` milliseconds, in every
      renderer. Default `false`
    * `:animation_speed` — milliseconds per animation frame. Default `100`
    * `:width` — chart width in columns. The element defaults it to the rect the
      parent allocated, but rendering always uses `rect.width`, so this only reaches
      the state
    * `:height` — chart height in rows. The element defaults it to the rect the
      parent allocated; `mount/1` on its own defaults it to `1`
    * `:max_data_points` — cap on retained points; older points are dropped when
      exceeded. Default `nil`, no cap
    * `:bar_gap` — blank columns between bars. Default `0`
    * `:area_fill` — which side of the line the area body fills: `:below`
      (default) or `:inverted` to fill from the line up to the top edge
    * `:show_baseline` — `t:boolean/0`, draw the zero baseline row on stacked
      braille areas. Default `false`
    * `:zero_center` — how a stacked range spanning zero is scaled: `:symmetric`
      (default, equal extent either side of zero), `:independent` to let the
      positive and negative extents differ, each half scaled on its own, or
      `:linear`, one scale from the lowest to the highest value with zero where
      it falls. Ignored when the data does not cross zero
    * `:smooth` — `t:boolean/0`, interpolate between points on line charts.
      Default `false`
    * `:series_names` — list of names, one per series, shown in the value readout.
      Default `[]`, which names them `series 1`, `series 2`, …
    * `:readout_format` — one-arity function turning a value into the text the
      readout shows. Default `nil`, two decimals
    * `:readout_sort` — `:none` (default), `:asc` or `:desc`, the order of series
      in the readout
    * `:stacked` — `t:boolean/0`, on `:braille_area` charts stack each series on
      the ones before it; `false` draws every series from the baseline, later
      series over earlier ones. Default `true`
    * `:line_thickness` — line width for line and area charts, in braille dots;
      an image scales it to the terminal's cell height. Default `1`
    * `:connect_lines` — `t:boolean/0`, join consecutive points of a `:line` or
      `:braille` chart with line segments; `false` draws the points alone.
      Default `true`
    * `:precision` — decimal places in the Y-axis tick labels. Default `3`. Read by
      `mount/1` and `update/2` only; the `chart/2` element does not forward it
    * `:style` — `t:map/0` of style properties. Default `%{}`
    * `:class` — theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:renderer` — rendering backend for this chart: `:text` (braille, or `:quad`
      blocks with `pixel_style: :quadrant`), `:braille`, `:half` / `:quad` / `:sextant` / `:octant` (block
      characters of that `FrenchCurve.Backend.Cells` set, two colours per cell), `:pixel` / `:auto` (best terminal graphics available —
      kitty/iTerm2/sixel image, falling back to braille), or `:iterm2` / `:kitty` /
      `:sixel` to force a protocol. Overrides the runtime `mode:` config, but the
      `DRAFTER_MODE` env var still forces over it. When unset, the global mode applies:
      `DRAFTER_MODE`, then the `mode:` run option (`Drafter.run(App, mode: :pixel)` /
      `Drafter.render_mode/1`), then `:text`.
    * `:image_scale` — for `:pixel` charts on a terminal that has not reported its
      cell size, pixels drawn per cell column (rows use `2×`); default `4`. When the
      terminal reports its cell size (see `:cell_size` in `Drafter.App`), images are
      drawn at that size and this is unused

  `update/2` re-reads every option above except `:width` and `:app_module`, which are
  fixed once the widget is mounted.

  A `:pixel` chart's image is drawn for the frame that shows it and written to the
  terminal with that frame's text, so the chart and the cells around it always change
  together.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`.

  ## Usage

      chart(data: [1, 4, 2, 8, 5, 9, 3], chart_type: :line)
      chart(data: candles, chart_type: :candlestick, show_axes: true)
      chart(data: points, chart_type: :scatter)
      chart(data: [series_a, series_b], chart_type: :clustered_bar, height: 8)
      chart(data: [series_a, series_b], chart_type: :stacked_bar, height: 8)
      chart(data: [[lo, hi] | ...], chart_type: :range_bar, height: 8)
      chart(data: io_data, chart_type: :line, min_value: -150, max_value: 150)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :mouse_up, :drag, :hover],
    scroll: [direction: :horizontal, step: 5]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  alias Drafter.Widget.Chart.{Pixel, Readout}

  @type chart_type ::
          :line
          | :step
          | :bar
          | :clustered_bar
          | :stacked_bar
          | :range_bar
          | :candlestick
          | :area
          | :scatter
          | :histogram
          | :heatmap
          | :bubble
          | :braille
          | :braille_area

  defstruct [
    :data,
    :chart_type,
    :pixel_style,
    :min_value,
    :max_value,
    :width,
    :height,
    :style,
    :classes,
    :app_module,
    :color,
    :colors,
    :show_axes,
    :show_labels,
    :title,
    :x_labels,
    :y_labels,
    :animated,
    :animation_speed,
    :max_data_points,
    :area_fill,
    :fill_opacity,
    :orientation,
    :bar_labels,
    :show_values,
    bar_gap: 0,
    show_baseline: false,
    zero_center: :symmetric,
    focused: false,
    _internal: %{}
  ]

  @type t :: %__MODULE__{
          data: list(),
          chart_type: chart_type(),
          pixel_style: :braille | :quadrant,
          min_value: number(),
          max_value: number(),
          width: pos_integer() | nil,
          height: pos_integer(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          color: {0..255, 0..255, 0..255} | nil,
          colors: [{0..255, 0..255, 0..255}],
          show_axes: boolean(),
          show_labels: boolean(),
          title: String.t() | nil,
          x_labels: [String.t()],
          y_labels: [String.t()],
          animated: boolean(),
          animation_speed: pos_integer(),
          max_data_points: pos_integer() | nil,
          area_fill: :below | :inverted,
          fill_opacity: float(),
          orientation: :vertical | :horizontal,
          bar_labels: [String.t()],
          show_values: boolean(),
          bar_gap: non_neg_integer(),
          show_baseline: boolean(),
          zero_center: :symmetric | :independent | :linear,
          focused: boolean(),
          _internal: map()
        }

  @doc """
  Builds the chart state from `props`.

  Resolves the Y range from `:min_value`/`:max_value` and the data, seeds the
  candlestick live candle, and stores the scroll and drag state under `:_internal`.
  `:height` defaults to `1` here; the `chart/2` element supplies the parent rect's
  height instead.

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3], chart_type: :bar})
      iex> {c.chart_type, c.data, c.height, c.bar_gap, c.show_axes}
      {:bar, [1, 2, 3], 1, 0, false}

      iex> c = Drafter.Widget.Chart.mount(%{data: [0, 100]})
      iex> {c.min_value, c.max_value}
      {-5.0, 105.0}

      iex> c = Drafter.Widget.Chart.mount(%{})
      iex> {c.min_value, c.max_value, c.chart_type, c.pixel_style}
      {-5.0, 105.0, :line, :braille}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    data = Map.get(props, :data, [])
    max_data_points = Map.get(props, :max_data_points)

    data_bounds = data_bounds(data, props)
    {min_val, max_val} = padded_range(data_bounds, props)

    data_hash = :erlang.phash2(data)

    %__MODULE__{
      data: data,
      chart_type: Map.get(props, :chart_type, :line),
      pixel_style: Map.get(props, :pixel_style, :braille),
      min_value: min_val,
      max_value: max_val,
      width: Map.get(props, :width),
      height: Map.get(props, :height, 1),
      color: Map.get(props, :color),
      colors: Map.get(props, :colors, []),
      show_axes: Map.get(props, :show_axes, false),
      show_labels: Map.get(props, :show_labels, false),
      title: Map.get(props, :title),
      x_labels: Map.get(props, :x_labels, []),
      y_labels: Map.get(props, :y_labels, []),
      animated: Map.get(props, :animated, false),
      animation_speed: Map.get(props, :animation_speed, 100),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      max_data_points: max_data_points,
      bar_gap: Map.get(props, :bar_gap, 0),
      area_fill: Map.get(props, :area_fill, :below),
      fill_opacity: Map.get(props, :fill_opacity, 0.6),
      orientation: Map.get(props, :orientation, :vertical),
      bar_labels: Map.get(props, :bar_labels, []),
      show_values: Map.get(props, :show_values, false),
      show_baseline: Map.get(props, :show_baseline, false),
      zero_center: Map.get(props, :zero_center, :symmetric),
      _internal: %{
        precision: Map.get(props, :precision, 3),
        animation_offset:
          animation_frame(
            Map.get(props, :animated, false),
            Map.get(props, :_render_timestamp),
            Map.get(props, :animation_speed, 100)
          ),
        scroll_offset: 0,
        drag_last_x: nil,
        drag_last_y: nil,
        y_offset: 0,
        data_hash: data_hash,
        data_bounds: data_bounds,
        fixed_range: {Map.get(props, :min_value), Map.get(props, :max_value)},
        dragging_scrollbar: false,
        smooth: Map.get(props, :smooth, false),
        stacked: Map.get(props, :stacked, true),
        series_names: Map.get(props, :series_names, []),
        readout_format: Map.get(props, :readout_format),
        readout_sort: Map.get(props, :readout_sort, :none),
        line_thickness: Map.get(props, :line_thickness, 1),
        connect_lines: Map.get(props, :connect_lines, true),
        renderer: Map.get(props, :renderer),
        image_scale: Map.get(props, :image_scale, 4)
      }
    }
  end

  @doc """
  Ends the current drag gesture, clearing `:drag_last_x` and setting
  `:dragging_scrollbar`. A release that ends no drag is a click, and moves the value
  readout cursor to column `x`. Always returns `{:ok, state}` and consumes the event.
  """
  @spec handle_mouse_up(integer(), integer(), t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_mouse_up(x, y, %{_internal: %{drag_last_x: nil}} = state) do
    {:ok, update_internal(state, dragging_scrollbar: true, cursor_x: x, cursor_y: y)}
  end

  def handle_mouse_up(_x, _y, state) do
    {:ok, update_internal(state, dragging_scrollbar: true, drag_last_x: nil)}
  end

  @doc """
  Moves the value readout cursor to the cell `x`, `y` as the pointer passes over the
  chart.

  On `:line`, `:braille`, `:step`, `:area`, `:braille_area` and `:stacked_area`
  charts the point under the cursor column is read; on `:bar`, `:clustered_bar`,
  `:stacked_bar` and `:range_bar` charts the bar or group under it, or under the
  cursor row for horizontal bars. The cursor column is highlighted and a panel
  beside it, to the right when it fits and otherwise to the left, lists the label
  (the `:bar_labels` entry for a bar chart, else the `:x_labels` entry, else
  `#index`) and each series' colour, name (`:series_names`) and value
  (`:readout_format`; a range bar shows `low – high`), ordered by `:readout_sort`. A
  chart drawn as an image has the panel drawn into the image. Returns
  `{:noreply, state}` when the cursor cell is unchanged.
  """
  @spec handle_hover(integer(), integer(), t()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_hover(x, y, %{_internal: %{cursor_x: x, cursor_y: y}} = state), do: {:noreply, state}
  def handle_hover(x, y, state), do: {:ok, update_internal(state, cursor_x: x, cursor_y: y)}

  @doc """
  Pans the chart.

  `:left`/`:ArrowLeft` and `:right`/`:ArrowRight` move the X scroll offset by 5 data
  points, clamped at `0` on the left and at one less than the longest series on
  the right. `:up`/`:ArrowUp` and `:down`/`:ArrowDown` move the Y offset by one
  step, unclamped; each step shifts the drawn value range by a tenth of its span. The codepoint `?c` resets the Y offset to `0`. All of those
  return `{:ok, state}`. `:escape` hides the value readout and bubbles; every
  other key returns `{:bubble, state}`.

      iex> c = Drafter.Widget.Chart.mount(%{data: Enum.to_list(1..20)})
      iex> {:ok, scrolled} = Drafter.Widget.Chart.handle_key(:right, c)
      iex> scrolled._internal.scroll_offset
      5

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3]})
      iex> {:ok, clamped} = Drafter.Widget.Chart.handle_key(:right, c)
      iex> clamped._internal.scroll_offset
      2

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3]})
      iex> {:ok, clamped} = Drafter.Widget.Chart.handle_key(:left, c)
      iex> clamped._internal.scroll_offset
      0

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3]})
      iex> {:ok, panned} = Drafter.Widget.Chart.handle_key(:up, c)
      iex> {:ok, reset} = Drafter.Widget.Chart.handle_key(?c, panned)
      iex> {panned._internal.y_offset, reset._internal.y_offset}
      {1, 0}

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3]})
      iex> Drafter.Widget.Chart.handle_key(:enter, c) |> elem(0)
      :bubble
  """
  @spec handle_key(Drafter.Widget.key() | integer(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_key(:left, state), do: scroll_left(state)
  def handle_key(:ArrowLeft, state), do: scroll_left(state)
  def handle_key(:right, state), do: scroll_right(state)
  def handle_key(:ArrowRight, state), do: scroll_right(state)

  def handle_key(:up, state),
    do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) + 1)}

  def handle_key(:ArrowUp, state),
    do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) + 1)}

  def handle_key(:down, state),
    do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) - 1)}

  def handle_key(:ArrowDown, state),
    do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) - 1)}

  def handle_key(?c, state), do: {:ok, update_internal(state, y_offset: 0)}
  def handle_key(:escape, state), do: {:bubble, update_internal(state, cursor_x: nil)}
  def handle_key(_key, state), do: {:bubble, state}

  @doc """
  Pans both axes as the pointer moves with a button held.

  The first drag event after a press only records the anchor point and leaves the
  offsets alone. Subsequent events move the X scroll offset by the leftward pointer
  delta, clamped as `handle_key/2` clamps it, and the Y offset by the downward
  delta. Always returns `{:ok, state}`.
  """
  @spec handle_drag(integer(), integer(), t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_drag(x, y, %{_internal: %{drag_last_x: nil}} = state) do
    {:ok, update_internal(state, drag_last_x: x, drag_last_y: y)}
  end

  def handle_drag(x, y, state) do
    dx = (state._internal.drag_last_x || x) - x
    dy = y - (state._internal.drag_last_y || y)
    new_x_offset = clamp_scroll(state, (state._internal.scroll_offset || 0) + dx)
    new_y_offset = (state._internal.y_offset || 0) + dy

    {:ok,
     update_internal(state,
       scroll_offset: new_x_offset,
       drag_last_x: x,
       y_offset: new_y_offset,
       drag_last_y: y
     )}
  end

  @doc """
  `opts[:height]`, or `5` when it is absent.

      iex> Drafter.Widget.Chart.preferred_height([1, 2], [])
      5

      iex> Drafter.Widget.Chart.preferred_height([1, 2], height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Chart.component_tag()
      :chart
  """
  @spec component_tag() :: :chart
  def component_tag, do: :chart

  @doc """
  Turns the `{:chart, data, opts}` element into a props map for `mount/1`.

  `data` is used as `:data` when it is a list, and otherwise `opts[:data]` is used,
  which is what lets `chart(chart_type: :line, data: values)` work. `:width` and
  `:height` default to the parent rect passed as `:__rect__`, itself defaulting to
  `%{width: 80, height: 20}`. `:class` is normalised into `:classes`,
  `:__app_module__` becomes `:app_module`, and `:_render_timestamp` is stamped
  from the monotonic clock for an `:animated` chart and is `0` otherwise, so a chart
  that is not animated keeps the same props while its data does not change.

  `:precision` is not forwarded; pass it directly to `mount/1` or `update/2`.

      iex> props = Drafter.Widget.Chart.from_component_opts([1, 2, 3], chart_type: :bar)
      iex> {props.data, props.chart_type, props.width, props.height, props.bar_gap}
      {[1, 2, 3], :bar, 80, 20, 0}

      iex> props = Drafter.Widget.Chart.from_component_opts(nil, data: [4, 5], height: 6)
      iex> {props.data, props.height, props.fill_opacity, props.zero_center}
      {[4, 5], 6, 0.6, :symmetric}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(data, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80, height: 20})
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    all_data = if is_list(data), do: data, else: Keyword.get(opts, :data, [])

    %{
      data: all_data,
      chart_type: Keyword.get(opts, :chart_type, :line),
      pixel_style: Keyword.get(opts, :pixel_style, :braille),
      min_value: Keyword.get(opts, :min_value),
      max_value: Keyword.get(opts, :max_value),
      width: Keyword.get(opts, :width, rect.width),
      height: Keyword.get(opts, :height, rect.height),
      color: Keyword.get(opts, :color),
      colors: Keyword.get(opts, :colors, []),
      show_axes: Keyword.get(opts, :show_axes, false),
      show_labels: Keyword.get(opts, :show_labels, false),
      title: Keyword.get(opts, :title),
      x_labels: Keyword.get(opts, :x_labels, []),
      y_labels: Keyword.get(opts, :y_labels, []),
      animated: Keyword.get(opts, :animated, false),
      animation_speed: Keyword.get(opts, :animation_speed, 100),
      max_data_points: Keyword.get(opts, :max_data_points),
      bar_gap: Keyword.get(opts, :bar_gap, 0),
      area_fill: Keyword.get(opts, :area_fill, :below),
      fill_opacity: Keyword.get(opts, :fill_opacity, 0.6),
      orientation: Keyword.get(opts, :orientation, :vertical),
      bar_labels: Keyword.get(opts, :bar_labels, []),
      show_values: Keyword.get(opts, :show_values, false),
      show_baseline: Keyword.get(opts, :show_baseline, false),
      zero_center: Keyword.get(opts, :zero_center, :symmetric),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__),
      smooth: Keyword.get(opts, :smooth, false),
      stacked: Keyword.get(opts, :stacked, true),
      series_names: Keyword.get(opts, :series_names, []),
      readout_format: Keyword.get(opts, :readout_format),
      readout_sort: Keyword.get(opts, :readout_sort, :none),
      line_thickness: Keyword.get(opts, :line_thickness, 1),
      connect_lines: Keyword.get(opts, :connect_lines, true),
      renderer: Keyword.get(opts, :renderer),
      image_scale: Keyword.get(opts, :image_scale, 4),
      _render_timestamp: render_timestamp(Keyword.get(opts, :animated, false))
    }
  end

  defp render_timestamp(true), do: System.monotonic_time(:millisecond)
  defp render_timestamp(false), do: 0

  @doc """
  Replaces `:data` with everything the widget's data channel has buffered.

  The buffer contents become the whole data set, they are not appended. An empty
  buffer leaves the state alone. The Y range is not recomputed here, so it keeps the
  bounds from the last `mount/1` or `update/2`.
  """
  @spec apply_data_buffer(t(), Drafter.RingBuffer.t(), Drafter.Widget.rect()) :: t()
  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    data = Drafter.RingBuffer.to_list(buffer)

    if data != [] do
      %{state | data: data}
    else
      state
    end
  end

  @doc """
  Draws the chart into `rect`, padded or truncated to exactly `rect.height` strips.

  Returns `[]` when `rect.width` is `0` or less. Accepts either a `t:t/0` or a raw
  props map, which is mounted first. Every renderer draws the same picture of the
  chart at its own resolution: a `:pixel` chart emits blank strips for the plot
  area, because the image itself is emitted separately by the widget server; a
  `:text` or `:braille` chart draws braille, two by four dots per cell (`:text` with
  `pixel_style: :quadrant` draws `:quad` blocks); a cell-set chart draws that set's
  blocks. The y axis, the x axis line and the title row are drawn around the plot
  area when `:show_axes` and `:title` ask for them, labelled with the value range
  the chart was drawn against.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(_state, %{width: width}) when width <= 0, do: []

  def render(state, rect) do
    state = state |> mounted() |> ranged(rect)
    frame = plot_frame(state, rect)

    state
    |> plot_strips(drawing(state), frame)
    |> framed(state, rect, frame, drawing(state))
  end

  defp mounted(state), do: if(is_struct(state, __MODULE__), do: state, else: mount(state))

  defp drawing(state) do
    case Pixel.mode(renderer(state), state.chart_type) do
      :text when state.pixel_style == :quadrant -> {:cells, :quad}
      :text -> :braille
      other -> other
    end
  end

  defp plot_strips(_state, :pixel, frame),
    do: blank_strips(%{width: frame.cols, height: frame.rows})

  defp plot_strips(state, :braille, frame) do
    Pixel.braille_strips(pixel_spec(state), {frame.cols, frame.rows}) ||
      blank_strips(%{width: frame.cols, height: frame.rows})
  end

  defp plot_strips(state, {:cells, set}, frame) do
    Pixel.cells_strips(pixel_spec(state), {frame.cols, frame.rows}, set) ||
      blank_strips(%{width: frame.cols, height: frame.rows})
  end

  defp ranged(state, rect) do
    case Pixel.value_range(pixel_spec(state), {max(1, rect.width), max(1, rect.height)}) do
      {lo, hi} -> %{state | min_value: lo * 1.0, max_value: hi * 1.0}
      nil -> state
    end
  end

  defp blank_strips(rect) do
    blank = Strip.new([Segment.new(String.duplicate(" ", max(1, rect.width)))])
    List.duplicate(blank, max(1, rect.height))
  end

  @doc """
  The chart as a `Drafter.Render.Picture` filling the plot area of `rect`, or `nil`
  when the chart does not resolve to the pixel renderer or cannot be drawn.

  The plot area is `rect` less the y axis column, the x axis row and the title row
  that `render/2` draws as text. The image has the terminal's pixel size per cell
  when the terminal reported it (see `:cell_size` in `Drafter.App`), and carries the
  value readout panel while the pointer is over the chart.
  """
  @spec image_raster(t() | Drafter.Widget.props(), Drafter.Widget.rect()) ::
          Drafter.Render.Picture.t() | nil
  @impl Drafter.Widget
  def image_raster(state, rect) do
    state = state |> mounted() |> ranged(rect)

    case drawing(state) do
      :pixel -> picture(state, rect)
      _ -> nil
    end
  end

  defp picture(state, rect) do
    frame = plot_frame(state, rect)
    {_bg, fg} = chart_colors(state)
    {marker, cells} = Readout.image_overlay(state, frame, Readout.index(state, frame), fg)
    spec = Map.merge(pixel_spec(state), %{marker: marker, overlay: cells})

    case Pixel.picture(spec, Pixel.protocol(renderer(state)), {frame.cols, frame.rows}) do
      nil -> nil
      picture -> %{picture | dx: frame.dx, dy: frame.dy}
    end
  end

  defp chart_colors(state) do
    computed =
      Computed.for_widget(:chart, state,
        classes: state.classes,
        style: state.style,
        app_module: state.app_module
      )

    {computed[:background] || {20, 20, 30}, state.color || computed[:color] || {100, 200, 255}}
  end

  defp plot_frame(state, rect) do
    axis_col_width = compute_y_axis_width(state) + 1
    axes? = state.show_axes and rect.width > axis_col_width
    titled? = is_binary(state.title) and state.title != ""

    dx = if axes?, do: axis_col_width, else: 0
    dy = if titled?, do: 1, else: 0
    axis_rows = if axes?, do: 1, else: 0

    %{
      dx: dx,
      dy: dy,
      cols: max(1, rect.width - dx),
      rows: max(1, rect.height - dy - axis_rows)
    }
  end

  defp framed(plot_strips, state, rect, frame, drawing) do
    {bg, fg} = chart_colors(state)

    plot_strips
    |> apply_axes(state, %{rect | height: frame.rows + 2}, bg, fg)
    |> apply_title(state, rect, bg, fg)
    |> pad_strips(rect.height)
    |> readout(state, frame, fg, drawing)
  end

  defp readout(strips, _state, _frame, _fg, :pixel), do: strips

  defp readout(strips, state, frame, fg, _drawing),
    do: Readout.decorate(strips, state, frame, Readout.index(state, frame), fg)

  @doc "Whether this chart is drawing a transmitted image rather than cells."
  @spec image_active?(t()) :: boolean()
  @impl Drafter.Widget
  def image_active?(state) do
    Pixel.mode(renderer(state), state.chart_type) == :pixel
  end

  defp renderer(state), do: Map.get(state._internal, :renderer)

  defp pixel_spec(state) do
    {bg, _fg} = chart_colors(state)
    {lo, hi} = panned_range(state)
    {fixed_min, fixed_max} = Map.get(state._internal, :fixed_range, {nil, nil})

    %{
      type: state.chart_type,
      data: shown_data(state),
      color: pixel_color(state),
      colors: state.colors,
      bg: bg,
      min: lo,
      max: hi,
      fixed_min: fixed_min,
      fixed_max: fixed_max,
      fill_opacity: state.fill_opacity,
      area_fill: state.area_fill,
      stacked: Map.get(state._internal, :stacked, true),
      zero_center: state.zero_center,
      show_baseline: state.show_baseline,
      smooth: Map.get(state._internal, :smooth, false),
      line_thickness: Map.get(state._internal, :line_thickness, 1),
      connect_lines: Map.get(state._internal, :connect_lines, true),
      orientation: state.orientation,
      bar_gap: state.bar_gap,
      bar_labels: state.bar_labels,
      show_labels: state.show_labels,
      show_values: state.show_values,
      scale: Map.get(state._internal, :image_scale, 4)
    }
  end

  defp panned_range(state) do
    shift = (state._internal[:y_offset] || 0) * (state.max_value - state.min_value) / 10
    {state.min_value + shift, state.max_value + shift}
  end

  @scrolled_types [
    :line,
    :braille,
    :step,
    :area,
    :braille_area,
    :stacked_area,
    :bar,
    :clustered_bar,
    :stacked_bar,
    :range_bar,
    :candlestick
  ]

  @item_types [:candlestick, :range_bar]

  defp shown_data(%{chart_type: type} = state) when type in @scrolled_types do
    state
    |> animated_data()
    |> scrolled(type, state._internal.scroll_offset || 0)
  end

  defp shown_data(state), do: state.data

  defp scrolled(data, _type, 0), do: data

  defp scrolled([first | _] = data, type, offset) when is_list(first) and type not in @item_types,
    do: Enum.map(data, &drop_tail(&1, offset))

  defp scrolled(data, _type, offset) when is_list(data), do: drop_tail(data, offset)
  defp scrolled(data, _type, _offset), do: data

  defp drop_tail(items, offset), do: Enum.drop(items, -min(offset, max(length(items) - 1, 0)))

  @animated_types [:line, :area, :step]

  defp animated_data(%{chart_type: type, data: [first | _] = data} = state)
       when type in @animated_types and is_number(first),
       do: rotate(data, state._internal.animation_offset)

  defp animated_data(state), do: state.data

  defp rotate(data, offset) when offset > 0 do
    shift = rem(offset, length(data))
    Enum.drop(data, shift) ++ Enum.take(data, shift)
  end

  defp rotate(data, _offset), do: data

  defp animation_frame(true, timestamp, speed)
       when is_integer(timestamp) and is_integer(speed) and speed > 0,
       do: div(timestamp, speed)

  defp animation_frame(_animated, _timestamp, _speed), do: 0

  defp updated_animation_frame(props, state) do
    case Map.get(props, :_render_timestamp) do
      nil ->
        state._internal.animation_offset

      timestamp ->
        animation_frame(
          Map.get(props, :animated, state.animated),
          timestamp,
          Map.get(props, :animation_speed, state.animation_speed)
        )
    end
  end

  defp pixel_color(state) do
    base = state.color || List.first(state.colors) || {120, 200, 255}

    case base do
      {r, g, b} -> {r, g, b, 255}
      {r, g, b, a} -> {r, g, b, a}
      _ -> {120, 200, 255, 255}
    end
  end

  @doc """
  Folds fresh props into `state`.

  The Y range is recomputed only when the data hash changes or when `props` carries
  a numeric `:min_value` or `:max_value`; otherwise the current bounds are kept.
  `:width` and `:app_module` are not re-read and keep their mounted values, and
  `:area_fill` falls back to the current value on any falsy prop rather than only on
  a missing key. Scroll offset, drag anchors and Y pan offset survive untouched.

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3]})
      iex> updated = Drafter.Widget.Chart.update(%{data: [10, 20], chart_type: :bar}, c)
      iex> {updated.data, updated.chart_type}
      {[10, 20], :bar}

      iex> c = Drafter.Widget.Chart.mount(%{data: [1, 2, 3], width: 40})
      iex> Drafter.Widget.Chart.update(%{width: 99}, c).width
      40
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)
    new_hash = :erlang.phash2(new_data)
    data_changed = new_hash != state._internal.data_hash

    data_bounds =
      if data_changed or not Map.has_key?(state._internal, :data_bounds),
        do: data_bounds(new_data, props),
        else: state._internal.data_bounds

    {min_val, max_val} =
      if data_changed or custom_range?(props),
        do: padded_range(data_bounds, props),
        else: {state.min_value, state.max_value}

    max_data_points = Map.get(props, :max_data_points, state.max_data_points)

    %{
      state
      | data: new_data,
        chart_type: Map.get(props, :chart_type, state.chart_type),
        pixel_style: Map.get(props, :pixel_style, state.pixel_style),
        min_value: min_val,
        max_value: max_val,
        height: Map.get(props, :height, state.height),
        color: Map.get(props, :color, state.color),
        colors: Map.get(props, :colors, state.colors),
        show_axes: Map.get(props, :show_axes, state.show_axes),
        show_labels: Map.get(props, :show_labels, state.show_labels),
        title: Map.get(props, :title, state.title),
        x_labels: Map.get(props, :x_labels, state.x_labels),
        y_labels: Map.get(props, :y_labels, state.y_labels),
        animated: Map.get(props, :animated, state.animated),
        animation_speed: Map.get(props, :animation_speed, state.animation_speed),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        max_data_points: max_data_points,
        bar_gap: Map.get(props, :bar_gap, state.bar_gap),
        area_fill: Map.get(props, :area_fill) || state.area_fill,
        orientation: Map.get(props, :orientation, state.orientation),
        bar_labels: Map.get(props, :bar_labels, state.bar_labels),
        show_values: Map.get(props, :show_values, state.show_values),
        fill_opacity: Map.get(props, :fill_opacity, state.fill_opacity),
        show_baseline: Map.get(props, :show_baseline, state.show_baseline),
        zero_center: Map.get(props, :zero_center, state.zero_center),
        _internal:
          Map.merge(state._internal, %{
            precision: Map.get(props, :precision, state._internal[:precision] || 3),
            animation_offset: updated_animation_frame(props, state),
            data_hash: new_hash,
            fixed_range: fixed_range(props, state),
            data_bounds: data_bounds,
            renderer: Map.get(props, :renderer, state._internal[:renderer]),
            smooth: Map.get(props, :smooth, state._internal[:smooth]),
            stacked: Map.get(props, :stacked, Map.get(state._internal, :stacked, true)),
            series_names:
              Map.get(props, :series_names, Map.get(state._internal, :series_names, [])),
            readout_format:
              Map.get(props, :readout_format, Map.get(state._internal, :readout_format)),
            readout_sort:
              Map.get(props, :readout_sort, Map.get(state._internal, :readout_sort, :none)),
            line_thickness: Map.get(props, :line_thickness, state._internal[:line_thickness]),
            connect_lines: Map.get(props, :connect_lines, state._internal[:connect_lines]),
            image_scale: Map.get(props, :image_scale, state._internal[:image_scale])
          })
    }
  end

  defp apply_axes(strips, %{show_axes: true} = state, rect, bg, fg),
    do: add_axes(strips, state, rect, bg, fg)

  defp apply_axes(strips, _state, _rect, _bg, _fg), do: strips

  defp apply_title(strips, %{title: title}, rect, bg, fg) when is_binary(title) and title != "",
    do: add_title(strips, title, rect, bg, fg)

  defp apply_title(strips, _state, _rect, _bg, _fg), do: strips

  defp fixed_range(props, state) do
    {previous_min, previous_max} = Map.get(state._internal, :fixed_range, {nil, nil})
    {Map.get(props, :min_value, previous_min), Map.get(props, :max_value, previous_max)}
  end

  defp scroll_left(state),
    do:
      {:ok,
       update_internal(state, scroll_offset: max(0, (state._internal.scroll_offset || 0) - 5))}

  defp scroll_right(state),
    do:
      {:ok,
       update_internal(state,
         scroll_offset: clamp_scroll(state, (state._internal.scroll_offset || 0) + 5)
       )}

  defp clamp_scroll(state, offset), do: offset |> min(max_scroll(state)) |> max(0)

  defp max_scroll(%{data: [first | _] = data}) when is_list(first),
    do: data |> Enum.map(&length/1) |> Enum.max() |> Kernel.-(1) |> max(0)

  defp max_scroll(%{data: data}) when is_list(data), do: max(0, length(data) - 1)
  defp max_scroll(_state), do: 0

  defp custom_range?(props) do
    is_number(Map.get(props, :min_value)) or is_number(Map.get(props, :max_value))
  end

  defp data_bounds(data, props) do
    case extract_values(data || [], Map.get(props, :chart_type)) do
      [] -> {0, 100}
      values -> Enum.min_max(values)
    end
  end

  defp padded_range({data_min, data_max}, props) do
    custom_min = Map.get(props, :min_value)
    custom_max = Map.get(props, :max_value)

    min_val = if is_number(custom_min), do: custom_min, else: data_min
    max_val = if is_number(custom_max), do: custom_max, else: data_max

    if min_val == max_val do
      {min_val - 0.001, max_val + 0.001}
    else
      padding = (max_val - min_val) * 0.05
      {bar_floor(Map.get(props, :chart_type), min_val, padding), max_val + padding}
    end
  end

  @bar_types [:bar, :clustered_bar, :stacked_bar, :histogram]

  defp bar_floor(type, min_val, _padding) when type in @bar_types and min_val >= 0, do: 0
  defp bar_floor(_type, min_val, padding), do: min_val - padding

  defp extract_values(data, chart_type) when chart_type in [:scatter, :bubble],
    do: Enum.flat_map(data, &point_height/1)

  defp extract_values([first | _] = data, :stacked_area) when is_list(first) do
    series = for values <- data, is_list(values), do: Enum.map(values, &stack_value/1)
    longest = series |> Enum.map(&length/1) |> Enum.max()

    totals =
      series
      |> Enum.map(&(&1 ++ List.duplicate(0, longest - length(&1))))
      |> Enum.zip_with(&Enum.sum/1)

    [0 | totals]
  end

  defp extract_values(data, _chart_type), do: extract_values(data)

  defp point_height({_x, y}) when is_number(y), do: [y]
  defp point_height({_x, y, _weight}) when is_number(y), do: [y]
  defp point_height([_x, y]) when is_number(y), do: [y]
  defp point_height([_x, y, _weight]) when is_number(y), do: [y]
  defp point_height(%{y: y}) when is_number(y), do: [y]
  defp point_height(points) when is_list(points), do: Enum.flat_map(points, &point_height/1)
  defp point_height(_other), do: []

  defp extract_values([first | _] = data) when is_list(first),
    do: Enum.flat_map(data, &series_values/1)

  defp extract_values(data) when is_list(data), do: Enum.flat_map(data, &item_values/1)
  defp extract_values(_), do: []

  defp series_values(series) when is_list(series), do: Enum.flat_map(series, &item_values/1)
  defp series_values(_other), do: []

  defp item_values(value) when is_number(value), do: [value]
  defp item_values({value, _weight}) when is_number(value), do: [value]
  defp item_values(values) when is_list(values), do: Enum.filter(values, &is_number/1)
  defp item_values(_other), do: []

  defp stack_value({value, _weight}), do: value
  defp stack_value(value) when is_number(value), do: value
  defp stack_value(nil), do: 0

  defp add_axes(strips, state, rect, bg, fg) do
    label_width = compute_y_axis_width(state)
    axis_col_width = label_width + 1

    if rect.width <= axis_col_width do
      strips
    else
      axed_strips(strips, state, rect, bg, fg, label_width, axis_col_width)
    end
  end

  defp tick_label(_state, _tick, _ticks, 0), do: ""

  defp tick_label(state, tick, ticks, _width) do
    span = state.max_value - state.min_value
    value = snap_zero(state.max_value - span * tick / ticks, span)
    format_axis_value(value, state._internal[:precision] || 3)
  end

  defp snap_zero(value, span) when abs(value) < abs(span) * 1.0e-9, do: 0.0
  defp snap_zero(value, _span), do: value

  defp axed_strips(strips, state, rect, bg, fg, label_width, axis_col_width) do
    tick_span = max(rect.height - 3, 1)

    y_axis_segments =
      for i <- 0..tick_span do
        label = tick_label(state, i, tick_span, label_width)

        Segment.new(IO.iodata_to_binary([String.pad_leading(label, label_width), "│"]), %{
          fg: fg,
          bg: bg
        })
      end

    strips_with_y =
      strips
      |> Enum.take(rect.height - 2)
      |> Enum.with_index()
      |> Enum.map(fn {strip, idx} ->
        y_seg =
          if idx < length(y_axis_segments) do
            Enum.at(y_axis_segments, idx)
          else
            Segment.new(String.duplicate(" ", axis_col_width), %{bg: bg})
          end

        Strip.new([y_seg | strip.segments])
      end)

    x_axis_content_width = max(1, rect.width - axis_col_width - 1)

    x_axis =
      IO.iodata_to_binary([
        String.duplicate(" ", label_width),
        "└",
        String.duplicate("─", x_axis_content_width)
      ])

    x_axis_strip =
      Strip.new([Segment.new(String.pad_trailing(x_axis, rect.width), %{fg: fg, bg: bg})])

    strips_with_y ++ [x_axis_strip]
  end

  defp compute_y_axis_width(%{orientation: :horizontal}), do: 0

  defp compute_y_axis_width(state) do
    min_label = format_axis_value(state.min_value, state._internal[:precision] || 3)
    max_label = format_axis_value(state.max_value, state._internal[:precision] || 3)
    max(String.length(min_label), String.length(max_label))
  end

  defp add_title(strips, title, _rect, bg, fg) do
    title_seg = Segment.new(title, %{fg: fg, bg: bg, bold: true})
    title_strip = Strip.new([title_seg])
    [title_strip | strips]
  end

  defp pad_strips(strips, target_height) do
    current_height = length(strips)

    if current_height < target_height do
      padding =
        for _ <- 1..(target_height - current_height) do
          Strip.new([Segment.new("", %{})])
        end

      strips ++ padding
    else
      Enum.take(strips, target_height)
    end
  end

  defp format_axis_value(val, precision) when is_float(val) do
    if abs(val) >= 1000 do
      "#{Float.round(val / 1000, 1)}k"
    else
      :erlang.float_to_binary(Float.round(val, precision), decimals: precision)
    end
  end

  defp format_axis_value(val, _precision), do: to_string(val)

  defp update_internal(state, updates) do
    %{state | _internal: Enum.into(updates, state._internal)}
  end
end
