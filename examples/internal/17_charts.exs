Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule Charts do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    data = generate_wave_data(300)
    candlestick_data = generate_forex_candlestick_data(200)
    [_open, _high, _low, close] = List.last(candlestick_data)

    %{
      data: data,
      scope_data: generate_scope_data(200, 0),
      renderer: :auto,
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

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :m, "render mode" do
    {:ok, %{state | renderer: next_renderer(state.renderer)}}
  end

  keybinding :r, "regenerate" do
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
          scope_data: generate_scope_data(200, state.timestamp + 1),
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
          scope_data: generate_scope_data(200, state.timestamp + 1),
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
          mode_label(state.renderer),
          label(""),
          label("Line Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            renderer: state.renderer,
            chart_type: :line,
            height: 6,
            color: {100, 200, 255},
            animated: true,
            animation_speed: 150,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Smooth Line Chart (Catmull-Rom, thickness: 2)", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            renderer: state.renderer,
            chart_type: :line,
            height: 6,
            color: {80, 255, 180},
            smooth: true,
            line_thickness: 2,
            animated: true,
            animation_speed: 150,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Oscilloscope (multi-series, smooth, connected)", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.scope_data,
            renderer: state.renderer,
            chart_type: :line,
            height: 10,
            smooth: true,
            line_thickness: 2,
            connect_lines: true,
            colors: [{0, 255, 120}, {255, 220, 0}, {0, 180, 255}, {255, 80, 200}],
            min_value: -1.5,
            max_value: 1.5,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Bar Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(Enum.take(state.data, 40), renderer: state.renderer, chart_type: :bar, height: 1, color: {80, 250, 123}),
          label(""),
          label("Area Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            renderer: state.renderer,
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
            renderer: state.renderer,
            chart_type: :candlestick,
            height: 40,
            animated: true,
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Scatter Plot", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data, renderer: state.renderer, chart_type: :scatter, height: 5, color: {255, 184, 108}),
          label(""),
          label("Step Plot", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data,
            renderer: state.renderer,
            chart_type: :step,
            height: 6,
            color: {180, 255, 100},
            _render_timestamp: state.timestamp
          ),
          label(""),
          label("Histogram", style: %{fg: {100, 150, 255}, bold: true}),
          chart(state.data, renderer: state.renderer, chart_type: :histogram, height: 6, color: {100, 200, 180}),
          label(""),
          label("Heatmap", style: %{fg: {100, 150, 255}, bold: true}),
          chart(generate_heatmap_data(),
            renderer: state.renderer,
            chart_type: :heatmap,
            height: 8
          ),
          label(""),
          label("Bubble Chart", style: %{fg: {100, 150, 255}, bold: true}),
          chart(generate_bubble_data(),
            renderer: state.renderer,
            chart_type: :bubble,
            height: 6,
            color: {200, 150, 255}
          ),
          label(""),
          label("Pie Charts", style: %{fg: {100, 150, 255}, bold: true}),
          horizontal(
            [
              pie_chart(
                [
                  {"Electronics", 34.2},
                  {"Clothing", 22.8},
                  {"Food & Bev", 18.5},
                  {"Home", 12.1},
                  {"Sports", 7.9},
                  {"Other", 4.5}
                ],
                renderer: state.renderer,
                show_legend: true,
                show_percentages: true
              ),
              pie_chart(
                [
                  {"Elixir", 42, {148, 94, 207}},
                  {"Rust", 28, {222, 110, 55}},
                  {"Go", 18, {0, 173, 216}},
                  {"Python", 12, {55, 118, 171}}
                ],
                renderer: state.renderer,
                show_legend: true,
                show_percentages: true
              )
            ],
            gap: 2
          ),
          label("")
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp next_renderer(:auto), do: :braille
  defp next_renderer(:braille), do: :text
  defp next_renderer(_renderer), do: :auto

  defp mode_label(renderer) do
    resolved = Drafter.Widget.Chart.Pixel.mode(renderer, :line)

    label("Render mode: #{renderer} (resolved: #{resolved}) — press m to cycle",
      style: %{fg: {255, 200, 100}, bold: true}
    )
  end

  defp generate_wave_data(count) do
    for i <- 0..(count - 1) do
      x = i * 0.2
      :math.sin(x) * 30 + 50 + :math.sin(x * 3) * 15 + :rand.uniform() * 5
    end
  end

  defp generate_scope_data(count, phase) do
    phase_shift = phase * 0.08

    sine =
      for i <- 0..(count - 1) do
        x = i * 0.12 + phase_shift
        :math.sin(x)
      end

    square =
      for i <- 0..(count - 1) do
        x = i * 0.12 + phase_shift
        if :math.sin(x * 0.7) >= 0, do: 0.7, else: -0.7
      end

    triangle =
      for i <- 0..(count - 1) do
        x = i * 0.12 + phase_shift * 1.3
        2.0 / :math.pi() * :math.asin(:math.sin(x * 0.9)) * 0.8
      end

    harmonic =
      for i <- 0..(count - 1) do
        x = i * 0.12 + phase_shift * 0.8
        (:math.sin(x * 2) + :math.sin(x * 5) * 0.3) * 0.5
      end

    [sine, square, triangle, harmonic]
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

  defp generate_heatmap_data do
    for y <- 0..29 do
      for x <- 0..119 do
        :math.sin(x * 0.08 + y * 0.05) * :math.cos(y * 0.12 - x * 0.03) * 50 + 50 + :rand.uniform() * 5
      end
    end
  end

  defp generate_bubble_data do
    for _ <- 1..30 do
      {:rand.uniform() * 100, :rand.uniform() * 100, :rand.uniform() * 20 + 2}
    end
  end
end

Drafter.run(Charts)
