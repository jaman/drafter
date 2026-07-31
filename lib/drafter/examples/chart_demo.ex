defmodule Drafter.Examples.ChartDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    data = generate_wave_data(60)
    candlestick_data = generate_forex_candlestick_data(50)
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

  def on_ready(state) do
    send(self(), {:set_interval, 100, :tick})
    state
  end

  def on_timer(:tick, state) do
    candle = state.current_candle

    trend = if :rand.uniform() > 0.50, do: 1, else: -1
    volatility = candle.close * 0.0005 * (:rand.uniform() + 0.5)
    change = trend * :rand.uniform() * volatility
    new_close = candle.close + change

    new_high = max(candle.high, new_close)
    new_low = min(candle.low, new_close)
    new_updates = candle.updates + 1

    if new_updates >= candle.target_updates do
      finalized_candle = [candle.open, new_high, new_low, new_close]
      new_candlestick_data = state.candlestick_data ++ [finalized_candle]

      %{
        state
        | timestamp: state.timestamp + 1,
          candlestick_data: new_candlestick_data,
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

  def on_timer(_id, state), do: state

  def render(state) do
    vertical([
      header("Chart Widget Demo", show_clock: true),
      scrollable(
        [
          label("Line Chart (Braille - 4x resolution)",
            style: %{fg: {100, 150, 255}, bold: true}
          ),
          chart(state.data,
            chart_type: :line,
            height: 6,
            color: {100, 200, 255},
            animated: true,
            animation_speed: 150,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Bar Chart (Single Row)", style: %{fg: {100, 150, 255}, bold: true}),
          chart(Enum.take(state.data, 40),
            chart_type: :bar,
            height: 1,
            color: {80, 250, 123}
          ),
          label(""),
          label("Area Chart (Animated)", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            chart_type: :area,
            height: 5,
            color: {255, 121, 198},
            animated: true,
            animation_speed: 100,
            _render_timestamp: state.timestamp
          ),
          label(""),
          vertical(
            [
              label("Candlestick Chart (EUR/USD) - Live Simulation",
                style: %{fg: {100, 150, 255}, bold: true}
              ),
              label("Green = Bullish, Red = Bearish | Rightmost candle builds in real-time",
                style: %{fg: {120, 120, 120}}
              ),
              label("Mouse wheel or arrow keys to scroll through history",
                style: %{fg: {120, 120, 120}}
              ),
              chart(
                state.candlestick_data ++
                  [
                    [
                      state.current_candle.open,
                      state.current_candle.high,
                      state.current_candle.low,
                      state.current_candle.close
                    ]
                  ],
                chart_type: :candlestick,
                height: 25,
                animated: true,
                _render_timestamp: state.timestamp
              )
            ],
            width: 40
          ),
          label(""),
          label("Scatter Plot", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            chart_type: :scatter,
            height: 5,
            color: {255, 184, 108}
          ),
          label("")
        ],
        flex: 1
      ),
      footer(bindings: [{"Ctrl+Q", "Quit"}, {"r", "Regenerate"}])
    ])
  end

  def handle_event(%{type: :key, key: :r}, state) do
    new_data = generate_wave_data(60)
    new_candlesticks = generate_forex_candlestick_data(50)
    [_open, _high, _low, close] = List.last(new_candlesticks)

    {:noreply,
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

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp generate_wave_data(count) do
    for i <- 0..(count - 1)//1 do
      x = i * 0.2
      :math.sin(x) * 30 + 50 + :math.sin(x * 3) * 15 + :rand.uniform() * 5
    end
  end

  defp generate_forex_candlestick_data(count) do
    base_price = 1.0850

    Enum.reduce(1..count, {base_price, []}, fn _i, {prev_close, acc} ->
      trend = if :rand.uniform() > 0.50, do: 1, else: -1
      volatility = prev_close * 0.002 * (:rand.uniform() + 0.5)
      change = trend * :rand.uniform() * volatility
      open = prev_close
      close = open + change

      wick_mult = 0.5 + :rand.uniform()
      high = max(open, close) + abs(change) * wick_mult
      low = min(open, close) - abs(change) * wick_mult

      {close, [[open, high, low, close] | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
