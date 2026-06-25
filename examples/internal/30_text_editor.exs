Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule TextEditor do
  use Drafter.App
  import Drafter.App

  @sample """
  defmodule Sample.Pipeline do
    @moduledoc "A few long lines so you can test horizontal scrolling past the right edge."

    def run(items) do
      items
      |> Enum.filter(fn item -> item.active? and item.score > 0 and not item.archived end)
      |> Enum.map(fn item -> %{id: item.id, label: String.upcase(item.label), score: item.score * 1.5} end)
      |> Enum.sort_by(& &1.score, :desc)
    end

    # A short comment, then a deliberately very long single line to scroll through ----------------------------------------> end here
    def describe(%{id: id, label: label, score: score}), do: "item " <> to_string(id) <> " " <> label <> " = " <> to_string(score)
  end
  """

  def mount(_props) do
    %{}
  end

  def render(_state) do
    vertical([
      header("Drafter — Text Editor"),
      text_area(
        id: :editor,
        text: @sample,
        language: :elixir,
        focused: true,
        show_line_numbers: true,
        highlight_cursor_line: true,
        tab_behavior: :indent,
        tab_size: 2,
        height: 22
      ),
      footer()
    ])
  end

  def keybindings do
    [
      {"type", "edit"},
      {"←→↑↓", "move"},
      {"Home/End", "line"},
      {"Ctrl+←→", "word"},
      {"Ctrl+Z/Y", "undo/redo"},
      {"Ctrl+Q", "quit"}
    ]
  end

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(TextEditor)
