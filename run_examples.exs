Mix.install([{:drafter, path: "."}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule ExamplesLauncher do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    examples =
      Path.wildcard(Path.join(__DIR__, "examples/**/*.exs"))
      |> Enum.sort()
      |> Enum.map(fn path -> {label_for(path), path} end)

    %{examples: examples}
  end

  def keybindings, do: [{"↑↓", "navigate"}, {"Enter", "run"}, {"q", "quit"}]

  def render(state) do
    vertical([
      header("Drafter — Example Gallery"),
      option_list(state.examples,
        id: :example_list,
        on_select: :run_example,
        trigger: :mouse_up,
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:run_example, path, state) do
    Task.start(fn -> eval_example(path) end)
    {:ok, state}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp label_for(path) do
    style = path |> Path.dirname() |> Path.basename() |> String.capitalize()
    "#{style}  ·  #{humanize(Path.basename(path, ".exs"))}"
  end

  defp humanize(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp eval_example(path) do
    IEx.Helpers.recompile()

    source =
      File.read!(path)
      |> String.replace(~r/^Mix\.install\(.*\)\n?/m, "")

    Code.eval_string(source, [], file: path)
  rescue
    e -> IO.puts("\nExample error: #{Exception.message(e)}")
  end
end

Drafter.run(ExamplesLauncher, syntax_highlighting: true)
