Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}])

alias Drafter.Prompt

valid_name = fn name ->
  if name =~ ~r/^[a-z][a-z0-9_]*$/,
    do: :ok,
    else: {:error, "Use lower case letters, digits and underscores, starting with a letter."}
end

templates = [
  [label: "Phoenix", value: :phoenix, hint: "web application"],
  [label: "Escript", value: :escript, hint: "command-line tool"],
  [label: "Library", value: :library, hint: "published to Hex"],
  [label: "Nerves", value: :nerves, hint: "needs a board", disabled: true]
]

with {:ok, name} <- Prompt.text("Project name", default: "my_app", validate: valid_name),
     {:ok, template} <- Prompt.select("Template", templates),
     {:ok, extras} <-
       Prompt.multiselect("Extras", ["Credo", "Dialyxir", "ExDoc"], default: ["Credo"]),
     {:ok, port} <- Prompt.number("Port", default: 4000, min: 1, max: 65_535),
     {:ok, true} <- Prompt.confirm("Create #{name}?") do
  Prompt.spinner("Resolving dependencies", fn status ->
    Process.sleep(700)
    IO.puts("resolved #{length(extras) + 3} packages")
    status.("Fetching dependencies")
    Process.sleep(700)
  end)

  files = ["mix.exs", "README.md", "lib/#{name}.ex", "test/#{name}_test.exs", "config/config.exs"]

  Prompt.progress("Writing files", files, fn file ->
    Process.sleep(250)
    file
  end)

  Prompt.say(:success, "Created #{name} from the #{template} template, listening on #{port}")
else
  {:ok, false} -> Prompt.say(:info, "Nothing was created")
  {:error, reason} -> Prompt.say(:warning, "Stopped: #{reason}")
end
