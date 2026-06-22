Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

# Elm-style text input. `bind:` keeps `state.name` in sync as you type; `on_submit:`
# sends a `:greet` message, which (like everything) lands in `update/2`.
defmodule Form do
  use Drafter, runtime: :reducer

  state %{name: "", greeting: "Type a name and press Enter."}

  def render(state) do
    vertical([
      header("Form — Elm/reducer style"),
      label(""),
      text_input(id: :name, placeholder: "Your name...", bind: :name, on_submit: :greet),
      label(""),
      label(state.greeting, style: %{fg: :cyan}),
      footer(bindings: [{"Enter", "greet"}, {"Tab", "focus"}, {"q", "quit"}])
    ])
  end

  def update({:greet, _data}, state) do
    case String.trim(state.name) do
      "" -> %{state | greeting: "Type a name and press Enter."}
      name -> %{state | greeting: "Hello, #{name}!"}
    end
  end

  def update({:key, :q}, _state), do: {:stop, :normal}
  def update(_msg, state), do: state
end

Drafter.run(Form)
