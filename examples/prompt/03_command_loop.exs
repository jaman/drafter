Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}])

defmodule FileShell do
  alias Drafter.Prompt
  alias Drafter.Prompt.Completion

  def run do
    Prompt.say(:info, "Type help for the commands. Tab completes commands and paths.")
    loop([])
  end

  defp loop(history) do
    case Prompt.readline("files> ", history: history, complete: completion()) do
      {:ok, line} -> line |> String.split() |> execute(line, history)
      {:error, _reason} -> Prompt.say(:info, "Bye")
    end
  end

  defp completion do
    Completion.commands(%{
      "ls" => Completion.paths(only: :directories),
      "cat" => Completion.paths(),
      "help" => [],
      "quit" => []
    })
  end

  defp execute([], _line, history), do: loop(history)
  defp execute(["quit"], _line, _history), do: Prompt.say(:info, "Bye")

  defp execute(["help"], line, history) do
    IO.puts("ls [directory]   list a directory")
    IO.puts("cat file         print a file")
    IO.puts("quit             leave")
    loop([line | history])
  end

  defp execute(["ls" | where], line, history) do
    where
    |> List.first(".")
    |> File.ls()
    |> report(&Enum.each(Enum.sort(&1), fn entry -> IO.puts(entry) end))

    loop([line | history])
  end

  defp execute(["cat", file], line, history) do
    file |> File.read() |> report(&IO.write/1)
    loop([line | history])
  end

  defp execute([command | _arguments], line, history) do
    Prompt.say(:error, "Unknown command: #{command}")
    loop([line | history])
  end

  defp report({:ok, result}, show), do: show.(result)

  defp report({:error, reason}, _show),
    do: Prompt.say(:error, to_string(:file.format_error(reason)))
end

FileShell.run()
