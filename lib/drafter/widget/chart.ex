defmodule Drafter.Widget.Chart do
  @moduledoc """
  Renders time-series and financial data as interactive charts with multiple styles.

  Supported chart types: `:line`, `:area`, `:bar`, `:clustered_bar`, `:stacked_bar`,
  `:range_bar`, `:scatter`, and `:candlestick`. Braille-dot rendering provides the
  highest resolution (two data points per column, four per row). Quadrant-block
  rendering provides 2×2 pixel resolution per cell (coarser but larger dots). Bar
  charts use half-block characters for 2× vertical resolution.

  Scatter data points accept `[x, y]` lists or `{x, y}` tuples.
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
    * `:chart_type` — `:line` (default), `:area`, `:bar`, `:clustered_bar`,
      `:stacked_bar`, `:range_bar`, `:scatter`, `:candlestick`
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
    handles: [:keyboard, :mouse_up, :drag],
    scroll: [direction: :horizontal, step: 5],
    focusable: true

  import Bitwise

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
    :_render_timestamp,
    :_animation_offset,
    :_live_candle,
    :_scroll_offset,
    :_drag_last_x,
    :_drag_last_y,
    :_y_offset,
    :_data_tuple,
    :_data_hash,
    bar_gap: 0,
    dragging_scrollbar: false,
    focused: false
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

  @block_chars [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

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
      _render_timestamp: Map.get(props, :_render_timestamp, 0),
      _animation_offset: 0,
      _live_candle: live_candle,
      _scroll_offset: 0,
      _drag_last_x: nil,
      _drag_last_y: nil,
      _y_offset: 0,
      _data_tuple: data_tuple,
      _data_hash: data_hash,
      dragging_scrollbar: false
    }
  end

  @impl Drafter.Widget
  def handle_mouse_up(_x, _y, state) do
    {:ok, %{state | dragging_scrollbar: true, _drag_last_x: nil}}
  end

  @impl Drafter.Widget
  def handle_key(:left, state), do: scroll_left(state)
  def handle_key(:"ArrowLeft", state), do: scroll_left(state)
  def handle_key(:right, state), do: scroll_right(state)
  def handle_key(:"ArrowRight", state), do: scroll_right(state)
  def handle_key(:up, state), do: {:ok, %{state | _y_offset: (state._y_offset || 0) + 1}}
  def handle_key(:"ArrowUp", state), do: {:ok, %{state | _y_offset: (state._y_offset || 0) + 1}}
  def handle_key(:down, state), do: {:ok, %{state | _y_offset: (state._y_offset || 0) - 1}}
  def handle_key(:"ArrowDown", state), do: {:ok, %{state | _y_offset: (state._y_offset || 0) - 1}}
  def handle_key(?c, state), do: {:ok, %{state | _y_offset: 0}}
  def handle_key(_key, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_drag(x, y, %{_drag_last_x: nil} = state) do
    {:ok, %{state | _drag_last_x: x, _drag_last_y: y}}
  end

  def handle_drag(x, y, state) do
    dx = (state._drag_last_x || x) - x
    dy = y - (state._drag_last_y || y)
    new_x_offset = max(0, (state._scroll_offset || 0) + dx)
    new_y_offset = (state._y_offset || 0) + dy
    {:ok, %{state | _scroll_offset: new_x_offset, _drag_last_x: x, _y_offset: new_y_offset, _drag_last_y: y}}
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  def component_tag, do: :chart

  def from_component_opts(data, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80, height: 20})
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
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
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__),
      _render_timestamp: System.monotonic_time(:millisecond)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    Map.put(mount_props, :_render_timestamp, System.monotonic_time(:millisecond))
  end

  defp scroll_left(state), do: {:ok, %{state | _scroll_offset: max(0, (state._scroll_offset || 0) - 5)}}
  defp scroll_right(state), do: {:ok, %{state | _scroll_offset: (state._scroll_offset || 0) + 5}}

  defp init_live_candle(data) when is_list(data) and length(data) > 0 do
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
        div(state._render_timestamp, state.animation_speed)
      else
        0
      end

    strips =
      case state.chart_type do
        :line ->
          render_line_chart(state, chart_width, chart_height, bg, fg, animation_offset)

        :bar ->
          render_bar_chart(state, chart_width, chart_height, bg, fg)

        :clustered_bar ->
          render_clustered_bar(state, chart_width, chart_height, bg)

        :stacked_bar ->
          render_stacked_bar(state, chart_width, chart_height, bg)

        :range_bar ->
          render_range_bar(state, chart_width, chart_height, bg, fg)

        :candlestick ->
          render_candlestick_chart(state, chart_width, chart_height, bg, fg)

        :area ->
          render_area_chart(state, chart_width, chart_height, bg, fg, animation_offset)

        :scatter ->
          render_scatter_chart(state, chart_width, chart_height, bg, fg)

        :braille ->
          render_braille_chart(state, chart_width, chart_height, bg, fg, animation_offset)

        _ ->
          render_line_chart(state, chart_width, chart_height, bg, fg, animation_offset)
      end

    strips =
      if state.show_axes do
        add_axes(strips, state, rect, bg, fg)
      else
        strips
      end

    strips =
      if state.title do
        add_title(strips, state.title, rect, bg, fg)
      else
        strips
      end

    pad_strips(strips, rect.height)
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)
    new_hash = :erlang.phash2(new_data)
    data_changed = new_hash != state._data_hash

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

    live_candle = state._live_candle || init_live_candle(new_data)

    {new_tuple, new_hash} =
      if data_changed do
        {data_to_tuple(new_data), new_hash}
      else
        {state._data_tuple, state._data_hash}
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
        _render_timestamp: Map.get(props, :_render_timestamp, state._render_timestamp),
        _live_candle: live_candle,
        _data_tuple: new_tuple,
        _data_hash: new_hash
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
      if length(all_values) > 0 do
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

  defp extract_values(data) when is_list(data) and length(data) > 0 do
    first = hd(data)

    cond do
      is_number(first) ->
        data

      is_list(first) and first != [] and is_number(hd(first)) ->
        Enum.flat_map(data, & &1)

      is_list(first) and first != [] and is_list(hd(first)) ->
        data |> Enum.flat_map(& &1) |> Enum.flat_map(& &1)

      true ->
        []
    end
  end

  defp extract_values(_), do: []

  defp render_line_chart(state, width, height, bg, fg, animation_offset) do
    data = state.data
    data_src = state._data_tuple || data

    cond do
      tuple_size_or_length(data_src) < 2 ->
        empty_strips(height, bg)

      is_list(data) and is_list(hd(data)) ->
        colors =
          if state.colors != [] do
            state.colors
          else
            @default_series_colors
          end

        scroll_offset = state._scroll_offset || 0
        viewport_width = width * 2

        scrolled_series =
          Enum.map(data, fn series ->
            total = length(series)
            end_idx = total - scroll_offset
            start_idx = max(0, end_idx - viewport_width)
            Enum.slice(series, start_idx, viewport_width)
          end)

        render_multi_series(scrolled_series, width, height,
          bg: bg,
          colors: colors,
          min: state.min_value,
          max: state.max_value
        )

      true ->
        scroll_offset = state._scroll_offset || 0
        total_points = tuple_size_or_length(data_src)
        viewport_width = width * 2

        end_index = total_points - scroll_offset
        start_index = max(0, end_index - viewport_width)

        viewport_data = tuple_slice(data_src, start_index, viewport_width)

        range = state.max_value - state.min_value
        pixel_height = height * 4

        normalized = normalize_data(viewport_data, state.min_value, range, pixel_height)

        shifted =
          if animation_offset > 0 do
            shift = rem(animation_offset, length(normalized))
            Enum.drop(normalized, shift) ++ Enum.take(normalized, shift)
          else
            normalized
          end

        points = Enum.with_index(shifted) |> Enum.map(fn {y, x} -> {x, y} end)

        lines = bresenham_lines(points)

        case state.pixel_style do
          :quadrant -> render_quadrant_pixels(lines, width, height, bg, fg)
          _ -> render_braille_pixels(lines, width, height, bg, fg)
        end
    end
  end

  defp render_bar_chart(state, width, height, bg, fg) do
    data_src = state._data_tuple || state.data

    if tuple_size_or_length(data_src) == 0 do
      empty_strips(height, bg)
    else
      range = state.max_value - state.min_value
      scroll_offset = state._scroll_offset || 0
      total_bars = tuple_size_or_length(data_src)

      end_index = total_bars - scroll_offset
      start_index = max(0, end_index - width)
      viewport_data = tuple_slice(data_src, start_index, width)

      bars =
        viewport_data
        |> Enum.map(fn value ->
          normalized = (value - state.min_value) / range
          bar_height = round(normalized * 8)
          Enum.at(@block_chars, min(8, max(0, bar_height)))
        end)

      bar_string = Enum.join(bars)
      padding = String.duplicate(" ", max(0, width - length(bars)))

      [Strip.new([Segment.new(bar_string <> padding, %{fg: fg, bg: bg})])]
    end
  end

  defp render_candlestick_chart(state, width, height, bg, _fg) do
    candles = state.data || []

    if length(candles) == 0 do
      empty_strips(height, bg)
    else
      first = hd(candles)

      is_valid_candle =
        cond do
          is_map(first) ->
            Map.has_key?(first, :open) and Map.has_key?(first, :high) and
              Map.has_key?(first, :low) and Map.has_key?(first, :close)

          is_list(first) ->
            length(first) >= 4

          true ->
            false
        end

      if not is_valid_candle do
        empty_strips(height, bg)
      else
        filtered_candles =
          Enum.filter(candles, fn c ->
            cond do
              is_map(c) ->
                Map.has_key?(c, :open) and Map.has_key?(c, :high) and
                  Map.has_key?(c, :low) and Map.has_key?(c, :close)

              is_list(c) ->
                length(c) >= 4

              true ->
                false
            end
          end)

        total_candles = length(filtered_candles)
        scroll_offset = state._scroll_offset || 0
        y_offset = state._y_offset || 0

        label_width = 11
        viewport_width = max(1, width - label_width)

        end_index = total_candles - scroll_offset
        start_index = max(0, end_index - viewport_width)

        display_candles = Enum.slice(filtered_candles, start_index, viewport_width)

        if length(display_candles) == 0 do
          empty_strips(height, bg)
        else
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
            render_candlestick_body(
              display_candles,
              height - 1,
              min_val,
              max_val,
              bull_color,
              bear_color,
              label_color,
              bg
            )

          time_strip =
            render_time_axis(
              display_candles,
              start_index,
              label_color,
              time_label_color,
              bg
            )

          chart_strips ++ [time_strip]
        end
      end
    end
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
            is_doji -> "-"
            is_spinning_top -> "┼"
            true -> "█"
          end

        {color, high_row, low_row, body_top_row, body_bottom_row, body_char}
      end)

    for row <- 0..(height - 1) do
      row_mid_price = max_val - (row + 0.5) * price_per_row
      label_text = format_price_label(row_mid_price)
      label_seg = Segment.new(String.pad_trailing(label_text, label_width), %{fg: label_color, bg: bg})

      candle_segments =
        Enum.map(precomputed, fn {color, high_row, low_row, body_top_row, body_bottom_row, body_char} ->
          cond do
            row >= body_top_row and row <= body_bottom_row ->
              Segment.new(body_char, %{fg: color, bg: bg})

            row >= high_row and row <= low_row ->
              Segment.new("│", %{fg: color, bg: bg})

            true ->
              empty_seg
          end
        end)

      Strip.new([label_seg | candle_segments])
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

  defp render_area_chart(state, width, height, bg, fg, animation_offset) do
    data = state.data
    data_src = state._data_tuple || data

    cond do
      tuple_size_or_length(data_src) < 2 ->
        empty_strips(height, bg)

      is_list(data) and is_list(hd(data)) ->
        colors =
          if state.colors != [],
            do: state.colors,
            else: [{100, 200, 255}, {255, 130, 80}, {80, 255, 150}, {255, 100, 180}, {200, 180, 60}, {180, 100, 255}]

        render_multi_series(data, width, height,
          bg: bg,
          colors: colors,
          min: state.min_value,
          max: state.max_value
        )

      true ->
        range = state.max_value - state.min_value
        pixel_height = height * 4
        scroll_offset = state._scroll_offset || 0

        viewport_width = width * 2
        total_points = tuple_size_or_length(data_src)
        end_index = total_points - scroll_offset
        start_index = max(0, end_index - viewport_width)
        viewport_data = tuple_slice(data_src, start_index, viewport_width)

        normalized = normalize_data(viewport_data, state.min_value, range, pixel_height)

        shifted =
          if animation_offset > 0 do
            shift = rem(animation_offset, length(normalized))
            Enum.drop(normalized, shift) ++ Enum.take(normalized, shift)
          else
            normalized
          end

        pixels =
          shifted
          |> Enum.with_index()
          |> Enum.flat_map(fn {y, x} ->
            case state.area_fill do
              :inverted ->
                flipped = pixel_height - 1 - y
                for yi <- flipped..(pixel_height - 1), do: {x, yi}
              _ ->
                for yi <- 0..y, do: {x, yi}
            end
          end)

        render_braille_pixels(pixels, width, height, bg, fg)
    end
  end

  defp render_scatter_chart(state, width, height, bg, fg) do
    data = state.data

    cond do
      length(data) == 0 ->
        empty_strips(height, bg)

      is_list(hd(data)) and hd(data) != [] and is_list(hd(hd(data))) ->
        colors = if state.colors != [], do: state.colors, else: @default_series_colors
        render_multi_series_scatter(data, width, height, bg, colors, state.min_value, state.max_value, state._scroll_offset || 0)

      true ->
        points =
          cond do
            is_list(hd(data)) and length(hd(data)) == 2 ->
              data

            is_tuple(hd(data)) and tuple_size(hd(data)) == 2 ->
              Enum.map(data, fn {x, y} -> [x, y] end)

            true ->
              data |> Enum.with_index() |> Enum.map(fn {y, x} -> [x, y] end)
          end

        range = state.max_value - state.min_value
        pixel_height = height * 4
        scroll_offset = state._scroll_offset || 0
        viewport_width = width * 2
        max_x = Enum.map(points, fn [x, _] -> x end) |> Enum.max(fn -> 0 end)
        end_x = max_x - scroll_offset
        start_x = max(0, end_x - viewport_width)

        pixels =
          points
          |> Enum.filter(fn [x, _y] -> x >= start_x and x < end_x end)
          |> Enum.map(fn [x, y] ->
            pixel_y = round((y - state.min_value) / range * pixel_height)
            {x - start_x, pixel_height - pixel_y - 1}
          end)

        case state.pixel_style do
          :quadrant -> render_quadrant_pixels(pixels, width, height, bg, fg)
          _ -> render_braille_pixels(pixels, width, height, bg, fg)
        end
    end
  end

  defp render_multi_series_scatter(data, width, height, bg, colors, min_val, max_val, scroll_offset) do
    range = max_val - min_val
    pixel_height = height * 4
    viewport_width = width * 2

    all_pixels =
      data
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, idx} ->
        color = Enum.at(colors, idx, hd(colors))
        points = normalize_scatter_points(series)
        max_x = Enum.map(points, fn [x, _] -> x end) |> Enum.max(fn -> 0 end)
        end_x = max_x - scroll_offset
        start_x = max(0, end_x - viewport_width)

        points
        |> Enum.filter(fn [x, _] -> x >= start_x and x < end_x end)
        |> Enum.map(fn [x, y] ->
          py = round((y - min_val) / range * pixel_height)
          {x - start_x, pixel_height - py - 1, color}
        end)
      end)

    render_braille_pixels_colored(all_pixels, width, height, bg)
  end

  defp normalize_scatter_points(series) do
    cond do
      length(series) == 0 ->
        []

      is_list(hd(series)) ->
        series

      is_tuple(hd(series)) ->
        Enum.map(series, fn {x, y} -> [x, y] end)

      true ->
        series |> Enum.with_index() |> Enum.map(fn {y, x} -> [x, y] end)
    end
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
          char_pixels = Map.get(pixels_by_char, {col, row}, [])

          if char_pixels == [] do
            Segment.new(braille_char(0), %{bg: bg})
          else
            {bits, color} =
              Enum.reduce(char_pixels, {0, nil}, fn {x, y, c}, {b, _} ->
                bit = Map.get(@braille_dot_offsets, {rem(x, 2), rem(y, 4)}, 0)
                {b ||| bit, c}
              end)

            Segment.new(braille_char(bits), %{fg: color, bg: bg})
          end
        end

      Strip.new(segments)
    end
  end

  defp render_braille_chart(state, width, height, bg, fg, animation_offset) do
    render_line_chart(%{state | chart_type: :line}, width, height, bg, fg, animation_offset)
  end

  defp render_clustered_bar(state, width, height, bg) do
    data = state.data

    cond do
      length(data) == 0 ->
        empty_strips(height, bg)

      not is_list(hd(data)) ->
        fg = state.color || {100, 200, 100}
        render_bar_chart(state, width, height, bg, fg)

      true ->
        colors = if state.colors != [], do: state.colors, else: @default_series_colors
        num_series = length(data)
        num_groups = data |> Enum.map(&length/1) |> Enum.max()
        gap = max(0, state.bar_gap || 0)
        group_width = num_series + gap

        scroll_offset = state._scroll_offset || 0
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

        for row <- 0..(height - 1) do
          segments =
            Enum.flat_map(0..(actual_groups - 1), fn g ->
              bar_segs =
                for s <- 0..(num_series - 1) do
                  col = g * group_width + s
                  if col < width do
                    {zpb, bpb, color} = bars |> Enum.at(g) |> Enum.at(s)
                    half_block_bar_char(row, height, zpb, bpb, total_px, color, bg)
                  end
                end
                |> Enum.reject(&is_nil/1)

              if gap > 0 and g < actual_groups - 1, do: bar_segs ++ [gap_seg], else: bar_segs
            end)

          padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
          Strip.new(segments ++ padding)
        end
    end
  end

  defp render_stacked_bar(state, width, height, bg) do
    data = state.data

    cond do
      length(data) == 0 ->
        empty_strips(height, bg)

      not is_list(hd(data)) ->
        fg = state.color || {100, 200, 100}
        render_bar_chart(state, width, height, bg, fg)

      true ->
        colors = if state.colors != [], do: state.colors, else: @default_series_colors
        num_series = length(data)
        num_positions = data |> Enum.map(&length/1) |> Enum.max()
        gap = max(0, state.bar_gap || 0)
        bar_width = 1 + gap

        scroll_offset = state._scroll_offset || 0
        end_p = num_positions - scroll_offset
        start_p = max(0, end_p - div(width, max(1, bar_width)))
        actual = min(end_p, num_positions) - start_p

        sliced = Enum.map(data, fn s -> Enum.slice(s, start_p, actual) end)

        range = state.max_value - state.min_value
        total_px = height * 2
        zero_pb = round((0 - state.min_value) / range * total_px) |> max(0) |> min(total_px)

        stacks =
          for p <- 0..(actual - 1) do
            Enum.reduce(0..(num_series - 1), {zero_pb, zero_pb, []}, fn s, {pos_top, neg_top, segs} ->
              val = sliced |> Enum.at(s, []) |> Enum.at(p, 0) || 0
              px = round(abs(val) / range * total_px)
              color = Enum.at(colors, s, hd(colors))

              if val >= 0 do
                new_top = pos_top + px
                {new_top, neg_top, [{pos_top, new_top, color} | segs]}
              else
                new_bot = neg_top - px
                {pos_top, new_bot, [{new_bot, neg_top, color} | segs]}
              end
            end)
            |> elem(2)
            |> Enum.reverse()
          end

        gap_seg = Segment.new(String.duplicate(" ", gap), %{bg: bg})

        for row <- 0..(height - 1) do
          segments =
            Enum.flat_map(0..(actual - 1), fn p ->
              seg = stacked_bar_char(row, height, Enum.at(stacks, p, []), total_px, bg)
              if gap > 0 and p < actual - 1, do: [seg, gap_seg], else: [seg]
            end)

          padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
          Strip.new(segments ++ padding)
        end
    end
  end

  defp render_range_bar(state, width, height, bg, fg) do
    data = state.data

    if length(data) == 0 do
      empty_strips(height, bg)
    else
      scroll_offset = state._scroll_offset || 0
      total = length(data)
      end_i = total - scroll_offset
      start_i = max(0, end_i - width)
      viewport = Enum.slice(data, start_i, width)

      range = state.max_value - state.min_value
      total_px = height * 2

      bars =
        Enum.map(viewport, fn item ->
          {lo, hi} =
            case item do
              [l, h | _] -> {l, h}
              {l, h} -> {l, h}
              _ -> {state.min_value, state.min_value}
            end

          lo_pb = round((lo - state.min_value) / range * total_px) |> max(0) |> min(total_px)
          hi_pb = round((hi - state.min_value) / range * total_px) |> max(0) |> min(total_px)
          {lo_pb, hi_pb}
        end)

      for row <- 0..(height - 1) do
        segments =
          Enum.map(bars, fn {lo_pb, hi_pb} ->
            half_block_bar_char(row, height, lo_pb, hi_pb, total_px, fg, bg)
          end)

        padding = List.duplicate(Segment.new(" ", %{bg: bg}), max(0, width - length(segments)))
        Strip.new(segments ++ padding)
      end
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
        top_filled and bot_filled -> Segment.new("█", %{fg: color, bg: bg})
        top_filled -> Segment.new("▀", %{fg: color, bg: bg})
        bot_filled -> Segment.new("▄", %{fg: color, bg: bg})
        true -> Segment.new(" ", %{bg: bg})
      end
    end
  end

  defp stacked_bar_char(row, height, segs, total_px, bg) do
    top_pb = total_px - 1 - 2 * row
    bot_pb = total_px - 2 - 2 * row
    _ = height

    hit =
      Enum.find(segs, fn {lo, hi, _color} -> lo <= top_pb and top_pb <= hi - 1 end) ||
        Enum.find(segs, fn {lo, hi, _color} -> lo <= bot_pb and bot_pb <= hi - 1 end)

    case hit do
      nil ->
        Segment.new(" ", %{bg: bg})

      {lo, hi, color} ->
        top_filled = lo <= top_pb and top_pb <= hi - 1
        bot_filled = lo <= bot_pb and bot_pb <= hi - 1

        cond do
          top_filled and bot_filled -> Segment.new("█", %{fg: color, bg: bg})
          top_filled -> Segment.new("▀", %{fg: color, bg: bg})
          bot_filled -> Segment.new("▄", %{fg: color, bg: bg})
          true -> Segment.new(" ", %{bg: bg})
        end
    end
  end

  defp render_braille_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 4

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} ->
        char_x = div(x, 2)
        char_y = div(y, 4)
        {char_x, char_y}
      end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          char_pixels = Map.get(pixels_by_char, {col, row}, [])

          char =
            if length(char_pixels) > 0 do
              build_braille_char(char_pixels)
            else
              braille_char(0)
            end

          Segment.new(char, %{fg: fg, bg: bg})
        end

      Strip.new(segments)
    end
  end

  defp render_quadrant_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 2

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 2)} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          char_pixels = Map.get(pixels_by_char, {col, row}, [])

          bits =
            Enum.reduce(char_pixels, 0, fn {x, y}, acc ->
              local_x = rem(x, 2)
              local_y = rem(y, 2)

              bit =
                case {local_x, local_y} do
                  {0, 0} -> 1
                  {1, 0} -> 2
                  {0, 1} -> 4
                  {1, 1} -> 8
                end

              acc ||| bit
            end)

          char = Map.get(@quadrant_chars, bits, " ")
          Segment.new(char, %{fg: fg, bg: bg})
        end

      Strip.new(segments)
    end
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
    sx = if x1 < x2, do: 1, else: -1
    sy = if y1 < y2, do: 1, else: -1
    err = dx - dy

    bresenham_loop(x1, y1, x2, y2, sx, sy, dx, dy, err, [])
  end

  defp bresenham_loop(x, y, x2, y2, _sx, _sy, _dx, _dy, _err, acc) when x == x2 and y == y2 do
    Enum.reverse([{x, y} | acc])
  end

  defp bresenham_loop(x, y, x2, y2, sx, sy, dx, dy, err, acc) do
    e2 = 2 * err

    {new_x, new_err} =
      if e2 > -dy do
        {x + sx, err - dy}
      else
        {x, err}
      end

    {new_y, final_err} =
      if e2 < dx do
        {y + sy, new_err + dx}
      else
        {y, new_err}
      end

    bresenham_loop(new_x, new_y, x2, y2, sx, sy, dx, dy, final_err, [{x, y} | acc])
  end

  defp empty_strips(height, bg) do
    for _ <- 1..height do
      Strip.new([Segment.new("", %{bg: bg})])
    end
  end

  defp data_to_tuple(data) when is_list(data), do: List.to_tuple(data)
  defp data_to_tuple(data), do: data

  defp tuple_slice(tuple, start, count) when is_tuple(tuple) do
    size = tuple_size(tuple)
    safe_start = max(0, min(start, size))
    safe_count = min(count, size - safe_start)

    if safe_count <= 0 do
      []
    else
      for i <- safe_start..(safe_start + safe_count - 1) do
        elem(tuple, i)
      end
    end
  end

  defp tuple_slice(list, start, count), do: Enum.slice(list, start, count)

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
        bars
        |> Enum.map(fn {normalized, _value} ->
          bar_pixel = round(normalized * pixel_height)

          cond do
            bar_pixel <= row_top ->
              Segment.new(" ", %{bg: bg})

            bar_pixel >= row_bottom + 1 ->
              Segment.new("█", %{fg: color, bg: bg})

            true ->
              if bar_pixel == row_top + 1 do
                Segment.new("▄", %{fg: color, bg: bg})
              else
                Segment.new(" ", %{bg: bg})
              end
          end
        end)

      Strip.new(segments)
    end
  end

  def render_multi_series(data_series, width, height, opts \\ []) do
    bg = Keyword.get(opts, :bg, {20, 20, 30})

    colors =
      Keyword.get(opts, :colors, [
        {255, 100, 100},
        {100, 255, 100},
        {100, 100, 255},
        {255, 255, 100}
      ])

    {min_val, max_val} =
      case {Keyword.get(opts, :min), Keyword.get(opts, :max)} do
        {nil, nil} ->
          all_values = List.flatten(data_series)
          {Enum.min(all_values), Enum.max(all_values)}

        {nil, max} ->
          all_values = List.flatten(data_series)
          {Enum.min(all_values), max}

        {min, nil} ->
          all_values = List.flatten(data_series)
          {min, Enum.max(all_values)}

        {min, max} ->
          {min, max}
      end
    range = max_val - min_val

    pixel_height = height * 4

    colors_tuple = List.to_tuple(colors)
    color_count = tuple_size(colors_tuple)

    all_pixels =
      data_series
      |> Enum.with_index()
      |> Enum.flat_map(fn {series, series_idx} ->
        color = elem(colors_tuple, rem(series_idx, color_count))

        series
        |> Enum.with_index()
        |> Enum.map(fn {value, x} ->
          normalized = (value - min_val) / range
          y = round((1 - normalized) * (pixel_height - 1))
          {{div(x, 2), div(y, 4)}, {rem(x, 2), rem(y, 4)}, color}
        end)
      end)

    pixels_by_char = Enum.group_by(all_pixels, fn {{cx, cy}, _, _} -> {cx, cy} end)

    for row <- 0..(height - 1) do
      segments =
        for col <- 0..(width - 1) do
          char_pixels = Map.get(pixels_by_char, {col, row}, [])

          if char_pixels != [] do
            {bits, color} =
              Enum.reduce(char_pixels, {0, nil}, fn {_, {lx, ly}, c}, {b, _} ->
                bit = Map.get(@braille_dot_offsets, {lx, ly}, 0)
                {b ||| bit, c}
              end)

            Segment.new(braille_char(bits), %{fg: color || hd(colors), bg: bg})
          else
            Segment.new(" ", %{bg: bg})
          end
        end

      Strip.new(segments)
    end
  end
end
