Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule SyntaxHighlight do
  use Drafter, runtime: :reducer

  def mount(_props) do
    source = File.read!(__ENV__.file)
    %{source: source}
  end

  keybinding {:q, [:ctrl]}, "quit" do
    {:stop, :normal}
  end

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

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(SyntaxHighlight, syntax_highlighting: true)
