defmodule Drafter.Prompt do
  @moduledoc """
  Questions, menus and progress lines for command-line programs, drawn in place below
  the shell prompt. No alternate screen, no app module, no widgets.

      alias Drafter.Prompt

      with {:ok, name} <- Prompt.text("Project name", default: "my_app"),
           {:ok, kind} <- Prompt.select("Template", ["Phoenix", "Escript", "Library"]),
           {:ok, extras} <- Prompt.multiselect("Extras", ["Credo", "Dialyxir", "ExDoc"]),
           {:ok, true} <- Prompt.confirm("Create it?") do
        Prompt.spinner("Creating \#{name}", fn -> create(name, kind, extras) end)
      end

  ## Functions

    * `text/2`, `password/2`, `number/2` — one line of typed input
    * `confirm/2` — yes or no
    * `select/3`, `multiselect/3`, `search/3` — pick from a list
    * `readline/2` — a bare input line with history and Tab completion, for a
      command loop
    * `form/1` — several questions, answered into one map
    * `spinner/3`, `progress/4` — a moving line while work runs
    * `say/2` — a status line
    * `run/2` — a prompt of your own, written as a `Drafter.Prompt.Component`

  ## Results

  Every question returns `{:ok, value}` or `{:error, reason}`, where `reason` is a
  `t:reason/0`. Each has a `!` twin that returns the value and raises
  `Drafter.Prompt.Stopped` instead. `spinner/3` and `progress/4` return what the work
  returned.

  ## Without a terminal

  When standard input is not a terminal, or `TERM` is `dumb`, nothing is drawn. Each
  question is written as one line and answered by one line of standard input, so a
  program can be driven by a pipe:

      printf 'my_app\\n2\\n\\ny\\n' | my_tool new

  A list is answered by the number of an entry, several by numbers separated by
  commas, and an empty line gives the default. Spinners and progress bars write
  only their final line.

  ## Reading input elsewhere

  After the first question asked on a terminal, standard input is read through
  `Drafter.Terminal.Stdin` for the rest of the run. Ask later questions through this
  module; `IO.gets/1` would compete with it for keys.

  ## Appearance

  Colours come from the active `Drafter.Theme` and symbols from the active skin; see
  `Drafter.Prompt.Style`. Every function takes `style:` with overrides for
  `Drafter.Prompt.Style.current/1`.

  ## Testing

  `Drafter.Prompt.Script.run/3` runs code that asks questions against a list of keys.
  """

  alias Drafter.Draw.Strip

  alias Drafter.Prompt.{
    Activity,
    Choice,
    Confirm,
    Frame,
    Runner,
    Select,
    Stopped,
    Style,
    Terminal,
    Text
  }

  @typedoc """
  Why a question ended without an answer.

    * `:cancelled` - Esc was pressed
    * `:interrupted` - Ctrl+C was pressed
    * `:eof` - Ctrl+D was pressed on an empty line, or standard input ended
    * `:not_a_terminal` - there is no terminal and the prompt cannot be answered by a
      line of input
  """
  @type reason :: :cancelled | :interrupted | :eof | :not_a_terminal

  @type result(value) :: {:ok, value} | {:error, reason()}

  @typedoc """
  One entry of `form/1`: a tuple naming a question function of this module followed
  by its arguments, a function from the answers so far to such a tuple, or `:skip`.
  """
  @type question ::
          {atom(), String.t()}
          | {atom(), String.t(), term()}
          | {atom(), String.t(), term(), keyword()}
          | :skip
          | (map() -> question())

  @questions [:text, :password, :number, :confirm, :select, :multiselect, :search, :readline]

  @doc """
  Ask for one line of text.

      Drafter.Prompt.text("Project name", default: "my_app")
      #=> {:ok, "my_app"}

  ## Options

    * `:default` - returned when the line is submitted empty
    * `:placeholder` - dimmed text shown while the line is empty
    * `:validate` - `(value -> :ok | {:error, message})`. A rejected line stays open
      with `message` under it
    * `:complete` - Tab completion: a list of words, or a function from the text
      before the cursor to candidates. See `Drafter.Prompt.Completion`
    * `:history` - earlier answers, newest first, recalled with Up and Down

  See `Drafter.Prompt.Text` for the keys.
  """
  @spec text(String.t(), keyword()) :: result(String.t())
  def text(label, opts \\ []), do: Runner.run(Text, Keyword.put(opts, :label, label))

  @doc """
  Ask for a secret. Typed characters are shown as `*`.

  Takes the options of `text/2`, and `:mask` to change the character shown.
  """
  @spec password(String.t(), keyword()) :: result(String.t())
  def password(label, opts \\ []), do: text(label, Keyword.put_new(opts, :mask, "*"))

  @doc """
  Ask for a number.

      Drafter.Prompt.number("Port", default: 4000, min: 1, max: 65_535)
      #=> {:ok, 4000}

  ## Options

    * `:float` - `true` accepts a decimal and returns a float. Default `false`, which
      returns an integer
    * `:min` and `:max` - the smallest and largest number accepted
    * `:default`, `:placeholder` and `:validate`, as in `text/2`; `:validate` receives
      the number
  """
  @spec number(String.t(), keyword()) :: result(number())
  def number(label, opts \\ []), do: text(label, Keyword.put(opts, :parse, number_parser(opts)))

  @doc """
  Ask a yes or no question.

      Drafter.Prompt.confirm("Overwrite the file?", default: false)
      #=> {:ok, false}

  `:default` is the answer Enter gives, `true` unless set.
  """
  @spec confirm(String.t(), keyword()) :: result(boolean())
  def confirm(label, opts \\ []), do: Runner.run(Confirm, Keyword.put(opts, :label, label))

  @doc """
  Pick one entry from a list.

      Drafter.Prompt.select("Template", ["Phoenix", "Escript", {"Plain library", :library}])
      #=> {:ok, :library}

  Each entry is anything `Drafter.Prompt.Choice.new/1` accepts; the result is the
  picked entry's value.

  ## Options

    * `:default` - the value highlighted first
    * `:filter` - `true` narrows the list as the user types
    * `:limit` - the most entries shown at once

  See `Drafter.Prompt.Select` for the keys.
  """
  @spec select(String.t(), [Choice.input()], keyword()) :: result(term())
  def select(label, choices, opts \\ []),
    do: Runner.run(Select, opts |> Keyword.put(:label, label) |> Keyword.put(:choices, choices))

  @doc """
  Pick any number of entries from a list.

      Drafter.Prompt.multiselect("Extras", ["Credo", "Dialyxir", "ExDoc"], default: ["Credo"])
      #=> {:ok, ["Credo", "ExDoc"]}

  The result holds the picked values in the order of the list.

  ## Options

    * `:default` - the values picked first
    * `:min` and `:max` - the fewest and most entries that may be picked
    * `:filter` and `:limit`, as in `select/3`
  """
  @spec multiselect(String.t(), [Choice.input()], keyword()) :: result([term()])
  def multiselect(label, choices, opts \\ []),
    do: select(label, choices, Keyword.put(opts, :multiple, true))

  @doc """
  Pick one entry from a list that depends on what the user types.

      Drafter.Prompt.search("Package", fn query -> Hex.search(query) end)

  `source` is called with the typed text, first with `""`, and returns the entries to
  list. It runs in the calling process on every change to the text.
  """
  @spec search(String.t(), (String.t() -> [Choice.input()]), keyword()) :: result(term())
  def search(label, source, opts \\ []) when is_function(source, 1),
    do: Runner.run(Select, opts |> Keyword.put(:label, label) |> Keyword.put(:source, source))

  @doc """
  Read one line after `prompt`, as a shell does.

      def loop(history) do
        case Drafter.Prompt.readline("db> ", history: history, complete: ["select", "insert", "quit"]) do
          {:ok, "quit"} ->
            :ok

          {:ok, line} ->
            run(line)
            loop([line | history])

          {:error, _reason} ->
            :ok
        end
      end

  The line is left on screen as typed. Takes the options of `text/2`.
  """
  @spec readline(String.t(), keyword()) :: result(String.t())
  def readline(prompt, opts \\ []), do: text(prompt, Keyword.put(opts, :plain, true))

  @doc """
  Ask several questions and return the answers as a map.

      Drafter.Prompt.form(
        name: {:text, "Project name", default: "my_app"},
        kind: {:select, "Template", ["Phoenix", "Escript"]},
        port: fn
          %{kind: "Phoenix"} -> {:number, "Port", default: 4000}
          _answers -> :skip
        end,
        go: {:confirm, "Create it?"}
      )
      #=> {:ok, %{name: "my_app", kind: "Phoenix", port: 4000, go: true}}

  Each entry is a `t:question/0`, asked in order. A function receives the answers so
  far and returns the question to ask, or `:skip` to leave its key out. The first
  question that ends without an answer ends the form with its `{:error, reason}`.
  """
  @spec form(keyword(question())) :: result(%{atom() => term()})
  def form(questions) when is_list(questions) do
    Enum.reduce_while(questions, {:ok, %{}}, fn {name, question}, {:ok, answers} ->
      case question |> resolve(answers) |> ask() do
        :skip -> {:cont, {:ok, answers}}
        {:ok, answer} -> {:cont, {:ok, Map.put(answers, name, answer)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Run a prompt component with `opts` and return its value.

  `component` implements `Drafter.Prompt.Component`. `opts` is passed to its
  `c:Drafter.Prompt.Component.init/1`.
  """
  @spec run(module(), keyword()) :: result(term())
  def run(component, opts \\ []) when is_atom(component), do: Runner.run(component, opts)

  @doc """
  Show a spinner beside `label` while `work` runs, and return what `work` returns.

      Drafter.Prompt.spinner("Fetching dependencies", fn -> fetch() end)

      Drafter.Prompt.spinner("Building", fn status ->
        compile()
        status.("Linking")
        link()
      end)

  `work` runs in the calling process. Given one argument, it receives a function that
  changes the label. What `work` writes to standard output appears above the spinner.
  The line ends with a done mark, or a failed mark when `work` raises, exits or throws,
  which then continues to the caller.

  `:interval` sets the milliseconds between redraws, `80` unless
  `config :drafter, prompt_interval:` says otherwise.
  """
  @spec spinner(String.t(), (-> result) | ((String.t() -> :ok) -> result), keyword()) :: result
        when result: var
  def spinner(label, work, opts \\ [])

  def spinner(label, work, opts) when is_function(work, 0),
    do: Activity.run(label, opts, fn _activity -> work.() end)

  def spinner(label, work, opts) when is_function(work, 1),
    do: Activity.run(label, opts, fn activity -> work.(&Activity.label(activity, &1)) end)

  @doc """
  Show a progress bar beside `label` while `work` runs.

  With a list or other enumerable, `work` is called with each element, the bar moves
  one step per element, and the results are returned as a list:

      Drafter.Prompt.progress("Resizing", images, fn image -> resize(image) end)

  With a number of steps, `work` is called once with a function that moves the bar by
  the steps it is given, and what `work` returns is returned:

      Drafter.Prompt.progress("Downloading", byte_size, fn advance ->
        download(fn chunk -> advance.(byte_size(chunk)) end)
      end)

  Output, failure and `:interval` behave as in `spinner/3`.
  """
  @spec progress(String.t(), number() | Enumerable.t(), (term() -> term()), keyword()) :: term()
  def progress(label, total, work, opts \\ [])

  def progress(label, total, work, opts) when is_number(total) and is_function(work, 1) do
    Activity.run(label, Keyword.put(opts, :total, total), fn activity ->
      work.(&Activity.advance(activity, &1))
    end)
  end

  def progress(label, items, work, opts) when is_function(work, 1) do
    items = Enum.to_list(items)

    Activity.run(label, Keyword.put(opts, :total, length(items)), fn activity ->
      Enum.map(items, fn item ->
        result = work.(item)
        Activity.advance(activity)
        result
      end)
    end)
  end

  @doc """
  Write a status line: a symbol for `kind`, then `message`.

      Drafter.Prompt.say(:success, "Created my_app")

  `kind` is `:info`, `:success`, `:warning` or `:error`. The line goes to standard
  output, coloured when standard output is a terminal.
  """
  @spec say(:info | :success | :warning | :error, String.t()) :: :ok
  def say(kind, message) when kind in [:info, :success, :warning, :error] do
    style = Style.current()
    {role, symbol} = mark(kind)

    strip =
      Strip.new([
        Style.segment(style, role, Style.symbol(style, symbol)),
        Style.segment(style, :plain, " " <> message)
      ])

    write_line(Runner.scripted(), strip)
  end

  @doc "As `text/2`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec text!(String.t(), keyword()) :: String.t()
  def text!(label, opts \\ []), do: label |> text(opts) |> answer!()

  @doc "As `password/2`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec password!(String.t(), keyword()) :: String.t()
  def password!(label, opts \\ []), do: label |> password(opts) |> answer!()

  @doc "As `number/2`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec number!(String.t(), keyword()) :: number()
  def number!(label, opts \\ []), do: label |> number(opts) |> answer!()

  @doc "As `confirm/2`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec confirm!(String.t(), keyword()) :: boolean()
  def confirm!(label, opts \\ []), do: label |> confirm(opts) |> answer!()

  @doc "As `select/3`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec select!(String.t(), [Choice.input()], keyword()) :: term()
  def select!(label, choices, opts \\ []), do: label |> select(choices, opts) |> answer!()

  @doc "As `multiselect/3`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec multiselect!(String.t(), [Choice.input()], keyword()) :: [term()]
  def multiselect!(label, choices, opts \\ []),
    do: label |> multiselect(choices, opts) |> answer!()

  @doc "As `search/3`, returning the answer or raising `Drafter.Prompt.Stopped`."
  @spec search!(String.t(), (String.t() -> [Choice.input()]), keyword()) :: term()
  def search!(label, source, opts \\ []), do: label |> search(source, opts) |> answer!()

  @doc "As `readline/2`, returning the line or raising `Drafter.Prompt.Stopped`."
  @spec readline!(String.t(), keyword()) :: String.t()
  def readline!(prompt, opts \\ []), do: prompt |> readline(opts) |> answer!()

  @doc "As `form/1`, returning the answers or raising `Drafter.Prompt.Stopped`."
  @spec form!(keyword(question())) :: %{atom() => term()}
  def form!(questions), do: questions |> form() |> answer!()

  defp answer!({:ok, answer}), do: answer
  defp answer!({:error, reason}), do: raise(Stopped, reason: reason)

  defp resolve(question, answers) when is_function(question, 1), do: question.(answers)
  defp resolve(question, _answers), do: question

  defp ask(:skip), do: :skip
  defp ask({kind, label}) when kind in @questions, do: apply(__MODULE__, kind, [label])

  defp ask({kind, label, argument}) when kind in @questions,
    do: apply(__MODULE__, kind, [label, argument])

  defp ask({kind, label, argument, opts}) when kind in @questions,
    do: apply(__MODULE__, kind, [label, argument, opts])

  defp number_parser(opts) do
    float? = Keyword.get(opts, :float, false)
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)

    fn text ->
      with {:ok, number} <- to_number(String.trim(text), float?),
           :ok <- at_least(number, min),
           :ok <- at_most(number, max) do
        {:ok, number}
      end
    end
  end

  defp to_number(text, false) do
    case Integer.parse(text) do
      {number, ""} -> {:ok, number}
      _other -> {:error, "Enter a whole number."}
    end
  end

  defp to_number(text, true) do
    case Float.parse(text) do
      {number, ""} -> {:ok, number}
      _other -> {:error, "Enter a number."}
    end
  end

  defp at_least(number, min) when is_number(min) and number < min,
    do: {:error, "Enter #{min} or more."}

  defp at_least(_number, _min), do: :ok

  defp at_most(number, max) when is_number(max) and number > max,
    do: {:error, "Enter #{max} or less."}

  defp at_most(_number, _max), do: :ok

  defp mark(:info), do: {:accent, :info}
  defp mark(:success), do: {:success, :done}
  defp mark(:warning), do: {:warning, :warning}
  defp mark(:error), do: {:error, :failed}

  defp write_line(nil, strip) do
    if IO.ANSI.enabled?(),
      do: IO.puts(Strip.to_ansi(strip)),
      else: IO.puts(Frame.text(Frame.new([strip])))
  end

  defp write_line(scripted, strip) do
    Terminal.print(scripted, [Frame.text(Frame.new([strip])), "\n"])
    :ok
  end
end
