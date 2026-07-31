Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule StackedArea do
  use Drafter.App
  import Drafter.App

  @colors [{120, 200, 255}, {255, 150, 80}, {120, 230, 150}]

  def mount(_props), do: %{t: 0, series: series(0)}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def handle_event(_event, state), do: {:noreply, state}

  def on_ready(state) do
    Drafter.set_interval(250, :tick)
    state
  end

  def on_timer(:tick, state), do: %{state | t: state.t + 1, series: series(state.t * 0.15)}

  def render(state) do
    vertical([
      label("Stacked area chart (pixel) — three series accumulate. q to quit",
        style: %{bold: true}
      ),
      box(
        [chart(state.series, chart_type: :stacked_area, renderer: :pixel, colors: @colors)],
        title: "Traffic by region",
        flex: 1
      )
    ])
  end

  defp series(phase) do
    for offset <- [0.0, 1.3, 2.6] do
      for i <- 0..59 do
        base = :math.sin(i / 9.0 + phase + offset) * 12 + 20
        max(2.0, base + :rand.uniform() * 4)
      end
    end
  end
end

Drafter.run(StackedArea)
