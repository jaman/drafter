Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}])

alias Drafter.Prompt

questions = [
  host: {:text, "Host", default: "localhost"},
  engine: {:select, "Database", ["PostgreSQL", "MySQL", "SQLite"]},
  file: fn
    %{engine: "SQLite"} -> {:text, "Database file", complete: Prompt.Completion.paths()}
    _answers -> :skip
  end,
  port: fn
    %{engine: "PostgreSQL"} -> {:number, "Port", default: 5432}
    %{engine: "MySQL"} -> {:number, "Port", default: 3306}
    _answers -> :skip
  end,
  password: fn
    %{engine: "SQLite"} -> :skip
    _answers -> {:password, "Password"}
  end,
  save: {:confirm, "Save these settings?"}
]

case Prompt.form(questions) do
  {:ok, %{save: true} = settings} ->
    Prompt.say(:success, "Saved #{inspect(Map.drop(settings, [:save, :password]))}")

  {:ok, _settings} ->
    Prompt.say(:info, "Not saved")

  {:error, reason} ->
    Prompt.say(:warning, "Stopped: #{reason}")
end
