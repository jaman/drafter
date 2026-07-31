defmodule Drafter.Widget.Chart do
  @moduledoc """
  Renders time-series and financial data as interactive charts with multiple styles.

  Supported chart types: `:line`, `:area`, `:braille_area`, `:bar`, `:clustered_bar`,
  `:stacked_bar`, `:range_bar`, `:scatter`, and `:candlestick`. Braille-dot rendering provides the
  highest resolution (two data points per column, four per row). Quadrant-block
  rendering provides 2×2 pixel resolution per cell (coarser but larger dots). Bar
  charts use half-block characters for 2× vertical resolution.

  Scatter data points accept `[x, y]` lists, `{x, y}` tuples, or weighted
  variants `[x, y, weight]` / `{x, y, weight}` where weight is a float
  between 0.0 and 1.0. Higher weights produce denser braille dot clusters
  and brighter colors, giving visual density feedback for clustered data.
  Candlestick candles accept `[open, high, low, close]` lists or maps with
  `:open`, `:high`, `:low`, `:close` keys.

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

  For `:range_bar`, data is a list of `[low, high]` pairs — one pair per bar:

      chart([[10, 40], [25, 65], [5, 55]], chart_type: :range_bar, height: 8)

  ## Bar Chart Types

    * `:bar` — classic single-row sparkline; one block-char per data point
    * `:clustered_bar` — multi-row grouped bars; each group shows one bar per
      series side by side with half-block vertical resolution
    * `:stacked_bar` — multi-row stacked bars; series accumulate from the
      baseline (supports negatives — positive series stack upward, negative
      series stack downward)
    * `:range_bar` — one bar per data point spanning a low→high range

  ## Keyboard Controls (when focused)

    * `←` / `→` — scroll the X-axis by 5 data points
    * `↑` / `↓` — pan the Y-axis up/down by 1 unit
    * `c` — re-anchor the Y-axis to the rightmost visible candle open price
    * Click and drag — pan both axes simultaneously

  ## Options

    * `:data` — numeric list; list of series for multi-series types; `[low, high]`
      pairs for `:range_bar`
    * `:chart_type` — `:line` (default), `:area`, `:braille_area`, `:bar`,
      `:clustered_bar`, `:stacked_bar`, `:range_bar`, `:scatter`, `:candlestick`

    * `:pixel_style` — pixel rendering style for line and scatter: `:braille` (default) or `:quadrant`
    * `:min_value` — explicit Y minimum; auto-detected when omitted
    * `:max_value` — explicit Y maximum; auto-detected when omitted
    * `:color` — `{r, g, b}` primary colour for single-series charts
    * `:colors` — list of `{r, g, b}` tuples; one per series for multi-series
      types; first entry overrides `:color` for single-series bar/scatter/area
    * `:show_axes` — draw axis lines and zero-line when range spans zero: `true` / `false`
    * `:show_labels` — draw axis tick labels: `true` / `false` (default)
    * `:title` — string displayed at the top of the chart
    * `:x_labels` — list of strings for X-axis tick labels
    * `:y_labels` — list of strings for Y-axis tick labels
    * `:orientation` — `:vertical` (default) or `:horizontal`; applies to all bar chart types
    * `:bar_labels` — list of strings labelling each bar or group; shown when `show_labels: true`
    * `:show_values` — show the numeric value beside each bar: `true` / `false` (default)
    * `:fill_opacity` — brightness of the area fill body relative to the series color,
      `0.0` (invisible) to `1.0` (same as edge). Default `0.6`.
    * `:animated` — animate new data points: `true` / `false` (default)
    * `:animation_speed` — milliseconds per animation frame (default `100`)
    * `:style` — map of style properties
    * `:classes` — list of theme class atoms
    * `:renderer` — rendering backend for this chart: `:text` (ASCII/block), `:braille`
      (anti-aliased braille), `:pixel` / `:auto` (best terminal graphics available —
      kitty/iTerm2/sixel image, falling back to braille), or `:iterm2` / `:kitty` /
      `:sixel` to force a protocol. Overrides the runtime `mode:` config, but the
      `DRAFTER_MODE` env var still forces over it. When unset, the global mode applies:
      `DRAFTER_MODE`, then the `mode:` run option (`Drafter.run(App, mode: :pixel)` /
      `Drafter.render_mode/1`), then `:text`.
    * `:image_throttle` — for `:pixel` charts, the minimum gap between image regenerations,
      in Drafter's timing units: `{n, :fps}`, `{n, :ms}`, `{n, :tick}` (every `n` render
      frames — the default, frame-aligned so it can't beat against the render clock), or a
      bare integer (milliseconds). Default `{2, :tick}`. Lower means smoother animation but
      more terminal load.
    * `:image_scale` — for `:pixel` charts, pixels generated per terminal cell column
      (rows use `2×`); default `4`. Higher is sharper but produces larger images.

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
    handles: [:keyboard, :mouse_up, :drag],
    scroll: [direction: :horizontal, step: 5]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  alias Drafter.Widget.Chart.{
    Area,
    Bar,
    BrailleArea,
    Bubble,
    Candlestick,
    Heatmap,
    Histogram,
    Pixel
  }

  alias Drafter.Widget.Chart.{Line, MultiSeries, Scatter, Step}

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

  defdelegate render_multi_series(data_series, width, height, opts), to: MultiSeries, as: :render
  defdelegate render_tall_bar_chart(data, height, opts), to: Bar

  @impl Drafter.Widget
  def mount(props) do
    data = Map.get(props, :data, [])
    max_data_points = Map.get(props, :max_data_points)

    {min_val, max_val} = calculate_data_range(data, props)

    live_candle = init_live_candle(data)
    data_hash = :erlang.phash2(data)
    data_tuple = data_to_tuple(data)

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
        render_timestamp: Map.get(props, :_render_timestamp, 0),
        animation_offset: 0,
        live_candle: live_candle,
        scroll_offset: 0,
        drag_last_x: nil,
        drag_last_y: nil,
        y_offset: 0,
        data_tuple: data_tuple,
        data_hash: data_hash,
        dragging_scrollbar: false,
        smooth: Map.get(props, :smooth, false),
        line_thickness: Map.get(props, :line_thickness, 1),
        connect_lines: Map.get(props, :connect_lines, false),
        raw_data: Map.get(props, :raw_data, false),
        renderer: Map.get(props, :renderer),
        image_scale: Map.get(props, :image_scale, 4)
      }
    }
  end

  @impl Drafter.Widget
  def handle_mouse_up(_x, _y, state) do
    {:ok, update_internal(state, dragging_scrollbar: true, drag_last_x: nil)}
  end

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
  def handle_key(_key, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_drag(x, y, %{_internal: %{drag_last_x: nil}} = state) do
    {:ok, update_internal(state, drag_last_x: x, drag_last_y: y)}
  end

  def handle_drag(x, y, state) do
    dx = (state._internal.drag_last_x || x) - x
    dy = y - (state._internal.drag_last_y || y)
    new_x_offset = max(0, (state._internal.scroll_offset || 0) + dx)
    new_y_offset = (state._internal.y_offset || 0) + dy

    {:ok,
     update_internal(state,
       scroll_offset: new_x_offset,
       drag_last_x: x,
       y_offset: new_y_offset,
       drag_last_y: y
     )}
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  def component_tag, do: :chart

  def from_component_opts(data, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80, height: 20})
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

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
      line_thickness: Keyword.get(opts, :line_thickness, 1),
      connect_lines: Keyword.get(opts, :connect_lines, false),
      raw_data: Keyword.get(opts, :raw_data, false),
      renderer: Keyword.get(opts, :renderer),
      image_scale: Keyword.get(opts, :image_scale, 4),
      _render_timestamp: System.monotonic_time(:millisecond)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    renderer = Map.get(mount_props, :renderer)
    chart_type = Map.get(mount_props, :chart_type, :line)

    if Pixel.mode(renderer, chart_type) == :text do
      Map.put(mount_props, :_render_timestamp, System.monotonic_time(:millisecond))
    else
      mount_props
    end
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    data = Drafter.RingBuffer.to_list(buffer)

    if data != [] do
      %{state | data: data}
    else
      state
    end
  end

  @impl Drafter.Widget
  def render(_state, %{width: width}) when width <= 0, do: []

  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case Pixel.mode(renderer(state), state.chart_type) do
      :pixel -> blank_strips(rect)
      :braille -> braille_render(state, rect)
      :text -> render_text(state, rect)
    end
  end

  defp blank_strips(rect) do
    blank = Strip.new([Segment.new(String.duplicate(" ", max(1, rect.width)))])
    List.duplicate(blank, max(1, rect.height))
  end

  @doc false
  def image(state, rect, id) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    cols = max(1, rect.width)
    rows = max(1, rect.height)

    case Pixel.mode(renderer(state), state.chart_type) do
      :pixel ->
        case Pixel.image(pixel_spec(state), Pixel.protocol(renderer(state)), {cols, rows}, id) do
          nil -> nil
          {paint, clear} -> {paint, clear, %{dx: 0, dy: 0, cols: cols, rows: rows}}
        end

      _ ->
        nil
    end
  end

  defp render_text(state, rect) do
    computed =
      Computed.for_widget(:chart, state,
        classes: state.classes,
        style: state.style,
        app_module: state.app_module
      )

    bg = computed[:background] || {20, 20, 30}
    fg = state.color || computed[:color] || {100, 200, 255}

    axis_label_width = if state.show_axes, do: compute_y_axis_width(state), else: 0
    chart_height = if state.show_axes, do: max(1, rect.height - 2), else: rect.height

    chart_width =
      if state.show_axes, do: max(1, rect.width - axis_label_width - 1), else: rect.width

    animation_offset =
      if state.animated do
        div(state._internal.render_timestamp, state.animation_speed)
      else
        0
      end

    horizontal? = state.orientation == :horizontal

    {strips, effective_state} =
      dispatch_chart(state, chart_width, chart_height, bg, fg, animation_offset, horizontal?)

    effective_state
    |> then(&apply_axes(strips, &1, rect, bg, fg))
    |> apply_title(state, rect, bg, fg)
    |> pad_strips(rect.height)
  end

  defp renderer(state), do: Map.get(state._internal, :renderer)

  defp braille_render(state, rect) do
    case Pixel.braille_strips(pixel_spec(state), {max(1, rect.width), max(1, rect.height)}) do
      nil -> render_text(state, rect)
      strips -> strips
    end
  end

  defp pixel_spec(state) do
    %{
      type: state.chart_type,
      data: state.data,
      color: pixel_color(state),
      colors: state.colors,
      smooth: Map.get(state._internal, :smooth, true),
      fill_opacity: state.fill_opacity,
      min: state.min_value,
      max: state.max_value,
      scale: Map.get(state._internal, :image_scale, 4)
    }
  end

  defp pixel_color(state) do
    base = state.color || List.first(state.colors) || {120, 200, 255}

    case base do
      {r, g, b} -> {r, g, b, 255}
      {r, g, b, a} -> {r, g, b, a}
      _ -> {120, 200, 255, 255}
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)
    new_hash = :erlang.phash2(new_data)
    data_changed = new_hash != state._internal.data_hash

    {min_val, max_val} =
      if data_changed do
        calculate_data_range(new_data, props)
      else
        custom_min = Map.get(props, :min_value)
        custom_max = Map.get(props, :max_value)

        if is_number(custom_min) or is_number(custom_max) do
          calculate_data_range(new_data, props)
        else
          {state.min_value, state.max_value}
        end
      end

    live_candle = state._internal.live_candle || init_live_candle(new_data)

    {new_tuple, new_hash} =
      if data_changed do
        {data_to_tuple(new_data), new_hash}
      else
        {state._internal.data_tuple, state._internal.data_hash}
      end

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
            render_timestamp:
              Map.get(props, :_render_timestamp, state._internal.render_timestamp),
            live_candle: live_candle,
            data_tuple: new_tuple,
            data_hash: new_hash,
            renderer: Map.get(props, :renderer, state._internal[:renderer]),
            smooth: Map.get(props, :smooth, state._internal[:smooth]),
            line_thickness: Map.get(props, :line_thickness, state._internal[:line_thickness]),
            connect_lines: Map.get(props, :connect_lines, state._internal[:connect_lines]),
            raw_data: Map.get(props, :raw_data, state._internal[:raw_data]),
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

  defp dispatch_chart(state, w, h, bg, fg, anim, true) do
    strips =
      case state.chart_type do
        :bar -> Bar.render_bar_chart_h(state, w, h, bg, fg)
        :clustered_bar -> Bar.render_clustered_bar_h(state, w, h, bg)
        :stacked_bar -> Bar.render_stacked_bar_h(state, w, h, bg)
        :range_bar -> Bar.render_range_bar_h(state, w, h, bg, fg)
        _ -> elem(dispatch_chart(state, w, h, bg, fg, anim, false), 0)
      end

    {strips, state}
  end

  defp dispatch_chart(state, w, h, bg, fg, anim, false) do
    dispatch_chart_v(state.chart_type, state, w, h, bg, fg, anim)
  end

  defp dispatch_chart_v(:braille_area, state, w, h, bg, _fg, _anim),
    do: BrailleArea.render(state, w, h, bg)

  defp dispatch_chart_v(:bar, s, w, h, bg, fg, _a),
    do: {Bar.render_bar_chart_v(s, w, h, bg, fg), s}

  defp dispatch_chart_v(:clustered_bar, s, w, h, bg, _fg, _a),
    do: {Bar.render_clustered_bar(s, w, h, bg), s}

  defp dispatch_chart_v(:stacked_bar, s, w, h, bg, _fg, _a),
    do: {Bar.render_stacked_bar(s, w, h, bg), s}

  defp dispatch_chart_v(:range_bar, s, w, h, bg, fg, _a),
    do: {Bar.render_range_bar(s, w, h, bg, fg), s}

  defp dispatch_chart_v(:candlestick, s, w, h, bg, fg, _a),
    do: {Candlestick.render(s, w, h, bg, fg), s}

  defp dispatch_chart_v(:area, s, w, h, bg, fg, a), do: {Area.render(s, w, h, bg, fg, a), s}
  defp dispatch_chart_v(:scatter, s, w, h, bg, fg, _a), do: {Scatter.render(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:step, s, w, h, bg, fg, a), do: {Step.render(s, w, h, bg, fg, a), s}

  defp dispatch_chart_v(:histogram, s, w, h, bg, fg, _a),
    do: {Histogram.render(s, w, h, bg, fg), s}

  defp dispatch_chart_v(:heatmap, s, w, h, bg, fg, _a), do: {Heatmap.render(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:bubble, s, w, h, bg, fg, _a), do: {Bubble.render(s, w, h, bg, fg), s}

  defp dispatch_chart_v(:braille, s, w, h, bg, fg, a),
    do: {Line.render_braille(s, w, h, bg, fg, a), s}

  defp dispatch_chart_v(_type, s, w, h, bg, fg, a), do: {Line.render(s, w, h, bg, fg, a), s}

  defp scroll_left(state),
    do:
      {:ok,
       update_internal(state, scroll_offset: max(0, (state._internal.scroll_offset || 0) - 5))}

  defp scroll_right(state),
    do: {:ok, update_internal(state, scroll_offset: (state._internal.scroll_offset || 0) + 5)}

  defp init_live_candle(data) when is_list(data) and data != [] do
    last_candle = List.last(data)

    close =
      case last_candle do
        [_, _, _, c | _] -> c
        _ -> 1.0850
      end

    %{
      open: close,
      high: close,
      low: close,
      close: close,
      price_prints: 0,
      prints_until_complete: 5 + :rand.uniform(10)
    }
  end

  defp init_live_candle(_) do
    %{
      open: 1.0850,
      high: 1.0850,
      low: 1.0850,
      close: 1.0850,
      price_prints: 0,
      prints_until_complete: 5 + :rand.uniform(10)
    }
  end

  defp calculate_data_range(data, props) do
    custom_min = Map.get(props, :min_value)
    custom_max = Map.get(props, :max_value)
    live_candle = Map.get(props, :_live_candle)

    data = data || []
    data_values = extract_values(data)

    live_values =
      if live_candle do
        [live_candle.high, live_candle.low]
      else
        []
      end

    all_values = data_values ++ live_values

    {data_min, data_max} =
      if all_values != [] do
        {Enum.min(all_values), Enum.max(all_values)}
      else
        {0, 100}
      end

    min_val = if is_number(custom_min), do: custom_min, else: data_min
    max_val = if is_number(custom_max), do: custom_max, else: data_max

    if min_val == max_val do
      {min_val - 0.001, max_val + 0.001}
    else
      padding = (max_val - min_val) * 0.05
      {min_val - padding, max_val + padding}
    end
  end

  defp extract_values([first | _] = data) when is_number(first), do: data

  defp extract_values([{val, _weight} | _] = data) when is_number(val) do
    Enum.map(data, fn {v, _w} -> v end)
  end

  defp extract_values([first | _] = data) when is_list(first) do
    case first do
      [{v, _w} | _] when is_number(v) ->
        data |> Enum.flat_map(fn series -> Enum.map(series, &extract_weighted_value/1) end)

      [nested | _] when is_number(nested) ->
        Enum.flat_map(data, & &1)

      [nested | _] when is_list(nested) ->
        data |> Enum.flat_map(& &1) |> Enum.flat_map(& &1)

      _ ->
        []
    end
  end

  defp extract_values(_), do: []

  defp extract_weighted_value({v, _w}), do: v
  defp extract_weighted_value(v) when is_number(v), do: v

  defp data_to_tuple(data) when is_list(data), do: List.to_tuple(data)
  defp data_to_tuple(data), do: data

  defp add_axes(strips, state, rect, bg, fg) do
    label_width = compute_y_axis_width(state)
    axis_col_width = label_width + 1

    if rect.width <= axis_col_width do
      strips
    else
      axed_strips(strips, state, rect, bg, fg, label_width, axis_col_width)
    end
  end

  defp axed_strips(strips, state, rect, bg, fg, label_width, axis_col_width) do
    tick_span = max(rect.height - 3, 1)

    y_axis_segments =
      for i <- 0..tick_span do
        y_val = state.max_value - (state.max_value - state.min_value) * i / tick_span
        label = format_axis_value(y_val, state._internal[:precision] || 3)

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
