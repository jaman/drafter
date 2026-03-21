Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule Charts do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    data = generate_wave_data(300)
    candlestick_data = generate_forex_candlestick_data(200)
    [_open, _high, _low, close] = List.last(candlestick_data)

    %{
      data: data,
      candlestick_data: candlestick_data,
      timestamp: 0,
      current_candle: %{
        open: close,
        high: close,
        low: close,
        close: close,
        updates: 0,
        target_updates: :rand.uniform(11) + 9
      }
    }
  end

  def keybindings, do: [{"q", "quit"}, {"r", "regenerate"}]

  def on_ready(state) do
    Drafter.set_interval(100, :tick)
    state
  end

  def on_timer(:tick, state) do
    candle = state.current_candle
    trend = if :rand.uniform() > 0.50, do: 1, else: -1
    tick = (:rand.uniform() * 2 + 0.5) * 0.0001
    new_close = Float.round(candle.close + trend * tick, 4)
    new_high = max(candle.high, new_close)
    new_low = min(candle.low, new_close)
    new_updates = candle.updates + 1

    if new_updates >= candle.target_updates do
      finalized = [candle.open, new_high, new_low, new_close]

      %{
        state
        | timestamp: state.timestamp + 1,
          candlestick_data: state.candlestick_data ++ [finalized],
          current_candle: %{
            open: new_close,
            high: new_close,
            low: new_close,
            close: new_close,
            updates: 0,
            target_updates: :rand.uniform(11) + 9
          }
      }
    else
      %{
        state
        | timestamp: state.timestamp + 1,
          current_candle: %{
            candle
            | close: new_close,
              high: new_high,
              low: new_low,
              updates: new_updates
          }
      }
    end
  end

  def render(state) do
    live_candle = [
      state.current_candle.open,
      state.current_candle.high,
      state.current_candle.low,
      state.current_candle.close
    ]

    vertical([
      header("Chart Demo", show_clock: true),
      scrollable(
        [
          label("Line Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            chart_type: :line,
            height: 6,
            color: {100, 200, 255},
            animated: true,
            animation_speed: 150,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Bar Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(Enum.take(state.data, 40), chart_type: :bar, height: 1, color: {80, 250, 123}),
          label(""),
          label("Area Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            chart_type: :area,
            height: 5,
            color: {255, 121, 198},
            animated: true,
            animation_speed: 100,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Candlestick Chart (EUR/USD - Live)", style: %{fg: {100, 150, 255}, bold: true}),
          label("Green = Bullish, Red = Bearish | Rightmost candle builds in real-time",
            style: %{fg: {120, 120, 120}}
          ),
          chart(state.candlestick_data ++ [live_candle],
            chart_type: :candlestick,
            height: 40,
            animated: true,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Scatter Plot", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data, chart_type: :scatter, height: 5, color: {255, 184, 108}),
          label("")
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event({:key, :r}, state) do
    new_data = generate_wave_data(300)
    new_candlesticks = generate_forex_candlestick_data(200)
    [_open, _high, _low, close] = List.last(new_candlesticks)

    {:ok,
     %{
       state
       | data: new_data,
         candlestick_data: new_candlesticks,
         current_candle: %{
           open: close,
           high: close,
           low: close,
           close: close,
           updates: 0,
           target_updates: :rand.uniform(11) + 9
         }
     }}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp generate_wave_data(count) do
    for i <- 0..(count - 1) do
      x = i * 0.2
      :math.sin(x) * 30 + 50 + :math.sin(x * 3) * 15 + :rand.uniform() * 5
    end
  end

  defp generate_forex_candlestick_data(count) do
    Enum.reduce(1..count, {1.1250, []}, fn _i, {prev_close, acc} ->
      mean_reversion = (1.1250 - prev_close) * 0.01
      trend = if :rand.uniform() > 0.50, do: 1, else: -1
      body_size = :rand.uniform() * 0.0015
      change = trend * body_size + mean_reversion

      open = prev_close
      close = Float.round(open + change, 4)

      upper_wick = abs(change) * (:rand.uniform() * 0.4 + 0.15)
      lower_wick = abs(change) * (:rand.uniform() * 0.4 + 0.15)

      high = Float.round(max(open, close) + upper_wick, 4)
      low = Float.round(min(open, close) - lower_wick, 4)

      {close, [[open, high, low, close] | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end

Drafter.run(Charts)
