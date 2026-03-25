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
    * `:marker` — render density: `:braille` (default), `:half_block`, `:block`, `:dot`
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
    * `:animated` — animate new data points: `true` / `false` (default)
    * `:animation_speed` — milliseconds per animation frame (default `100`)
    * `:style` — map of style properties
    * `:classes` — list of theme class atoms

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

  import Bitwise

  alias Drafter.{CharacterSet, Visualization}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @type chart_type ::
          :line
          | :bar
          | :clustered_bar
          | :stacked_bar
          | :range_bar
          | :candlestick
          | :area
          | :scatter
          | :braille
          | :braille_area

  @default_series_colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 180, 100},
    {180, 100, 255}
  ]
  @type marker :: :braille | :half_block | :block | :dot

  @quadrant_chars %{
    0 => " ",
    1 => "▘",
    2 => "▝",
    3 => "▀",
    4 => "▖",
    5 => "▌",
    6 => "▚",
    7 => "▛",
    8 => "▗",
    9 => "▞",
    10 => "▐",
    11 => "▜",
    12 => "▄",
    13 => "▙",
    14 => "▟",
    15 => "█"
  }

  defstruct [
    :data,
    :chart_type,
    :marker,
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
    :orientation,
    :bar_labels,
    :show_values,
    bar_gap: 0,
    show_baseline: false,
    zero_center: :symmetric,
    focused: false,
    _internal: %{}
  ]

  @braille_base 0x2800

  @braille_dot_offsets %{
    {0, 0} => 0x01,
    {0, 1} => 0x02,
    {0, 2} => 0x04,
    {0, 3} => 0x40,
    {1, 0} => 0x08,
    {1, 1} => 0x10,
    {1, 2} => 0x20,
    {1, 3} => 0x80
  }

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
      marker: Map.get(props, :marker, :braille),
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
      orientation: Map.get(props, :orientation, :vertical),
      bar_labels: Map.get(props, :bar_labels, []),
      show_values: Map.get(props, :show_values, false),
      show_baseline: Map.get(props, :show_baseline, false),
      zero_center: Map.get(props, :zero_center, :symmetric),
      _internal: %{
        render_timestamp: Map.get(props, :_render_timestamp, 0),
        animation_offset: 0,
        live_candle: live_candle,
        scroll_offset: 0,
        drag_last_x: nil,
        drag_last_y: nil,
        y_offset: 0,
        data_tuple: data_tuple,
        data_hash: data_hash,
        dragging_scrollbar: false
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
  def handle_key(:up, state), do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) + 1)}
  def handle_key(:ArrowUp, state), do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) + 1)}
  def handle_key(:down, state), do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) - 1)}
  def handle_key(:ArrowDown, state), do: {:ok, update_internal(state, y_offset: (state._internal.y_offset || 0) - 1)}
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
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

    classes =
      Enum.map(raw_classes, fn
        c when is_binary(c) -> String.to_atom(c)
        c when is_atom(c) -> c
      end)

    all_data = if is_list(data), do: data, else: Keyword.get(opts, :data, [])

    %{
      data: all_data,
      chart_type: Keyword.get(opts, :chart_type, :line),
      marker: Keyword.get(opts, :marker, :braille),
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
      orientation: Keyword.get(opts, :orientation, :vertical),
      bar_labels: Keyword.get(opts, :bar_labels, []),
      show_values: Keyword.get(opts, :show_values, false),
      show_baseline: Keyword.get(opts, :show_baseline, false),
      zero_center: Keyword.get(opts, :zero_center, :symmetric),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__),
      _render_timestamp: System.monotonic_time(:millisecond)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    Map.put(mount_props, :_render_timestamp, System.monotonic_time(:millisecond))
  end

  defp scroll_left(state),
    do: {:ok, update_internal(state, scroll_offset: max(0, (state._internal.scroll_offset || 0) - 5))}

  defp scroll_right(state), do: {:ok, update_internal(state, scroll_offset: (state._internal.scroll_offset || 0) + 5)}

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

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    computed =
      Computed.for_widget(:chart, state,
        classes: state.classes,
        style: state.style,
        app_module: state.app_module
      )

    bg = computed[:background] || {20, 20, 30}
    fg = state.color || computed[:color] || {100, 200, 255}

    chart_height = if state.show_axes, do: max(1, rect.height - 2), else: rect.height
    chart_width = if state.show_axes, do: max(1, rect.width - 6), else: rect.width

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

  defp apply_axes(strips, %{show_axes: true} = state, rect, bg, fg), do: add_axes(strips, state, rect, bg, fg)
  defp apply_axes(strips, _state, _rect, _bg, _fg), do: strips

  defp apply_title(strips, %{title: title}, rect, bg, fg) when is_binary(title) and title != "",
    do: add_title(strips, title, rect, bg, fg)

  defp apply_title(strips, _state, _rect, _bg, _fg), do: strips

  defp dispatch_chart(state, w, h, bg, fg, anim, true) do
    strips =
      case state.chart_type do
        :bar -> render_bar_chart_h(state, w, h, bg, fg)
        :clustered_bar -> render_clustered_bar_h(state, w, h, bg)
        :stacked_bar -> render_stacked_bar_h(state, w, h, bg)
        :range_bar -> render_range_bar_h(state, w, h, bg, fg)
        _ -> elem(dispatch_chart(state, w, h, bg, fg, anim, false), 0)
      end

    {strips, state}
  end

  defp dispatch_chart(state, w, h, bg, fg, anim, false) do
    dispatch_chart_v(state.chart_type, state, w, h, bg, fg, anim)
  end

  defp dispatch_chart_v(:braille_area, state, w, h, bg, _fg, _anim), do: render_braille_area(state, w, h, bg)

  defp dispatch_chart_v(:bar, s, w, h, bg, fg, _a), do: {render_bar_chart_v(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:clustered_bar, s, w, h, bg, _fg, _a), do: {render_clustered_bar(s, w, h, bg), s}
  defp dispatch_chart_v(:stacked_bar, s, w, h, bg, _fg, _a), do: {render_stacked_bar(s, w, h, bg), s}
  defp dispatch_chart_v(:range_bar, s, w, h, bg, fg, _a), do: {render_range_bar(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:candlestick, s, w, h, bg, fg, _a), do: {render_candlestick_chart(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:area, s, w, h, bg, fg, a), do: {render_area_chart(s, w, h, bg, fg, a), s}
  defp dispatch_chart_v(:scatter, s, w, h, bg, fg, _a), do: {render_scatter_chart(s, w, h, bg, fg), s}
  defp dispatch_chart_v(:braille, s, w, h, bg, fg, a), do: {render_braille_chart(s, w, h, bg, fg, a), s}
  defp dispatch_chart_v(_type, s, w, h, bg, fg, a), do: {render_line_chart(s, w, h, bg, fg, a), s}

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
        marker: Map.get(props, :marker, state.marker),
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
        _internal:
          Map.merge(state._internal, %{
            render_timestamp: Map.get(props, :_render_timestamp, state._internal.render_timestamp),
            live_candle: live_candle,
            data_tuple: new_tuple,
            data_hash: new_hash
          })
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

  defp render_line_chart(state, width, height, bg, fg, animation_offset) do
    data = state.data
    data_src = state._internal.data_tuple || data

    cond do
      tuple_size_or_length(data_src) < 2 ->
        empty_strips(height, bg)

      is_list(data) and is_list(hd(data)) ->
        render_line_multi_series(state, data, width, height, bg)

      true ->
        render_line_single_series(state, data_src, width, height, bg, fg, animation_offset)
    end
  end

  defp render_line_multi_series(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2

    scrolled_series =
      Enum.map(data, fn series ->
        {_start, slice} = Drafter.ScrollMath.end_anchored_slice(series, scroll_offset, viewport_width)
        slice
      end)

    render_multi_series(scrolled_series, width, height,
      bg: bg,
      colors: colors,
      min: state.min_value,
      max: state.max_value
    )
  end

  defp render_line_single_series(state, data_src, width, height, bg, fg, animation_offset) do
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    {_start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, viewport_width)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    normalized = normalize_data(viewport_data, state.min_value, range, pixel_height)
    shifted = apply_animation_shift(normalized, animation_offset)
    points = Enum.with_index(shifted) |> Enum.map(fn {y, x} -> {x, y} end)
    lines = bresenham_lines(points)

    case state.pixel_style do
      :quadrant -> render_quadrant_pixels(lines, width, height, bg, fg)
      _ -> render_braille_pixels(lines, width, height, bg, fg)
    end
  end

  defp apply_animation_shift(normalized, animation_offset) when animation_offset > 0 do
    shift = rem(animation_offset, length(normalized))
    Enum.drop(normalized, shift) ++ Enum.take(normalized, shift)
  end

  defp apply_animation_shift(normalized, _animation_offset), do: normalized

  defp render_bar_chart_v(state, width, height, bg, fg) do
    data_src = state._internal.data_tuple || state.data

    if tuple_size_or_length(data_src) == 0 do
      empty_strips(height, bg)
    else
      render_bar_chart_v_data(state, data_src, width, height, bg, fg)
    end
  end

  defp render_bar_chart_v_data(state, data_src, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    levels = CharacterSet.sparkline_levels_v()
    label_row? = state.show_labels and state.bar_labels != []
    bar_height = if label_row?, do: max(1, height - 1), else: height
    {start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, width)
    viewport_labels = Enum.slice(state.bar_labels, start_index, width)
    bars = build_v_bars(state, viewport_data, viewport_labels, levels)
    bar_strips = build_v_bar_strips(bars, bar_height, width, bg, fg)
    maybe_append_label_row(bar_strips, bars, label_row?, width, bg, fg)
  end

  defp build_v_bars(state, viewport_data, viewport_labels, levels) do
    viewport_data
    |> Enum.with_index()
    |> Enum.map(fn {value, i} ->
      normalized = Visualization.normalize(value, state.min_value, state.max_value)
      idx = Visualization.level_index(normalized, levels)
      char = Enum.at(levels, idx)
      value_str = if state.show_values, do: Visualization.format_number(value), else: nil
      label = if state.show_labels, do: Enum.at(viewport_labels, i, ""), else: nil
      {char, value_str, label}
    end)
  end

  defp build_v_bar_strips(bars, bar_height, width, bg, fg) do
    for _row <- 1..bar_height do
      segs = Enum.map(bars, fn {char, _val, _lbl} -> Segment.new(char, %{fg: fg, bg: bg}) end)
      padding_count = max(0, width - length(segs))
      Strip.new(segs ++ List.duplicate(Segment.new(" ", %{bg: bg}), padding_count))
    end
  end

  defp maybe_append_label_row(bar_strips, bars, true, width, bg, fg) do
    label_segs =
      Enum.map(bars, fn {_, _, lbl} ->
        Segment.new(String.slice(lbl || "", 0, 1), %{fg: fg, bg: bg})
      end)

    padding_count = max(0, width - length(label_segs))
    label_strip = Strip.new(label_segs ++ List.duplicate(Segment.new(" ", %{bg: bg}), padding_count))
    bar_strips ++ [label_strip]
  end

  defp maybe_append_label_row(bar_strips, _bars, false, _width, _bg, _fg), do: bar_strips

  defp render_bar_chart_h(state, width, height, bg, fg) do
    data_src = state._internal.data_tuple || state.data

    if tuple_size_or_length(data_src) == 0 do
      empty_strips(height, bg)
    else
      render_bar_chart_h_data(state, data_src, width, height, bg, fg)
    end
  end

  defp render_bar_chart_h_data(state, data_src, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    {start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, height)
    viewport_labels = Enum.slice(state.bar_labels, start_index, height)
    label_width = h_label_width(state, viewport_labels)
    value_width = h_value_width(state, viewport_data)
    bar_width = max(1, width - label_width - value_width)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1
    full_char = CharacterSet.fill(:full)

    ctx = %{
      state: state,
      levels: levels,
      level_count: level_count,
      full_char: full_char,
      bar_width: bar_width,
      label_width: label_width,
      value_width: value_width,
      viewport_labels: viewport_labels,
      fg: fg,
      bg: bg
    }

    viewport_data
    |> Enum.with_index()
    |> Enum.map(fn {value, i} -> build_h_bar_strip(value, i, ctx) end)
  end

  defp h_label_width(state, viewport_labels) do
    if state.show_labels and state.bar_labels != [] do
      viewport_labels |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end) |> max(1)
    else
      0
    end
  end

  defp h_value_width(state, viewport_data) do
    if state.show_values do
      viewport_data
      |> Enum.map(fn v -> String.length(Visualization.format_number(v)) end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)
    else
      0
    end
  end

  defp build_h_bar_strip(value, i, %{state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, fg: fg, bg: bg} = _ctx) do
    normalized = Visualization.normalize(value, state.min_value, state.max_value)
    total_steps = round(normalized * bar_width * level_count)
    full_blocks = div(total_steps, level_count)
    partial_idx = rem(total_steps, level_count)
    full_str = Visualization.safe_duplicate(full_char, full_blocks)
    partial_str = if partial_idx > 0 and full_blocks < bar_width, do: Enum.at(levels, partial_idx, ""), else: ""
    bar_used = full_blocks + if(partial_idx > 0 and full_blocks < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", bar_width - bar_used)
    label_style = %{fg: fg, bg: bg}

    segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, i, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, label_style)]
      else
        []
      end

    segs = segs ++ [Segment.new(full_str <> partial_str <> padding, %{fg: fg, bg: bg})]

    segs =
      if value_width > 0 do
        val_str = " " <> Visualization.format_number(value)
        segs ++ [Segment.new(String.pad_trailing(val_str, value_width), label_style)]
      else
        segs
      end

    Strip.new(segs)
  end

  defp valid_candle?(%{open: _, high: _, low: _, close: _}), do: true
  defp valid_candle?(c) when is_list(c), do: length(c) >= 4
  defp valid_candle?(_), do: false

  defp render_candlestick_chart(state, width, height, bg, _fg) do
    candles = state.data || []

    cond do
      candles == [] -> empty_strips(height, bg)
      not valid_candle?(hd(candles)) -> empty_strips(height, bg)
      true -> render_candlestick_filtered(state, candles, width, height, bg)
    end
  end

  defp render_candlestick_filtered(state, candles, width, height, bg) do
    filtered_candles = Enum.filter(candles, &valid_candle?/1)
    scroll_offset = state._internal.scroll_offset || 0
    y_offset = state._internal.y_offset || 0
    label_width = 11
    viewport_width = max(1, width - label_width)
    {start_index, display_candles} =
      Drafter.ScrollMath.end_anchored_slice(filtered_candles, scroll_offset, viewport_width)

    if display_candles == [] do
      empty_strips(height, bg)
    else
      render_candlestick_display(display_candles, start_index, height, y_offset, bg)
    end
  end

  defp render_candlestick_display(display_candles, start_index, height, y_offset, bg) do
    rightmost = List.last(display_candles)
    {anchor_open, _, _, _} = extract_ohlc(rightmost)
    half_range = height / 2 * 0.0001
    center = anchor_open + y_offset * 0.0001
    min_val = Float.round(center - half_range, 4)
    max_val = Float.round(center + half_range, 4)
    bull_color = {52, 208, 88}
    bear_color = {234, 74, 90}
    label_color = {140, 140, 150}
    time_label_color = {120, 120, 130}

    chart_strips =
      render_candlestick_body(display_candles, height - 1, min_val, max_val, bull_color, bear_color, label_color, bg)
    time_strip = render_time_axis(display_candles, start_index, label_color, time_label_color, bg)
    chart_strips ++ [time_strip]
  end

  defp render_candlestick_body(
         candles,
         height,
         min_val,
         max_val,
         bull_color,
         bear_color,
         label_color,
         bg
       ) do
    range = max_val - min_val
    price_per_row = range / height
    label_width = 11
    empty_seg = Segment.new(" ", %{fg: bg, bg: bg})

    precomputed =
      Enum.map(candles, fn candle ->
        {open, high, low, close} = extract_ohlc(candle)
        is_bull = close >= open
        color = if is_bull, do: bull_color, else: bear_color
        body_top = max(open, close)
        body_bottom = min(open, close)

        high_row = trunc((max_val - high) / price_per_row)
        low_row = trunc((max_val - low) / price_per_row)
        body_top_row = trunc((max_val - body_top) / price_per_row)
        body_bottom_row = trunc((max_val - body_bottom) / price_per_row)

        body_span = body_bottom_row - body_top_row
        is_doji = abs(open - close) < price_per_row * 0.5
        has_upper_wick = high_row < body_top_row
        has_lower_wick = low_row > body_bottom_row
        is_spinning_top = body_span <= 1 and has_upper_wick and has_lower_wick

        body_char =
          cond do
            is_doji -> CharacterSet.box(:h_dashed)
            is_spinning_top -> CharacterSet.box(:cross)
            true -> CharacterSet.fill(:full)
          end

        {color, high_row, low_row, body_top_row, body_bottom_row, body_char}
      end)

    for row <- 0..(height - 1) do
      row_mid_price = max_val - (row + 0.5) * price_per_row
      label_text = format_price_label(row_mid_price)

      label_seg =
        Segment.new(String.pad_trailing(label_text, label_width), %{fg: label_color, bg: bg})

      candle_segments =
        Enum.map(precomputed, fn precomputed_candle ->
          candle_segment_for_row(row, precomputed_candle, empty_seg, bg)
        end)

      Strip.new([label_seg | candle_segments])
    end
  end

  defp candle_segment_for_row(row, {color, high_row, low_row, body_top_row, body_bottom_row, body_char}, empty_seg, bg) do
    cond do
      row >= body_top_row and row <= body_bottom_row -> Segment.new(body_char, %{fg: color, bg: bg})
      row >= high_row and row <= low_row -> Segment.new("│", %{fg: color, bg: bg})
      true -> empty_seg
    end
  end

  defp render_time_axis(display_candles, start_index, label_color, time_color, bg) do
    label_width = 11
    label_seg = Segment.new(String.duplicate(" ", label_width), %{fg: label_color, bg: bg})

    num_candles = length(display_candles)
    interval = max(1, div(num_candles, 10))

    time_markers =
      for i <- 0..(num_candles - 1) do
        candle_index = start_index + i

        if rem(i, interval) == 0 do
          marker_str = Integer.to_string(candle_index)
          String.pad_leading(marker_str, String.length(marker_str))
        else
          " "
        end
      end

    time_segs =
      Enum.map(time_markers, fn char ->
        Segment.new(char, %{fg: time_color, bg: bg})
      end)

    Strip.new([label_seg | time_segs])
  end

  defp extract_ohlc(%{open: o, high: h, low: l, close: c}), do: {o, h, l, c}
  defp extract_ohlc([o, h, l, c | _]), do: {o, h, l, c}

  defp format_price_label(price) do
    cond do
      price >= 1_000_000 ->
        "#{Float.round(price / 1_000_000, 1)}M"

      price >= 100 ->
        Float.round(price, 0) |> trunc() |> Integer.to_string()

      price >= 1 ->
        Float.round(price, 4) |> to_string()

      true ->
        Float.round(price, 5) |> to_string()
    end
  end

  @area_default_colors [
    {100, 200, 255},
    {255, 130, 80},
    {80, 255, 150},
    {255, 100, 180},
    {200, 180, 60},
    {180, 100, 255}
  ]

  defp render_area_chart(state, width, height, bg, fg, animation_offset) do
    data = state.data
    data_src = state._internal.data_tuple || data

    cond do
      tuple_size_or_length(data_src) < 2 ->
        empty_strips(height, bg)

      is_list(data) and is_list(hd(data)) ->
        render_area_multi_series(state, data, width, height, bg)

      true ->
        render_area_single_series(state, data_src, width, height, bg, fg, animation_offset)
    end
  end

  defp render_area_multi_series(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @area_default_colors
    render_multi_series(data, width, height, bg: bg, colors: colors, min: state.min_value, max: state.max_value)
  end

  defp render_area_single_series(state, data_src, width, height, bg, fg, animation_offset) do
    range = state.max_value - state.min_value
    pixel_height = height * 4
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    {_start_index, viewport_data} = Drafter.ScrollMath.end_anchored_slice(data_src, scroll_offset, viewport_width)
    normalized = normalize_data(viewport_data, state.min_value, range, pixel_height)
    shifted = apply_animation_shift(normalized, animation_offset)

    pixels =
      shifted
      |> Enum.with_index()
      |> Enum.flat_map(fn {y, x} -> area_fill_pixels(x, y, pixel_height, state.area_fill) end)

    render_braille_pixels(pixels, width, height, bg, fg)
  end

  defp area_fill_pixels(x, y, pixel_height, :inverted) do
    flipped = pixel_height - 1 - y
    for yi <- flipped..(pixel_height - 1), do: {x, yi}
  end

  defp area_fill_pixels(x, y, _pixel_height, _fill) do
    for yi <- 0..y, do: {x, yi}
  end

  defp render_scatter_chart(state, width, height, bg, fg) do
    data = state.data

    cond do
      data == [] ->
        empty_strips(height, bg)

      is_list(hd(data)) and hd(data) != [] and is_list(hd(hd(data))) ->
        colors = if state.colors != [], do: state.colors, else: @default_series_colors
        scroll = state._internal.scroll_offset || 0
        render_multi_series_scatter(data, width, height, bg, colors, state.min_value, state.max_value, scroll)

      true ->
        render_scatter_single_series(state, data, width, height, bg, fg)
    end
  end

  defp render_scatter_single_series(state, data, width, height, bg, fg) do
    points = normalize_scatter_points(data)
    range = state.max_value - state.min_value
    pixel_height = height * 4
    scroll_offset = state._internal.scroll_offset || 0
    viewport_width = width * 2
    max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
    end_x = max_x - scroll_offset
    start_x = max(0, end_x - viewport_width)

    has_weights = Enum.any?(points, fn [_, _, w] -> w != 1.0 end)

    if has_weights do
      colored_pixels =
        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.flat_map(fn [x, y, w] ->
          py = round((y - state.min_value) / range * pixel_height)
          expand_weighted_point(x - start_x, pixel_height - py - 1, w, weight_color(fg, bg, w))
        end)

      render_braille_pixels_colored(colored_pixels, width, height, bg)
    else
      pixels =
        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.map(fn [x, y, _w] ->
          pixel_y = round((y - state.min_value) / range * pixel_height)
          {x - start_x, pixel_height - pixel_y - 1}
        end)

      case state.pixel_style do
        :quadrant -> render_quadrant_pixels(pixels, width, height, bg, fg)
        _ -> render_braille_pixels(pixels, width, height, bg, fg)
      end
    end
  end

  defp render_multi_series_scatter(
         data,
         width,
         height,
         bg,
         colors,
         min_val,
         max_val,
         scroll_offset
       ) do
    range = max_val - min_val
    pixel_height = height * 4
    viewport_width = width * 2

    all_pixels =
      data
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, idx} ->
        color = Enum.at(colors, idx, hd(colors))
        points = normalize_scatter_points(series)
        max_x = Enum.map(points, fn [x | _] -> x end) |> Enum.max(fn -> 0 end)
        end_x = max_x - scroll_offset
        start_x = max(0, end_x - viewport_width)

        points
        |> Enum.filter(fn [x | _] -> x >= start_x and x < end_x end)
        |> Enum.flat_map(fn [x, y, w] ->
          py = round((y - min_val) / range * pixel_height)
          expand_weighted_point(x - start_x, pixel_height - py - 1, w, weight_color(color, bg, w))
        end)
      end)

    render_braille_pixels_colored(all_pixels, width, height, bg)
  end

  defp normalize_scatter_points(series) do
    cond do
      series == [] ->
        []

      match?([_, _, _], hd(series)) and is_number(hd(hd(series))) ->
        series

      is_list(hd(series)) and length(hd(series)) == 2 ->
        Enum.map(series, fn [x, y] -> [x, y, 1.0] end)

      match?({_, _, _}, hd(series)) ->
        Enum.map(series, fn {x, y, w} -> [x, y, w] end)

      is_tuple(hd(series)) ->
        Enum.map(series, fn {x, y} -> [x, y, 1.0] end)

      true ->
        series |> Enum.with_index() |> Enum.map(fn {y, x} -> [x, y, 1.0] end)
    end
  end

  defp expand_weighted_point(px, py, weight, color) when weight >= 0.7 do
    for dx <- -1..1, dy <- -1..1, abs(dx) + abs(dy) <= 1 do
      {px + dx, py + dy, color}
    end
  end

  defp expand_weighted_point(px, py, weight, color) when weight >= 0.4 do
    [{px, py, color}, {px, py - 1, color}, {px, py + 1, color}]
  end

  defp expand_weighted_point(px, py, _weight, color) do
    [{px, py, color}]
  end

  defp weight_color({fr, fg, fb}, {br, bg_g, bb}, weight) do
    w = min(1.0, max(0.0, weight))
    {round(br + (fr - br) * w), round(bg_g + (fg - bg_g) * w), round(bb + (fb - bb) * w)}
  end

  defp colored_braille_segment([], bg), do: Segment.new(braille_char(0), %{bg: bg})

  defp colored_braille_segment(char_pixels, bg) do
    {bits, color} =
      Enum.reduce(char_pixels, {0, nil}, fn {x, y, c}, {b, _} ->
        bit = Map.get(@braille_dot_offsets, {rem(x, 2), rem(y, 4)}, 0)
        {b ||| bit, c}
      end)

    Segment.new(braille_char(bits), %{fg: color, bg: bg})
  end

  defp render_braille_pixels_colored(colored_pixels, width, height, bg) do
    pixel_height = height * 4

    pixels_by_char =
      colored_pixels
      |> Enum.filter(fn {x, y, _c} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y, _c} -> {div(x, 2), div(y, 4)} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          colored_braille_segment(Map.get(pixels_by_char, {col, row}, []), bg)
        end

      Strip.new(segments)
    end
  end

  defp render_braille_area(state, width, height, bg) do
    raw = state.data

    series =
      cond do
        raw == [] -> []
        is_number(hd(raw)) -> [raw]
        match?({_, _}, hd(raw)) -> [raw]
        true -> raw
      end

    case series do
      [] -> {empty_strips(height, bg), state}
      _ -> render_braille_area_stacked(series, state, width, height, bg)
    end
  end

  defp render_braille_area_stacked(series, state, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: [{80, 200, 80}, {200, 180, 40}]
    num_series = length(series)
    pixel_h = height * 4
    pixel_w = width * 2

    stacked = slice_and_stack(series, pixel_w, state._internal.scroll_offset || 0)

    range_result = compute_stack_range(stacked, state.zero_center)

    base = %{
      stacked: stacked, colors: colors, num_series: num_series,
      pixel_h: pixel_h, pixel_w: pixel_w, char_w: width,
      grid: :atomics.new(width * height, signed: false),
      color_grid: Enum.map(0..(width * height - 1), fn _ -> :atomics.new(3, signed: true) end)
    }

    build_braille_area(range_result, base, state, width, height, bg)
  end

  defp build_braille_area({neg_min, pos_max, :split}, base, state, width, height, bg) do
    ctx = Map.merge(base, %{pos_max: pos_max, neg_min: neg_min, zero_py: div(base.pixel_h, 2), mode: :split})
    fill_braille_area_grid(ctx)
    baseline_row = div(div(base.pixel_h, 2), 4)
    strips = render_braille_grid(width, height, base, baseline_row, bg)
    {strips, %{state | min_value: neg_min, max_value: pos_max}}
  end

  defp build_braille_area({stack_min, range, mode}, base, state, width, height, bg) do
    ctx = Map.merge(base, %{range: range, stack_min: stack_min, mode: mode})
    fill_braille_area_grid(ctx)
    baseline_row = compute_baseline_row(state, base.pixel_h, stack_min, range)
    strips = render_braille_grid(width, height, base, baseline_row, bg)
    {strips, %{state | min_value: stack_min, max_value: stack_min + range}}
  end

  defp render_braille_grid(width, height, base, baseline_row, bg) do
    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          braille_area_cell(row, col, width, base.grid, base.color_grid, baseline_row, bg)
        end

      Strip.new(segments)
    end
  end

  defp slice_and_stack(series, pixel_w, scroll_offset) do
    normalized = Enum.map(series, &normalize_weighted_series/1)
    max_len = normalized |> Enum.map(&length/1) |> Enum.max()
    end_idx = max(0, max_len - scroll_offset)
    start_idx = max(0, end_idx - pixel_w)
    visible_count = end_idx - start_idx

    sliced = Enum.map(normalized, fn s -> Enum.slice(s, start_idx, visible_count) end)
    build_stacked_columns(sliced, length(series))
  end

  defp normalize_weighted_series(series) do
    Enum.map(series, fn
      {val, weight} when is_number(val) and is_number(weight) -> {val, weight}
      val when is_number(val) -> {val, 1.0}
    end)
  end

  defp compute_stack_range(stacked, zero_center) do
    all_values =
      Enum.flat_map(stacked, fn col ->
        Enum.flat_map(col, fn
          {bottom, top, _weight} -> [bottom, top]
          {bottom, top} -> [bottom, top]
        end)
      end)

    case all_values do
      [] -> {0, 1, :positive}
      vals -> classify_stack_range(Enum.min(vals), Enum.max(vals), zero_center)
    end
  end

  defp classify_stack_range(data_min, data_max, _zc) when data_min >= 0 do
    {0, max(1, data_max), :positive}
  end

  defp classify_stack_range(data_min, data_max, _zc) when data_max <= 0 do
    {data_min, max(1, abs(data_min)), :negative}
  end

  defp classify_stack_range(data_min, data_max, :independent) do
    {min(data_min, -0.001), max(data_max, 0.001), :split}
  end

  defp classify_stack_range(data_min, data_max, _zc) do
    extreme = max(abs(data_min), abs(data_max))
    {-extreme, extreme * 2, :symmetric}
  end

  defp compute_baseline_row(state, pixel_h, stack_min, range) do
    if state.show_baseline do
      baseline_py = pixel_h - 1 - round((0 - stack_min) / range * (pixel_h - 1))
      div(max(0, min(baseline_py, pixel_h - 1)), 4)
    else
      nil
    end
  end

  defp braille_area_cell(row, col, width, grid, color_grid, baseline_row, bg) do
    idx = row * width + col
    bits = :atomics.get(grid, idx + 1)

    if bits == 0 do
      braille_empty_cell(row, baseline_row, bg)
    else
      braille_colored_cell(bits, Enum.at(color_grid, idx), bg)
    end
  end

  defp braille_empty_cell(row, row, bg), do: Segment.new("⠒", %{fg: {60, 60, 60}, bg: bg})
  defp braille_empty_cell(_row, _baseline, bg), do: Segment.new(braille_char(0), %{bg: bg})

  defp braille_colored_cell(bits, color_ref, bg) do
    fg_color = {:atomics.get(color_ref, 1), :atomics.get(color_ref, 2), :atomics.get(color_ref, 3)}
    Segment.new(braille_char(bits), %{fg: fg_color, bg: bg})
  end

  defp build_stacked_columns(sliced, num_series) do
    max_len = sliced |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    for col_idx <- 0..(max_len - 1) do
      Enum.reduce(0..(num_series - 1), {0, 0, []}, fn si, acc ->
        {val, weight} = sliced |> Enum.at(si) |> Enum.at(col_idx, {0, 1.0})
        stack_value(val, weight, acc)
      end)
      |> elem(2)
      |> Enum.reverse()
    end
  end

  defp stack_value(val, weight, {pos_running, neg_running, acc}) when val >= 0 do
    new_top = pos_running + val
    {new_top, neg_running, [{pos_running, new_top, weight} | acc]}
  end

  defp stack_value(val, weight, {pos_running, neg_running, acc}) do
    new_bottom = neg_running + val
    {pos_running, new_bottom, [{new_bottom, neg_running, weight} | acc]}
  end

  defp fill_braille_area_grid(ctx) do
    ctx.stacked
    |> Enum.with_index()
    |> Enum.each(fn {col_layers, col_idx} ->
      if col_idx < ctx.pixel_w do
        fill_braille_column(col_layers, col_idx, ctx)
      end
    end)
  end

  defp fill_braille_column(col_layers, col_idx, ctx) do
    char_col = div(col_idx, 2)
    local_x = rem(col_idx, 2)

    Enum.each(0..(ctx.num_series - 1), fn si ->
      {bottom, top, weight} = extract_layer(Enum.at(col_layers, si))
      series_color = Enum.at(ctx.colors, rem(si, length(ctx.colors)))
      weighted_color = apply_weight_to_color(series_color, weight)
      dim_color = Drafter.Style.mix({0, 0, 0}, weighted_color, 0.6)

      {lo_py, hi_py, top_py} = compute_pixel_range(bottom, top, ctx)

      Enum.each(lo_py..hi_py, fn py ->
        paint_braille_pixel(py, local_x, char_col, top_py, weighted_color, dim_color, ctx)
      end)
    end)
  end

  defp extract_layer({bottom, top, weight}), do: {bottom, top, weight}
  defp extract_layer({bottom, top}), do: {bottom, top, 1.0}

  defp apply_weight_to_color(color, 1.0), do: color

  defp apply_weight_to_color({r, g, b}, weight) do
    w = min(1.0, max(0.1, weight))
    {round(r * w), round(g * w), round(b * w)}
  end

  defp compute_pixel_range(bottom, top, %{mode: :split} = ctx) do
    bottom_py = value_to_pixel_split(bottom, ctx)
    top_py = value_to_pixel_split(top, ctx)
    lo_py = max(0, min(top_py, ctx.pixel_h - 1))
    hi_py = max(0, min(bottom_py, ctx.pixel_h - 1))
    {lo_py, hi_py, top_py}
  end

  defp compute_pixel_range(bottom, top, ctx) do
    bottom_py = ctx.pixel_h - 1 - round((bottom - ctx.stack_min) / ctx.range * (ctx.pixel_h - 1))
    top_py = ctx.pixel_h - 1 - round((top - ctx.stack_min) / ctx.range * (ctx.pixel_h - 1))
    lo_py = max(0, min(top_py, ctx.pixel_h - 1))
    hi_py = max(0, min(bottom_py, ctx.pixel_h - 1))
    {lo_py, hi_py, top_py}
  end

  defp value_to_pixel_split(value, ctx) when value >= 0 do
    ctx.zero_py - 1 - round(value / ctx.pos_max * (ctx.zero_py - 1))
  end

  defp value_to_pixel_split(value, ctx) do
    ctx.zero_py + round(value / ctx.neg_min * (ctx.pixel_h - ctx.zero_py - 1))
  end

  defp paint_braille_pixel(py, local_x, char_col, top_py, series_color, dim_color, ctx) do
    local_y = rem(py, 4)
    char_row = div(py, 4)
    bit = Map.get(@braille_dot_offsets, {local_x, local_y}, 0)
    idx = char_row * ctx.char_w + char_col + 1
    max_idx = ctx.char_w * div(ctx.pixel_h, 4)

    if idx >= 1 and idx <= max_idx do
      old_bits = :atomics.get(ctx.grid, idx)
      :atomics.put(ctx.grid, idx, old_bits ||| bit)

      pixel_color = if py == top_py, do: series_color, else: dim_color
      blend_pixel_color(Enum.at(ctx.color_grid, idx - 1), pixel_color)
    end
  end

  defp blend_pixel_color(color_ref, {pr, pg, pb} = pixel_color) do
    old_r = :atomics.get(color_ref, 1)
    old_g = :atomics.get(color_ref, 2)
    old_b = :atomics.get(color_ref, 3)

    {mr, mg, mb} =
      if old_r == 0 and old_g == 0 and old_b == 0 do
        {pr, pg, pb}
      else
        Drafter.Style.mix({old_r, old_g, old_b}, pixel_color, 0.5)
      end

    :atomics.put(color_ref, 1, mr)
    :atomics.put(color_ref, 2, mg)
    :atomics.put(color_ref, 3, mb)
  end

  defp render_braille_chart(state, width, height, bg, fg, animation_offset) do
    render_line_chart(%{state | chart_type: :line}, width, height, bg, fg, animation_offset)
  end

  defp render_clustered_bar(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_v(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_clustered_bar_data(state, data, width, height, bg)
    end
  end

  defp render_clustered_bar_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_groups = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    group_width = num_series + gap
    scroll_offset = state._internal.scroll_offset || 0
    viewport_groups = div(width, max(1, group_width))
    end_g = num_groups - scroll_offset
    start_g = max(0, end_g - viewport_groups)
    actual_groups = min(end_g, num_groups) - start_g
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_g, actual_groups) end)
    range = state.max_value - state.min_value
    total_px = height * 2
    zero_pb = round((0 - state.min_value) / range * total_px) |> max(0) |> min(total_px)

    bars =
      for g <- 0..(actual_groups - 1) do
        for s <- 0..(num_series - 1) do
          val = sliced |> Enum.at(s, []) |> Enum.at(g, 0) || 0
          bar_pb = round((val - state.min_value) / range * total_px) |> max(0) |> min(total_px)
          {zero_pb, bar_pb, Enum.at(colors, s, hd(colors))}
        end
      end

    gap_seg = Segment.new(String.duplicate(" ", gap), %{bg: bg})

    ctx = %{
      actual_groups: actual_groups,
      num_series: num_series,
      group_width: group_width,
      width: width,
      bars: bars,
      height: height,
      total_px: total_px,
      gap: gap,
      gap_seg: gap_seg,
      bg: bg
    }

    for row <- 0..(height - 1) do
      segments = build_clustered_row_segments(row, ctx)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  defp build_clustered_row_segments(row, %{actual_groups: actual_groups, num_series: num_series, group_width: group_width, width: width, bars: bars, height: height, total_px: total_px, gap: gap, gap_seg: gap_seg, bg: bg}) do
    Enum.flat_map(0..(actual_groups - 1), fn g ->
      bar_segs =
        0..(num_series - 1)
        |> Enum.filter(fn s -> g * group_width + s < width end)
        |> Enum.map(fn s ->
          {zpb, bpb, color} = bars |> Enum.at(g) |> Enum.at(s)
          half_block_bar_char(row, height, zpb, bpb, total_px, color, bg)
        end)

      if gap > 0 and g < actual_groups - 1, do: bar_segs ++ [gap_seg], else: bar_segs
    end)
  end

  defp render_stacked_bar(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_v(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_stacked_bar_data(state, data, width, height, bg)
    end
  end

  defp render_stacked_bar_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_positions = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    bar_width = 1 + gap
    scroll_offset = state._internal.scroll_offset || 0
    end_p = num_positions - scroll_offset
    start_p = max(0, end_p - div(width, max(1, bar_width)))
    actual = min(end_p, num_positions) - start_p
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_p, actual) end)
    range = state.max_value - state.min_value
    total_px = height * 2
    zero_pb = round((0 - state.min_value) / range * total_px) |> max(0) |> min(total_px)
    stacks = build_stacks(actual, num_series, sliced, colors, zero_pb, range, total_px)
    gap_seg = Segment.new(String.duplicate(" ", gap), %{bg: bg})

    for row <- 0..(height - 1) do
      segments = build_stacked_bar_row(row, height, actual, stacks, total_px, gap, gap_seg, bg)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  defp build_stacked_bar_row(row, height, actual, stacks, total_px, gap, gap_seg, bg) do
    Enum.flat_map(0..(actual - 1), fn p ->
      seg = stacked_bar_char(row, height, Enum.at(stacks, p, []), total_px, bg)
      if gap > 0 and p < actual - 1, do: [seg, gap_seg], else: [seg]
    end)
  end

  defp build_stacks(actual, num_series, sliced, colors, zero_pb, range, total_px) do
    for p <- 0..(actual - 1) do
      Enum.reduce(0..(num_series - 1), {zero_pb, zero_pb, []}, fn s, {pos_top, neg_top, segs} ->
        val = sliced |> Enum.at(s, []) |> Enum.at(p, 0) || 0
        px = round(abs(val) / range * total_px)
        color = Enum.at(colors, s, hd(colors))
        accumulate_stack_segment(val, px, color, pos_top, neg_top, segs)
      end)
      |> elem(2)
      |> Enum.reverse()
    end
  end

  defp accumulate_stack_segment(val, px, color, pos_top, neg_top, segs) when val >= 0 do
    new_top = pos_top + px
    {new_top, neg_top, [{pos_top, new_top, color} | segs]}
  end

  defp accumulate_stack_segment(_val, px, color, pos_top, neg_top, segs) do
    new_bot = neg_top - px
    {pos_top, new_bot, [{new_bot, neg_top, color} | segs]}
  end

  defp render_clustered_bar_h(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_h(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_clustered_bar_h_data(state, data, width, height, bg)
    end
  end

  defp render_clustered_bar_h_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_groups = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    scroll_offset = state._internal.scroll_offset || 0
    viewport_groups = div(height, max(1, num_series + gap))
    end_g = num_groups - scroll_offset
    start_g = max(0, end_g - viewport_groups)
    actual_groups = min(end_g, num_groups) - start_g
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_g, actual_groups) end)
    viewport_labels = Enum.slice(state.bar_labels, start_g, actual_groups)
    label_width = h_label_width(state, viewport_labels)
    value_width = if state.show_values, do: data |> List.flatten() |> Enum.map(fn v -> String.length(Visualization.format_number(v)) end) |> Enum.max(fn -> 0 end) |> Kernel.+(1), else: 0
    bar_width = max(1, width - label_width - value_width)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1
    full_char = CharacterSet.fill(:full)
    gap_strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: bg})])

    strips =
      for g <- 0..(actual_groups - 1) do
        h_ctx = %{
          sliced: sliced,
          colors: colors,
          state: state,
          levels: levels,
          level_count: level_count,
          full_char: full_char,
          bar_width: bar_width,
          label_width: label_width,
          value_width: value_width,
          viewport_labels: viewport_labels,
          bg: bg
        }

        group_strips =
          for s <- 0..(num_series - 1) do
            build_clustered_h_series_strip(s, g, h_ctx)
          end

        if gap > 0 and g < actual_groups - 1,
          do: group_strips ++ List.duplicate(gap_strip, gap),
          else: group_strips
      end
      |> List.flatten()

    Enum.take(strips, height)
  end

  defp build_clustered_h_series_strip(s, g, %{sliced: sliced, colors: colors, state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, bg: bg}) do
    val = sliced |> Enum.at(s, []) |> Enum.at(g, 0) || 0
    color = Enum.at(colors, s, hd(colors))
    normalized = Visualization.normalize(val, state.min_value, state.max_value)
    total_steps = round(normalized * bar_width * level_count)
    full_blocks = div(total_steps, level_count)
    partial_idx = rem(total_steps, level_count)
    full_str = Visualization.safe_duplicate(full_char, full_blocks)
    partial_str = if partial_idx > 0 and full_blocks < bar_width, do: Enum.at(levels, partial_idx, ""), else: ""
    bar_used = full_blocks + if(partial_idx > 0 and full_blocks < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", bar_width - bar_used)

    segs =
      if label_width > 0 do
        lbl = if s == 0, do: Enum.at(viewport_labels, g, "") |> String.pad_trailing(label_width), else: String.duplicate(" ", label_width)
        [Segment.new(lbl, %{fg: color, bg: bg})]
      else
        []
      end

    segs = segs ++ [Segment.new(full_str <> partial_str <> padding, %{fg: color, bg: bg})]

    segs =
      if value_width > 0 do
        val_str = " " <> Visualization.format_number(val)
        segs ++ [Segment.new(String.pad_trailing(val_str, value_width), %{fg: color, bg: bg})]
      else
        segs
      end

    Strip.new(segs)
  end

  defp render_stacked_bar_h(state, width, height, bg) do
    data = state.data

    cond do
      data == [] -> empty_strips(height, bg)
      not is_list(hd(data)) -> render_bar_chart_h(state, width, height, bg, state.color || {100, 200, 100})
      true -> render_stacked_bar_h_data(state, data, width, height, bg)
    end
  end

  defp render_stacked_bar_h_data(state, data, width, height, bg) do
    colors = if state.colors != [], do: state.colors, else: @default_series_colors
    num_series = length(data)
    num_positions = data |> Enum.map(&length/1) |> Enum.max()
    gap = max(0, state.bar_gap || 0)
    scroll_offset = state._internal.scroll_offset || 0
    end_p = num_positions - scroll_offset
    start_p = max(0, end_p - (height - gap * max(0, num_positions - 1)))
    actual = min(end_p, num_positions) - start_p
    sliced = Enum.map(data, fn s -> Enum.slice(s, start_p, actual) end)
    viewport_labels = Enum.slice(state.bar_labels, start_p, actual)
    label_width = h_label_width(state, viewport_labels)
    bar_width = max(1, width - label_width)
    range = state.max_value - state.min_value
    full_char = CharacterSet.fill(:full)
    gap_strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: bg})])

    sh_ctx = %{
      sliced: sliced,
      colors: colors,
      num_series: num_series,
      range: range,
      bar_width: bar_width,
      full_char: full_char,
      label_width: label_width,
      viewport_labels: viewport_labels,
      bg: bg
    }

    strips =
      for p <- 0..(actual - 1) do
        strip = build_stacked_h_strip(p, sh_ctx)
        if gap > 0 and p < actual - 1, do: [strip | List.duplicate(gap_strip, gap)], else: [strip]
      end
      |> List.flatten()

    Enum.take(strips, height)
  end

  defp build_stacked_h_strip(p, %{sliced: sliced, colors: colors, num_series: num_series, range: range, bar_width: bar_width, full_char: full_char, label_width: label_width, viewport_labels: viewport_labels, bg: bg}) do
    label_segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, p, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, %{fg: hd(colors), bg: bg})]
      else
        []
      end

    bar_segs =
      for s <- 0..(num_series - 1) do
        val = sliced |> Enum.at(s, []) |> Enum.at(p, 0) || 0
        color = Enum.at(colors, s, hd(colors))
        seg_width = round(abs(val) / range * bar_width)
        Segment.new(Visualization.safe_duplicate(full_char, seg_width), %{fg: color, bg: bg})
      end

    used = Enum.reduce(bar_segs, 0, fn seg, acc -> acc + String.length(seg.text) end)
    padding = Visualization.safe_duplicate(" ", max(0, bar_width - used))
    Strip.new(label_segs ++ bar_segs ++ [Segment.new(padding, %{bg: bg})])
  end

  defp render_range_bar_h(state, width, height, bg, fg) do
    data = state.data

    if data == [] do
      empty_strips(height, bg)
    else
      render_range_bar_h_data(state, data, width, height, bg, fg)
    end
  end

  defp render_range_bar_h_data(state, data, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    total = length(data)
    end_i = total - scroll_offset
    start_i = max(0, end_i - height)
    viewport = Enum.slice(data, start_i, height)
    viewport_labels = Enum.slice(state.bar_labels, start_i, height)
    label_width = h_label_width(state, viewport_labels)
    value_width = range_bar_value_width(state, viewport)
    bar_width = max(1, width - label_width - value_width)
    full_char = CharacterSet.fill(:full)
    levels = CharacterSet.sparkline_levels_h()
    level_count = length(levels) - 1

    rb_ctx = %{
      state: state,
      levels: levels,
      level_count: level_count,
      full_char: full_char,
      bar_width: bar_width,
      label_width: label_width,
      value_width: value_width,
      viewport_labels: viewport_labels,
      fg: fg,
      bg: bg
    }

    viewport
    |> Enum.with_index()
    |> Enum.map(fn {item, i} -> build_range_bar_h_strip(item, i, rb_ctx) end)
  end

  defp range_bar_value_width(state, viewport) do
    if state.show_values do
      viewport
      |> Enum.flat_map(fn item ->
        {lo, hi} = extract_range_item(item, state)
        [String.length(Visualization.format_number(lo)), String.length(Visualization.format_number(hi))]
      end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)
    else
      0
    end
  end

  defp build_range_bar_h_strip(item, i, %{state: state, levels: levels, level_count: level_count, full_char: full_char, bar_width: bar_width, label_width: label_width, value_width: value_width, viewport_labels: viewport_labels, fg: fg, bg: bg}) do
    {lo, hi} = extract_range_item(item, state)
    lo_norm = Visualization.normalize(lo, state.min_value, state.max_value)
    hi_norm = Visualization.normalize(hi, state.min_value, state.max_value)
    lo_steps = round(lo_norm * bar_width * level_count)
    hi_steps = round(hi_norm * bar_width * level_count)
    lo_full = div(lo_steps, level_count)
    hi_full = div(hi_steps, level_count)
    hi_partial = rem(hi_steps, level_count)
    empty_before = Visualization.safe_duplicate(" ", lo_full)
    bar_fill = Visualization.safe_duplicate(full_char, max(0, hi_full - lo_full))
    partial_str = if hi_partial > 0 and hi_full < bar_width, do: Enum.at(levels, hi_partial, ""), else: ""
    used = lo_full + max(0, hi_full - lo_full) + if(hi_partial > 0 and hi_full < bar_width, do: 1, else: 0)
    padding = Visualization.safe_duplicate(" ", max(0, bar_width - used))

    segs =
      if label_width > 0 do
        lbl = Enum.at(viewport_labels, i, "") |> String.pad_trailing(label_width)
        [Segment.new(lbl, %{fg: fg, bg: bg})]
      else
        []
      end

    segs = segs ++ [Segment.new(empty_before <> bar_fill <> partial_str <> padding, %{fg: fg, bg: bg})]

    segs =
      if value_width > 0 do
        hi_str = " " <> Visualization.format_number(hi)
        segs ++ [Segment.new(String.pad_trailing(hi_str, value_width), %{fg: fg, bg: bg})]
      else
        segs
      end

    Strip.new(segs)
  end

  defp extract_range_item(item, state) do
    case item do
      [l, h | _] -> {l, h}
      {l, h} -> {l, h}
      _ -> {state.min_value, state.min_value}
    end
  end

  defp render_range_bar(state, _width, height, bg, _fg) when state.data == [], do: empty_strips(height, bg)

  defp render_range_bar(state, width, height, bg, fg) do
    scroll_offset = state._internal.scroll_offset || 0
    total = length(state.data)
    end_i = total - scroll_offset
    start_i = max(0, end_i - width)
    viewport = Enum.slice(state.data, start_i, width)
    range = state.max_value - state.min_value
    total_px = height * 2
    bars = render_range_bar_bars(viewport, state, range, total_px)
    render_range_bar_rows(bars, height, width, total_px, fg, bg)
  end

  defp render_range_bar_bars(viewport, state, range, total_px) do
    Enum.map(viewport, fn item ->
      {lo, hi} = extract_range_item(item, state)
      lo_pb = round((lo - state.min_value) / range * total_px) |> max(0) |> min(total_px)
      hi_pb = round((hi - state.min_value) / range * total_px) |> max(0) |> min(total_px)
      {lo_pb, hi_pb}
    end)
  end

  defp render_range_bar_rows(bars, height, width, total_px, fg, bg) do
    for row <- 0..(height - 1) do
      segments = Enum.map(bars, fn {lo_pb, hi_pb} -> half_block_bar_char(row, height, lo_pb, hi_pb, total_px, fg, bg) end)
      padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
      Strip.new(segments ++ padding)
    end
  end

  defp half_block_bar_char(row, height, zero_pb, bar_pb, total_px, color, bg) do
    top_pb = total_px - 1 - 2 * row
    bot_pb = total_px - 2 - 2 * row

    lo = min(zero_pb, bar_pb)
    hi = max(zero_pb, bar_pb) - 1

    if lo > hi do
      Segment.new(" ", %{bg: bg})
    else
      top_filled = lo <= top_pb and top_pb <= hi
      bot_filled = lo <= bot_pb and bot_pb <= hi
      _ = height

      cond do
        top_filled and bot_filled -> Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})
        top_filled -> Segment.new(CharacterSet.fill(:upper_half), %{fg: color, bg: bg})
        bot_filled -> Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})
        true -> Segment.new(" ", %{bg: bg})
      end
    end
  end

  defp stacked_bar_char(row, _height, segs, total_px, bg) do
    top_pb = total_px - 1 - 2 * row
    bot_pb = total_px - 2 - 2 * row
    top_hit = Enum.find(segs, fn {lo, hi, _} -> lo <= top_pb and top_pb <= hi - 1 end)
    bot_hit = Enum.find(segs, fn {lo, hi, _} -> lo <= bot_pb and bot_pb <= hi - 1 end)
    stacked_bar_segment(top_hit, bot_hit, bg)
  end

  defp stacked_bar_segment(nil, nil, bg), do: Segment.new(" ", %{bg: bg})

  defp stacked_bar_segment({_lo, _hi, color}, {_lo2, _hi2, color}, bg),
    do: Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})

  defp stacked_bar_segment({_lo, _hi, color}, nil, bg),
    do: Segment.new(CharacterSet.fill(:upper_half), %{fg: color, bg: bg})

  defp stacked_bar_segment(nil, {_lo, _hi, color}, bg),
    do: Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})

  defp stacked_bar_segment({_lo, _hi, top_color}, {_lo2, _hi2, _bot_color}, bg),
    do: Segment.new(CharacterSet.fill(:upper_half), %{fg: top_color, bg: bg})

  defp braille_char_for_pixels([], _fg, bg), do: Segment.new(braille_char(0), %{fg: bg, bg: bg})
  defp braille_char_for_pixels(char_pixels, fg, bg), do: Segment.new(build_braille_char(char_pixels), %{fg: fg, bg: bg})

  defp render_braille_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 4

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 4)} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          braille_char_for_pixels(Map.get(pixels_by_char, {col, row}, []), fg, bg)
        end

      Strip.new(segments)
    end
  end

  defp quadrant_bit({0, 0}), do: 1
  defp quadrant_bit({1, 0}), do: 2
  defp quadrant_bit({0, 1}), do: 4
  defp quadrant_bit({1, 1}), do: 8
  defp quadrant_bit(_), do: 0

  defp render_quadrant_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 2

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 2)} end)

    for row <- 0..(height - 1) do
      segments = for col <- 0..(width - 1), do: quadrant_pixel_segment(pixels_by_char, col, row, fg, bg)
      Strip.new(segments)
    end
  end

  defp quadrant_pixel_segment(pixels_by_char, col, row, fg, bg) do
    char_pixels = Map.get(pixels_by_char, {col, row}, [])
    bits = Enum.reduce(char_pixels, 0, fn {x, y}, acc -> acc ||| quadrant_bit({rem(x, 2), rem(y, 2)}) end)
    Segment.new(Map.get(@quadrant_chars, bits, " "), %{fg: fg, bg: bg})
  end

  defp build_braille_char(pixels) do
    bits =
      pixels
      |> Enum.map(fn {x, y} ->
        local_x = rem(x, 2)
        local_y = rem(y, 4)
        Map.get(@braille_dot_offsets, {local_x, local_y}, 0)
      end)
      |> Enum.sum()

    braille_char(bits)
  end

  defp braille_char(bits) when bits >= 0 and bits <= 255 do
    <<@braille_base + bits::utf8>>
  end

  defp braille_char(_), do: " "

  defp normalize_data(data, min_val, range, pixel_height) do
    data
    |> Enum.map(fn value ->
      normalized = (value - min_val) / range

      round(normalized * pixel_height)
      |> min(pixel_height - 1)
      |> max(0)
    end)
  end

  defp bresenham_lines([]), do: []
  defp bresenham_lines([_single]), do: []

  defp bresenham_lines([{x1, y1} | rest]) do
    case rest do
      [{x2, y2} | _] -> bresenham_line(x1, y1, x2, y2) ++ bresenham_lines(rest)
      [] -> []
    end
  end

  defp bresenham_line(x1, y1, x2, y2) do
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)
    ctx = {x2, y2, if(x1 < x2, do: 1, else: -1), if(y1 < y2, do: 1, else: -1), dx, dy}
    bresenham_loop(x1, y1, dx - dy, ctx, [])
  end

  defp bresenham_loop(x, y, _err, {x2, y2, _sx, _sy, _dx, _dy}, acc) when x == x2 and y == y2 do
    Enum.reverse([{x, y} | acc])
  end

  defp bresenham_loop(x, y, err, {_x2, _y2, sx, sy, dx, dy} = ctx, acc) do
    e2 = 2 * err
    {new_x, new_err} = if e2 > -dy, do: {x + sx, err - dy}, else: {x, err}
    {new_y, final_err} = if e2 < dx, do: {y + sy, new_err + dx}, else: {y, new_err}
    bresenham_loop(new_x, new_y, final_err, ctx, [{x, y} | acc])
  end

  defp empty_strips(height, bg) do
    for _ <- 1..height do
      Strip.new([Segment.new("", %{bg: bg})])
    end
  end

  defp data_to_tuple(data) when is_list(data), do: List.to_tuple(data)
  defp data_to_tuple(data), do: data

  defp tuple_size_or_length(tuple) when is_tuple(tuple), do: tuple_size(tuple)
  defp tuple_size_or_length(list), do: length(list)

  defp add_axes(strips, state, rect, bg, fg) do
    y_axis_width = 5

    y_axis_segments =
      for i <- 0..(rect.height - 3) do
        y_val = state.max_value - (state.max_value - state.min_value) * i / (rect.height - 3)
        label = format_axis_value(y_val)
        Segment.new(String.pad_leading(label, y_axis_width - 1) <> "│", %{fg: fg, bg: bg})
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
            Segment.new(String.duplicate(" ", y_axis_width), %{bg: bg})
          end

        Strip.new([y_seg | strip.segments])
      end)

    x_axis = " " <> String.duplicate("─", rect.width - 7) <> "┘"

    x_axis_strip =
      Strip.new([Segment.new(String.pad_trailing(x_axis, rect.width), %{fg: fg, bg: bg})])

    strips_with_y ++ [x_axis_strip]
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

  defp format_axis_value(val) when is_float(val) do
    cond do
      abs(val) >= 1000 -> "#{Float.round(val / 1000, 1)}k"
      abs(val) >= 1 -> Float.round(val, 1) |> to_string()
      true -> Float.round(val, 3) |> to_string()
    end
  end

  defp format_axis_value(val), do: to_string(val)

  def render_tall_bar_chart(data, height, opts \\ []) do
    min_val = Keyword.get(opts, :min, 0)
    max_val = Keyword.get(opts, :max, 100)
    color = Keyword.get(opts, :color, {100, 200, 100})
    bg = Keyword.get(opts, :bg, {20, 20, 30})

    range = max_val - min_val

    bars =
      data
      |> Enum.map(fn value ->
        normalized = (value - min_val) / range
        {normalized, value}
      end)

    pixel_height = height * 2

    for row <- 0..(height - 1) do
      row_top = (height - 1 - row) * 2
      row_bottom = row_top + 1

      segments =
        Enum.map(bars, fn {normalized, _value} ->
          bar_pixel = round(normalized * pixel_height)
          tall_bar_segment(bar_pixel, row_top, row_bottom, color, bg)
        end)

      Strip.new(segments)
    end
  end

  defp tall_bar_segment(bar_pixel, row_top, _row_bottom, _color, bg) when bar_pixel <= row_top, do: Segment.new(" ", %{bg: bg})
  defp tall_bar_segment(bar_pixel, _row_top, row_bottom, color, bg) when bar_pixel >= row_bottom + 1, do: Segment.new(CharacterSet.fill(:full), %{fg: color, bg: bg})
  defp tall_bar_segment(bar_pixel, row_top, _row_bottom, color, bg) when bar_pixel == row_top + 1, do: Segment.new(CharacterSet.fill(:lower_half), %{fg: color, bg: bg})
  defp tall_bar_segment(_bar_pixel, _row_top, _row_bottom, _color, bg), do: Segment.new(" ", %{bg: bg})

  @multi_series_default_colors [{255, 100, 100}, {100, 255, 100}, {100, 100, 255}, {255, 255, 100}]

  def render_multi_series(data_series, width, height, opts \\ []) do
    bg = Keyword.get(opts, :bg, {20, 20, 30})
    colors = Keyword.get(opts, :colors, @multi_series_default_colors)
    {min_val, max_val} = resolve_multi_series_range(opts, data_series)
    range = max_val - min_val
    pixel_height = height * 4
    colors_tuple = List.to_tuple(colors)
    color_count = tuple_size(colors_tuple)

    all_pixels =
      data_series
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, series_idx} ->
        color = elem(colors_tuple, rem(series_idx, color_count))
        series_to_pixels(series, color, min_val, range, pixel_height)
      end)

    pixels_by_char = Enum.group_by(all_pixels, fn {{cx, cy}, _, _} -> {cx, cy} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          multi_series_segment(Map.get(pixels_by_char, {col, row}, []), hd(colors), bg)
        end

      Strip.new(segments)
    end
  end

  defp resolve_multi_series_range(opts, data_series) do
    case {Keyword.get(opts, :min), Keyword.get(opts, :max)} do
      {nil, nil} ->
        all_values = List.flatten(data_series)
        {Enum.min(all_values), Enum.max(all_values)}

      {nil, max} ->
        {data_series |> List.flatten() |> Enum.min(), max}

      {min, nil} ->
        {min, data_series |> List.flatten() |> Enum.max()}

      {min, max} ->
        {min, max}
    end
  end

  defp series_to_pixels(series, color, min_val, range, pixel_height) do
    series
    |> Enum.with_index()
    |> Enum.map(fn {value, x} ->
      normalized = (value - min_val) / range
      y = round((1 - normalized) * (pixel_height - 1))
      {{div(x, 2), div(y, 4)}, {rem(x, 2), rem(y, 4)}, color}
    end)
  end

  defp multi_series_segment([], _fallback_color, bg), do: Segment.new(" ", %{bg: bg})

  defp multi_series_segment(char_pixels, fallback_color, bg) do
    {bits, color} =
      Enum.reduce(char_pixels, {0, nil}, fn {_, {lx, ly}, c}, {b, _} ->
        bit = Map.get(@braille_dot_offsets, {lx, ly}, 0)
        {b ||| bit, c}
      end)

    Segment.new(braille_char(bits), %{fg: color || fallback_color, bg: bg})
  end

  defp update_internal(state, updates) do
    %{state | _internal: Enum.into(updates, state._internal)}
  end
end
