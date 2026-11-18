Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}])

defmodule Tasks do
  alias Drafter.Prompt

  def run(tasks \\ []) do
    menu = [
      {"Add a task", :add},
      [label: "Finish tasks", value: :finish, disabled: tasks == []],
      [label: "List tasks", value: :list, hint: "#{length(tasks)} open"],
      {"Quit", :quit}
    ]

    case Prompt.select("Tasks", menu) do
      {:ok, :quit} -> Prompt.say(:info, "#{length(tasks)} tasks left open")
      {:ok, action} -> tasks |> act(action) |> run()
      {:error, _reason} -> :ok
    end
  end

  defp act(tasks, :add) do
    case Prompt.text("What needs doing?", validate: &named/1) do
      {:ok, task} -> tasks ++ [task]
      {:error, _reason} -> tasks
    end
  end

  defp act(tasks, :finish) do
    case Prompt.multiselect("Which are done?", tasks, filter: true) do
      {:ok, done} ->
        Prompt.say(:success, "Finished #{length(done)}")
        tasks -- done

      {:error, _reason} ->
        tasks
    end
  end

  defp act(tasks, :list) do
    Enum.each(tasks, &Prompt.say(:info, &1))
    tasks
  end

  defp named(""), do: {:error, "A task needs a name."}
  defp named(_task), do: :ok
end

Tasks.run()
