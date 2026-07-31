Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

# Elm-style timer: `on_ready` arms a recurring timer; each tick is delivered to `update/2`
# as `{:timer, id}`, just like every other message. Pure transitions, one handler.
defmodule Ticker do
  use Drafter, runtime: :reducer

  state %{ticks: 0}

  def on_ready(state) do
    Drafter.set_interval(1000, :tick)
    state
  end

  def render(state) do
    vertical([
      header("Ticker — Elm/reducer style"),
      label(""),
      label("Ticks: #{state.ticks}", style: %{bold: true, fg: :cyan}),
      label(""),
      label("A timer message flows through update/2 like any other. Press q to quit."),
      footer()
    ])
  end

  def update({:timer, :tick}, state), do: %{state | ticks: state.ticks + 1}
  def update({:key, :q}, _state), do: {:stop, :normal}
  def update(_msg, state), do: state
end

Drafter.run(Ticker)
