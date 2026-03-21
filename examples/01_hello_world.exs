Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule HelloWorld do
  use Drafter.App
  import Drafter.App

  def mount(_props), do: %{}

  def keybindings, do: [{"q", "quit"}]

  def render(_state) do
    vertical([
      header("Hello, World!"),
      label(""),
      label("Welcome to Drafter!", style: %{bold: true, fg: :cyan}),
      label(""),
      label("Press q to quit"),
      footer()
    ])
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(HelloWorld)
