Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

# Elm-style counter: `runtime: :reducer`. There is one message handler, `update/2`.
# Every message — named callbacks (button `on_click:`), key events, timers — flows through
# it. `update/2` returns the new state, or `{:stop, reason}` to quit. A named callback
# arrives as `{name, data}`; a key event arrives as its `{:key, _}` tuple.
defmodule Counter do
  use Drafter, runtime: :reducer

  state %{count: 0}

  def render(state) do
    vertical([
      header("Counter — Elm/reducer style"),
      label(""),
      label("Count: #{state.count}", style: %{bold: true, fg: :cyan}),
      label(""),
      horizontal(
        [
          button("Decrement", on_click: :decrement),
          button("Increment", on_click: :increment, variant: :primary)
        ],
        gap: 2
      ),
      label(""),
      label("Press q to quit."),
      footer()
    ])
  end

  def update({:increment, _data}, state), do: %{state | count: state.count + 1}
  def update({:decrement, _data}, state), do: %{state | count: state.count - 1}
  def update({:key, :q}, _state), do: {:stop, :normal}
  def update(_msg, state), do: state
end

Drafter.run(Counter)
