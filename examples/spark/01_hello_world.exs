Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

# Phoenix-style (flat `use Drafter`): one `use`, no `Drafter.App` namespace, widgets
# are unqualified, and `state/1` declares the initial state instead of `mount/1`.
defmodule HelloWorld do
  use Drafter

  state %{}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def render(_state) do
    vertical([
      header("Hello — Phoenix style (use Drafter)"),
      label(""),
      label("Hello, World!", style: %{bold: true, fg: :cyan}),
      label(""),
      label("Press q to quit."),
      footer()
    ])
  end
end

Drafter.run(HelloWorld)
