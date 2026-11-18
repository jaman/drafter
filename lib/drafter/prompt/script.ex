defmodule Drafter.Prompt.Script do
  @moduledoc """
  Runs code that asks questions against a list of keys, with no terminal.

      {answers, transcript} =
        Drafter.Prompt.Script.run(["ada", :enter, :down, :enter], fn ->
          {:ok, name} = Drafter.Prompt.text("Name")
          {:ok, kind} = Drafter.Prompt.select("Kind", ["App", "Library"])
          {name, kind}
        end)

      answers
      #=> {"ada", "Library"}

      transcript
      #=> "✔ Name · ada\\n✔ Kind · Library\\n"

  ## Inputs

  Each input is one of:

    * a string, typed one character at a time; `"\\r"` is Enter and `"\\t"` is Tab
    * an atom naming a key, such as `:enter`, `:down`, `:tab`, `:escape` or
      `:backspace`; `:space` is the space bar
    * an event as `Drafter.Terminal.ANSI` decodes it, such as `{:key, :c, [:ctrl]}`

  A prompt that is still waiting when the inputs run out returns `{:error, :eof}`.

  The transcript holds the line each prompt left on screen, what
  `Drafter.Prompt.say/2` wrote, and what was written during a spinner or progress
  bar, in order and without styling.

  ## Options

    * `:size` - `{columns, rows}` reported to prompts. Default `{80, 24}`.
  """

  alias Drafter.Prompt.Runner
  alias Drafter.Prompt.Terminal
  alias Drafter.Prompt.Terminal.Scripted
  alias Drafter.Terminal.ANSI

  @type input :: String.t() | atom() | Terminal.event()

  @doc """
  Call `fun` with `inputs` standing in for the keyboard.

  Returns what `fun` returned and the transcript. Only prompts asked by the calling
  process read the inputs.
  """
  @spec run([input()], (-> result), keyword()) :: {result, String.t()} when result: var
  def run(inputs, fun, opts \\ []) when is_list(inputs) and is_function(fun, 0) do
    terminal = inputs |> Enum.flat_map(&events/1) |> Scripted.start(opts)
    previous = Runner.script(terminal)

    try do
      result = fun.()
      {result, Scripted.transcript(terminal)}
    after
      Runner.script(previous)
      Scripted.stop(terminal)
    end
  end

  defp events(text) when is_binary(text) do
    {events, _rest} = ANSI.flush_sequence(text)
    events
  end

  defp events(:space), do: [{:key, :" "}]
  defp events(key) when is_atom(key), do: [{:key, key}]
  defp events(event) when is_tuple(event), do: [event]
end
