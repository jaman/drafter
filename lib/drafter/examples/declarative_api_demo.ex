defmodule Drafter.Examples.DeclarativeApiDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    line_data = for i <- 0..199 do
      x = i * 0.1
      :math.sin(x) * 30 + 50 + :math.cos(x * 2) * 20 + :rand.uniform() * 5
    end

    area_data = for i <- 0..199 do
      x = i * 0.05
      :math.cos(x) * 40 + 60 + :rand.uniform() * 8
    end

    bar_data = for _i <- 0..99 do
      30 + :rand.uniform(70)
    end

    scatter_data = for _ <- 0..149 do
      {:rand.uniform(100), :rand.uniform(100)}
    end

    candlestick_data = Enum.reduce(1..100, {[], 50.0}, fn _i, {candles, last_close} ->
      open = last_close
      close = max(10, min(90, last_close + (:rand.uniform() - 0.5) * 10))
      high = max(open, close) + :rand.uniform() * 5
      low = min(open, close) - :rand.uniform() * 5

      candle = %{open: open, high: high, low: low, close: close}
      {[candle | candles], close}
    end) |> elem(0) |> Enum.reverse()

    %{
      line_data: line_data,
      area_data: area_data,
      bar_data: bar_data,
      scatter_data: scatter_data,
      candlestick_data: candlestick_data
    }
  end

  def render(state) do
    vertical([
      header("Declarative Widget API Demo", show_clock: true),
      scrollable(
        [
          label("Declarative Widget Event Handling API", style: %{fg: {100, 150, 255}, bold: true}),
          label(""),
          label("Chart widget declared with:", style: %{fg: {200, 200, 200}}),
          label("  use Drafter.Widget, handles: [:scroll, :keyboard], focusable: true",
            style: %{fg: {120, 120, 120}}
          ),
          label(""),
          label("Framework automatically:", style: %{fg: {200, 200, 200}}),
          label("  • Registers as focusable widget", style: %{fg: {120, 120, 120}}),
          label("  • Routes scroll events to handle_scroll/2", style: %{fg: {120, 120, 120}}),
          label("  • Routes keyboard to handle_key/2", style: %{fg: {120, 120, 120}}),
          label("  • Manages focus state automatically", style: %{fg: {120, 120, 120}}),
          label(""),
          label("Try it: Tab to focus charts, then use arrow keys or mouse wheel",
            style: %{fg: {255, 184, 108}, bold: true}
          ),
          label("Watch the chart data shift left/right as you scroll!",
            style: %{fg: {255, 184, 108}}
          ),
          label(""),
          label("Line Chart (200 data points):", style: %{fg: {100, 150, 255}}),
          vertical(
            [
              chart(
                state.line_data,
                chart_type: :line,
                height: 8,
                color: {100, 200, 255}
              )
            ],
            width: 60
          ),
          label(""),
          label("Area Chart (200 data points):", style: %{fg: {120, 200, 150}}),
          vertical(
            [
              chart(
                state.area_data,
                chart_type: :area,
                height: 8,
                color: {120, 200, 150}
              )
            ],
            width: 60
          ),
          label(""),
          label("Bar Chart (100 bars):", style: %{fg: {255, 180, 100}}),
          vertical(
            [
              chart(
                state.bar_data,
                chart_type: :bar,
                height: 8,
                color: {255, 180, 100}
              )
            ],
            width: 60
          ),
          label(""),
          label("Scatter Plot (150 points):", style: %{fg: {255, 120, 200}}),
          vertical(
            [
              chart(
                state.scatter_data,
                chart_type: :scatter,
                height: 8,
                color: {255, 120, 200}
              )
            ],
            width: 60
          ),
          label(""),
          label("Candlestick Chart (100 candles):", style: %{fg: {200, 100, 255}}),
          vertical(
            [
              chart(
                state.candlestick_data,
                chart_type: :candlestick,
                height: 24,
                color: {200, 100, 255}
              )
            ],
            width: 60
          ),
          label(""),
          label("All charts support scrolling with mouse wheel and arrow keys",
            style: %{fg: {120, 120, 120}}
          ),
          label("Benefits: 70% less boilerplate, clear intent, type-safe callbacks",
            style: %{fg: {120, 120, 120}}
          )
        ],
        flex: 1
      ),
      footer(bindings: [{"Ctrl+Q", "Quit"}, {"Tab", "Focus"}, {"Arrow Keys", "Scroll Chart"}])
    ])
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
