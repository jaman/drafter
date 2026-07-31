Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule Counter do
  use Drafter.App
  import Drafter.App

  def mount(_props), do: %{count: 0}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def render(state) do
    vertical([
      header("Counter Example"),
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
  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(Counter)
