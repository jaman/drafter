Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule SyntaxHighlight do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    source = File.read!(__ENV__.file)
    %{source: source}
  end

  def keybindings,
    do: [{"^Q", "quit"}, {"↑↓", "scroll"}, {"←→", "h-scroll"}, {"PgUp/PgDn", "page"}]

  def render(state) do
    vertical([
      header("Syntax Highlight — viewing own source"),
      code_view(
        source: state.source,
        language: :exs,
        show_line_numbers: true,
        height: :auto,
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(SyntaxHighlight, syntax_highlighting: true)
