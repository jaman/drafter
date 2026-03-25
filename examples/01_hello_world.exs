Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule HelloWorld do
  use Drafter.App
  import Drafter.App

  def mount(_props), do: %{}

  def keybindings, do: [{"q", "quit"}]

  def render(_state) do
    vertical([
      header("Hello, World!"),
      label(""),
      label("你好. Welcome to Drafter! 반갑습니다", style: %{bold: true, fg: :cyan}),
      label(""),
      label("Press q to quit"),
      footer()
    ])
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(HelloWorld)
