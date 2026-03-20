Mix.install([{:drafter, path: "."}])

defmodule ExamplesLauncher do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    examples =
      Path.wildcard(Path.join(__DIR__, "examples/*.exs"))
      |> Enum.sort()
      |> Enum.map(fn path -> {humanize(Path.basename(path, ".exs")), path} end)

    %{examples: examples}
  end

  def keybindings, do: [{"↑↓", "navigate"}, {"Enter", "run"}, {"q", "quit"}]

  def render(state) do
    vertical([
      header("Drafter — Example Gallery"),
      option_list(state.examples, id: :example_list, on_select: :run_example, flex: 1),
      footer()
    ])
  end

  def handle_event(:run_example, path, _state) do
    Application.put_env(:drafter, :__selected_example__, path)
    {:stop, :normal}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp humanize(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

defmodule ExamplesRunner do
  def run do
    Application.delete_env(:drafter, :__selected_example__)
    Drafter.run(ExamplesLauncher)

    case Application.get_env(:drafter, :__selected_example__) do
      nil ->
        :ok

      path ->
        eval_example(path)
        run()
    end
  end

  defp eval_example(path) do
    source =
      File.read!(path)
      |> String.replace(~r/^Mix\.install\(.*\)\n?/m, "")

    Code.eval_string(source, [], file: path)
  rescue
    e -> IO.puts("\nExample error: #{Exception.message(e)}")
  end
end

ExamplesRunner.run()
