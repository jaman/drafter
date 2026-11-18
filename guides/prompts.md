# Command-Line Prompts

`Drafter.Prompt` is for command-line tools that ask a few questions and get on with
their work. It draws below the shell prompt, in the lines the program is already
printing to. There is no alternate screen, no app module and no widget tree: a
question is one function call that returns the answer.

```elixir
alias Drafter.Prompt

with {:ok, name} <- Prompt.text("Project name", default: "my_app"),
     {:ok, kind} <- Prompt.select("Template", ["Phoenix", "Escript", "Library"]),
     {:ok, extras} <- Prompt.multiselect("Extras", ["Credo", "Dialyxir", "ExDoc"]),
     {:ok, true} <- Prompt.confirm("Create it?") do
  Prompt.spinner("Creating #{name}", fn -> create(name, kind, extras) end)
end
```

Each answered question shrinks to one line, so the terminal ends up holding a record
of what was asked:

```
✔ Project name · my_app
✔ Template · Escript
✔ Extras · Credo, ExDoc
✔ Create it? · Yes
✔ Creating my_app
```

Use it from an escript, a Mix task, or a script run with `elixir` or `mix run`. The
`:drafter` application must be started, which it is in all of those.

## The questions

| Function | Asks for | Returns |
|---|---|---|
| `text/2` | one line of text | the string |
| `password/2` | a secret, shown as `*` | the string |
| `number/2` | a number, with `:min`, `:max`, `:float` | an integer or float |
| `confirm/2` | yes or no | a boolean |
| `select/3` | one entry of a list | the entry's value |
| `multiselect/3` | any number of entries | the values, in list order |
| `search/3` | one entry of a list that depends on what is typed | the entry's value |
| `readline/2` | a bare line, as a shell reads one | the string |

Every one returns `{:ok, value}` or `{:error, reason}`:

| Reason | Meaning |
|---|---|
| `:cancelled` | Esc |
| `:interrupted` | Ctrl+C |
| `:eof` | Ctrl+D on an empty line, or standard input ended |
| `:not_a_terminal` | no terminal, and the prompt cannot be answered by a line of input |

Each also has a `!` twin (`text!/2`, `select!/3`, …) that returns the value and raises
`Drafter.Prompt.Stopped` otherwise. The tagged form suits `with`; the `!` form suits a
short script where stopping should end the program.

### Text

```elixir
Prompt.text("Project name",
  default: "my_app",
  placeholder: "lower_case_name",
  validate: fn name ->
    if name =~ ~r/^[a-z][a-z0-9_]*$/, do: :ok, else: {:error, "Lower case, digits, underscores."}
  end
)
```

A line that `:validate` rejects stays open with the message under it. The line has
the usual editing keys: arrows, Home and End, Ctrl+A and Ctrl+E, word movement with
Ctrl or Alt and an arrow, Ctrl+W, Ctrl+U and Ctrl+K to cut, Ctrl+Y to put the cut text
back. Pasted text goes in as typed text. `Drafter.Prompt.Editor` lists them all.

### Lists

An entry is a string, an atom or number, a `{label, value}` pair, or a keyword list
with `:label` and optionally `:value`, `:hint` and `:disabled`:

```elixir
Prompt.select("Template", [
  "Phoenix",
  {"Command-line tool", :escript},
  [label: "Nerves", value: :nerves, hint: "needs a board", disabled: true]
])
```

`filter: true` narrows the list as the user types. `limit:` sets how many entries
show at once; longer lists scroll, with a line saying which entries are visible.
`default:` is the entry highlighted first, or for `multiselect/3` the entries picked
first. `multiselect/3` also takes `min:` and `max:`.

`search/3` takes a function in place of the list. It is called with the typed text
and returns the entries to show:

```elixir
Prompt.search("Package", fn query -> MyHex.search(query) end)
```

The function runs in the calling process on every keystroke, so it should answer
quickly.

## Tab completion

`text/2` and `readline/2` take `complete:`. A list of words completes the word being
typed:

```elixir
Prompt.text("Branch", complete: ["main", "develop", "release"])
```

A function receives the text before the cursor and returns the candidates for the
word being typed. `Drafter.Prompt.Completion` has two ready-made ones:

