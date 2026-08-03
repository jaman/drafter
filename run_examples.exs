Mix.install(
  [
    {:drafter, path: "."},
    {:french_curve, github: "jaman/french_curve"},
    {:elixir_make, "~> 0.9"},
    {:spark, "~> 2.6"}
  ], consolidate_protocols: false)

defmodule ExamplesLauncher do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    groups =
      Path.wildcard(Path.join(__DIR__, "examples/**/*.exs"))
      |> Enum.sort()
      |> Enum.group_by(&style_of/1, fn path -> {humanize(Path.basename(path, ".exs")), path} end)
      |> Enum.sort_by(fn {style, _examples} -> style end)
      |> Enum.map(fn {style, examples} ->
        %{id: :"#{style}_examples", title: String.capitalize(style), examples: examples}
      end)

    %{groups: groups}
  end

  def keybindings do
    [{"↑↓", "navigate"}, {"←→", "switch style"}, {"Enter", "run"}, {"q", "quit"}]
  end

  def render(state) do
    vertical([
      header("Drafter — Example Gallery"),
      horizontal(Enum.map(state.groups, &example_column/1), flex: 1),
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

  defp example_column(group) do
    box(
      [
        option_list(group.examples,
          id: group.id,
          on_select: :run_example,
          trigger: :mouse_up,
          expand_height: :fill,
          flex: 1
        )
      ],
      title: group.title,
      flex: 1
    )
  end

  defp style_of(path), do: path |> Path.dirname() |> Path.basename()

  defp humanize(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp eval_example(path) do
    IEx.Helpers.recompile()

    path
    |> File.read!()
    |> Code.string_to_quoted!(file: path)
    |> drop_mix_install()
    |> Code.eval_quoted([], file: path)
  rescue
    e -> IO.puts("\nExample error: #{Exception.message(e)}")
  end

  defp drop_mix_install({:__block__, meta, expressions}) do
    {:__block__, meta, Enum.reject(expressions, &mix_install?/1)}
  end

  defp drop_mix_install(expression) do
    if mix_install?(expression), do: {:__block__, [], []}, else: expression
  end

  defp mix_install?({{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, _}), do: true
  defp mix_install?(_expression), do: false
end

Drafter.run(ExamplesLauncher, syntax_highlighting: true)
