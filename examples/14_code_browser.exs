Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}])

defmodule CodeBrowser do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      root: File.cwd!(),
      selected_path: nil,
      hex_view: false
    }
  end

  def keybindings do
    [{"^Q", "quit"}, {"↑↓/Enter", "navigate"}, {"Tab", "switch pane"}]
  end

  def render(state) do
    vertical([
      header("Code Browser — #{state.root}"),
      horizontal(
        [
          directory_tree(
            id: :tree,
            path: state.root,
            on_file_select: :file_selected,
            width: 30,
            flex: 0
          ),
          code_view(
            id: :preview,
            path: state.selected_path,
            source: "",
            show_line_numbers: true,
            hex_view: state.hex_view,
            flex: 1
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:file_selected, path, state) do
    hex_view = binary_file?(path)
    {:ok, %{state | selected_path: path, hex_view: hex_view}}
  end

  defp binary_file?(nil), do: false
  defp binary_file?(path) do
    case File.read(path) do
      {:ok, content} -> not String.valid?(content)
      _ -> false
    end
  end

  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(CodeBrowser, syntax_highlighting: true)
