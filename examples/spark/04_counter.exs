Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

# Phoenix-style counter: declarative `state`, named callbacks via `handle_event/3`
# (the button `on_click:` name is dispatched to the matching clause).
defmodule Counter do
  use Drafter

  state %{count: 0}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def render(state) do
    vertical([
      header("Counter — Phoenix style"),
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
      footer()
    ])
  end

  def handle_event(:increment, _data, state), do: {:ok, %{state | count: state.count + 1}}
  def handle_event(:decrement, _data, state), do: {:ok, %{state | count: state.count - 1}}
  def handle_event(_event, _data, state), do: {:noreply, state}
end

Drafter.run(Counter)