```elixir
Prompt.text("Config file", complete: Completion.paths())

Prompt.readline("files> ",
  complete:
    Completion.commands(%{
      "ls" => Completion.paths(only: :directories),
      "cat" => Completion.paths(),
      "quit" => []
    })
)
```

One candidate is inserted. Several are listed under the line and the line is
completed as far as they agree; Tab and Shift+Tab then step through them, Enter keeps
the highlighted one, and Esc closes the list.

## A command loop

`readline/2` draws only the prompt string and the line, and leaves both on screen as
typed. With `history:` it recalls earlier lines on Up and Down. A command loop is a
function that calls itself with the history:

```elixir
def loop(history) do
  case Prompt.readline("db> ", history: history, complete: ["select", "insert", "quit"]) do
    {:ok, "quit"} ->
      :ok

    {:ok, line} ->
      run(line)
      loop([line | history])

    {:error, _reason} ->
      :ok
  end
end
```

`examples/prompt/03_command_loop.exs` is a complete one.

## A menu

A menu is `select/3` in a function that calls itself. The entries can change between
rounds, since the list is built on each call:

```elixir
def menu(tasks) do
  entries = [
    {"Add a task", :add},
    [label: "Finish tasks", value: :finish, disabled: tasks == []],
    {"Quit", :quit}
  ]

  case Prompt.select("Tasks", entries) do
    {:ok, :quit} -> :ok
    {:ok, action} -> tasks |> act(action) |> menu()
    {:error, _reason} -> :ok
  end
end
```

`examples/prompt/04_menu.exs` is a complete one.

## Forms

`form/1` asks a list of questions and returns the answers as a map. Each entry names a
question function and its arguments. An entry can be a function of the answers so
far, which lets a later question depend on an earlier one or be left out:

```elixir
Prompt.form(
  name: {:text, "Project name", default: "my_app"},
  kind: {:select, "Template", ["Phoenix", "Escript"]},
  port: fn
    %{kind: "Phoenix"} -> {:number, "Port", default: 4000}
    _answers -> :skip
  end,
  go: {:confirm, "Create it?"}
)
#=> {:ok, %{name: "my_app", kind: "Phoenix", port: 4000, go: true}}
```

The first question that ends without an answer ends the form with its error.

## Spinners and progress bars

`spinner/3` and `progress/4` show a moving line while a function runs, and return
what the function returns. The function runs in the calling process.

```elixir
Prompt.spinner("Fetching dependencies", fn -> fetch() end)

Prompt.spinner("Building", fn status ->
  compile()
  status.("Linking")
  link()
end)

Prompt.progress("Resizing", images, fn image -> resize(image) end)

Prompt.progress("Downloading", total_bytes, fn advance ->
  download(fn chunk -> advance.(byte_size(chunk)) end)
end)
```

Anything the function writes to standard output appears above the moving line, so
`IO.puts/1` inside a step is safe. The line ends with a done mark, or with a failed
mark if the function raises, exits or throws; the error then continues to the caller.

Output written by other processes, and by `Logger`, goes straight to the terminal and
is not moved above the line.

`say/2` writes a status line in the same look:

```elixir
Prompt.say(:success, "Created my_app")
Prompt.say(:warning, "No tests found")
```

## Without a terminal

When standard input is not a terminal, or `TERM` is `dumb`, nothing is drawn. Each
question is written as a line and answered by a line of standard input:

```bash
printf 'my_app\n2\n1,3\ny\n' | my_tool new
```

```
Project name (my_app):
Template
  1) Phoenix
  2) Escript
  3) Library
Number [1]:
Extras
  1) Credo
  2) Dialyxir
  3) ExDoc
Numbers, separated by commas:
Create it? [Y/n]:
```

A list is answered by the number of an entry, several by numbers separated by commas,
a yes or no question by `y` or `n`, and an empty line gives the default. A line the
question rejects is asked for again. Spinners and progress bars write only their final
line.

## Testing

`Drafter.Prompt.Script.run/3` runs code that asks questions against a list of keys,
with no terminal, and returns the result with the lines the prompts left behind:

```elixir
test "the wizard returns what was chosen" do
  {result, transcript} =
    Drafter.Prompt.Script.run(["ada", :enter, :down, :enter, "y"], fn -> MyTool.wizard() end)

  assert result == {:ok, %{name: "ada", kind: "Library", go: true}}
  assert transcript =~ "✔ Kind · Library"
end
```

