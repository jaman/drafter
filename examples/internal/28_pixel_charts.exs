Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule PixelCharts do
  use Drafter.App
  import Drafter.App

  @bars [3, 7, 2, 9, 5, 8, 4, 6]
  @scatter for i <- 0..40, do: [i, :math.sin(i / 4) * 5 + :rand.uniform() * 3]
  @pie [{"Elixir", 45}, {"Rust", 30}, {"Go", 15}, {"Zig", 10}]

  def mount(_props), do: %{t: 0, wave: wave(120, 0), candles: candles()}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def handle_event(_event, state), do: {:noreply, state}

  def on_ready(state) do
    Drafter.set_interval(250, :tick)
    state
  end

  def on_timer(:tick, state), do: %{state | t: state.t + 1, wave: wave(120, state.t * 0.15)}

  def render(state) do
    vertical([
      label("Pixel charts — best available per terminal (iTerm2/kitty/sixel → braille). q to quit",
        style: %{bold: true}
      ),
      horizontal([
        box([chart(state.wave, chart_type: :line, renderer: :pixel, color: {120, 200, 255}, smooth: true)],
          title: "Line (live)",
          flex: 1
        ),
        box([chart(@bars, chart_type: :bar, renderer: :pixel, color: {255, 180, 80})],
          title: "Bar",
          flex: 1
        ),
        box([chart(@scatter, chart_type: :scatter, renderer: :pixel, color: {120, 255, 150})],
          title: "Scatter",
          flex: 1
        )
      ]),
      horizontal([
        box([chart(state.candles, chart_type: :candlestick, renderer: :pixel)], title: "Candlestick", flex: 1),
        box([chart(state.wave, chart_type: :area, renderer: :pixel, color: {255, 120, 180}, smooth: true)],
          title: "Area (live)",
          flex: 1
        ),
        box([pie_chart(@pie, renderer: :pixel)], title: "Pie", flex: 1)
      ])
    ])
  end

  defp candles do
    {candles, _} =
      Enum.reduce(1..18, {[], 50.0}, fn _, {acc, prev_close} ->
        open = prev_close
        close = open + (:rand.uniform() - 0.5) * 9
        high = max(open, close) + :rand.uniform() * 3
        low = min(open, close) - :rand.uniform() * 3
        {[[open, high, low, close] | acc], close}
      end)

    Enum.reverse(candles)
  end

  defp wave(n, phase) do
    for i <- 0..(n - 1) do
      x = i / 6.0 + phase
      :math.sin(x) + :math.sin(x * 0.5) * 0.6 + :math.sin(x * 0.23) * 0.3
    end
  end
end

Drafter.run(PixelCharts)
