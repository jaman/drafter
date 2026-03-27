defmodule Drafter.Widget.Chart.Candlestick do
  @moduledoc false

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Shared

  def valid_candle?(%{open: _, high: _, low: _, close: _}), do: true
  def valid_candle?(c) when is_list(c), do: length(c) >= 4
  def valid_candle?(_), do: false

  def render(state, width, height, bg, _fg) do
    candles = state.data || []

    cond do
      candles == [] -> Shared.empty_strips(height, bg)
      not valid_candle?(hd(candles)) -> Shared.empty_strips(height, bg)
      true -> render_filtered(state, candles, width, height, bg)
    end
  end

  defp render_filtered(state, candles, width, height, bg) do
    filtered_candles = Enum.filter(candles, &valid_candle?/1)
    scroll_offset = state._internal.scroll_offset || 0
    y_offset = state._internal.y_offset || 0
    label_width = 11
    viewport_width = max(1, width - label_width)
    {start_index, display_candles} =
      Drafter.ScrollMath.end_anchored_slice(filtered_candles, scroll_offset, viewport_width)

    if display_candles == [] do
      Shared.empty_strips(height, bg)
    else
      render_display(display_candles, start_index, height, y_offset, bg)
    end
  end

  defp render_display(display_candles, start_index, height, y_offset, bg) do
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
      render_body(display_candles, height - 1, min_val, max_val, bull_color, bear_color, label_color, bg)
    time_strip = render_time_axis(display_candles, start_index, label_color, time_label_color, bg)
    chart_strips ++ [time_strip]
  end

  defp render_body(candles, height, min_val, max_val, bull_color, bear_color, label_color, bg) do
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

  def render_time_axis(display_candles, start_index, label_color, time_color, bg) do
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

  def extract_ohlc(%{open: o, high: h, low: l, close: c}), do: {o, h, l, c}
  def extract_ohlc([o, h, l, c | _]), do: {o, h, l, c}

  def format_price_label(price) do
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
end