A string is typed one character at a time, an atom is a named key (`:enter`, `:down`,
`:tab`, `:escape`, `:space`), and a tuple is a raw event such as
`{:key, :c, [:ctrl]}`. A prompt still waiting when the keys run out returns
`{:error, :eof}`.

## Appearance

Colours come from the active `Drafter.Theme` and symbols from the active skin, so
`Drafter.ThemeManager.set_theme/1` changes prompts too. The `:ascii` skin gives 7-bit
symbols. Setting `NO_COLOR` removes the colours. Every function takes `style:` with
overrides; see `Drafter.Prompt.Style`.

Two settings have defaults in the application environment:

```elixir
config :drafter,
  prompt_limit: 7,
  prompt_interval: 80
```

`prompt_limit` is how many list entries or completion candidates show at once, and
`prompt_interval` is the milliseconds between redraws of a spinner. `limit:` and
`interval:` on a call take precedence.

## Writing your own prompt

A prompt is a module with three functions: a starting state, how an event changes it,
and the frame to show for it. `Drafter.Prompt.run/2` does the rest.

```elixir
defmodule Rating do
  @behaviour Drafter.Prompt.Component

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.Frame

  @impl true
  def init(opts), do: %{label: Keyword.fetch!(opts, :label), stars: 3}

  @impl true
  def handle_event({:key, :right}, state), do: {:cont, %{state | stars: min(state.stars + 1, 5)}}
  def handle_event({:key, :left}, state), do: {:cont, %{state | stars: max(state.stars - 1, 1)}}
  def handle_event({:key, :enter}, state), do: {:done, state.stars, state}
  def handle_event({:key, :escape}, state), do: {:stop, :cancelled, state}
  def handle_event(_event, state), do: {:cont, state}

  @impl true
  def render(state, _status, _context) do
    Frame.new([Strip.from_text(state.label <> " " <> String.duplicate("★", state.stars))])
  end
end

{:ok, stars} = Drafter.Prompt.run(Rating, label: "Rate it")
```

`render/3` is called with `:active` while the prompt is open, and once more with
`{:done, value}` or `{:stopped, reason}`; that last frame is what stays on screen. A
frame is a list of `Drafter.Draw.Strip`, the same lines widgets draw with, and may
name a cursor position. See `Drafter.Prompt.Component`.

## With a full-screen app

A program can ask questions and then start a full-screen app with `Drafter.run/2`, or
ask a question after one has exited. Both read the keyboard through one process,
`Drafter.Terminal.Stdin`, which hands input to whichever of them is running.

`Drafter.run/2` halts the VM when its app exits unless it is given
`halt_on_exit: false`, so pass that when more questions follow:

```elixir
{:ok, profile} = Prompt.select("Profile", profiles)
:ok = Drafter.run(Dashboard, halt_on_exit: false, props: %{profile: profile})
{:ok, save?} = Prompt.confirm("Save the layout?")
```

## How it works

**Drawing in place.** A prompt's frame is a few lines. To redraw, the cursor moves up
to the frame's first line, each line is written and the rest of it erased, and
anything left below is erased. Moves are relative, so the frame can sit anywhere on
screen and survives the terminal scrolling. Lines are cut one column short of the
terminal's width so they never wrap, since a wrapped line would make the line count
wrong.

**Raw mode for the length of a question.** Arrow keys and Tab only reach a program
when the terminal is in raw mode. A prompt enters raw mode when it opens and leaves it
when it closes, so between questions the terminal behaves as usual: `IO.puts/1` breaks
lines normally and Ctrl+C reaches the VM. While a question is open, Ctrl+C arrives as
a key and ends the question with `:interrupted`.

**One reader of standard input.** A read from the terminal cannot be taken back once
it has been asked for: if the process waiting on it goes away, the next key typed is
lost with it. So one process reads standard input for the whole run and passes keys to
whoever is asking. Keys typed between two questions are kept for the second one. The
cost is that `IO.gets/1` after a prompt competes with that reader, which is why later
input should come through `Drafter.Prompt` too.

**Spinners do not take the keyboard.** A spinner leaves the terminal mode alone and
keeps the cursor visible at the end of its line, so stopping the program with Ctrl+C
during one leaves the terminal usable.
