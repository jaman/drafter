defmodule Drafter.Prompt.Runner do
  @moduledoc false

  alias Drafter.Prompt.{Component, Style, Terminal}
  alias Drafter.Prompt.Terminal.{Local, Piped, Scripted}

  @key {Drafter.Prompt, :terminal}

  @doc """
  Run `component` with `opts` on the calling process's terminal and return its value.
  """
  @spec run(module(), keyword()) ::
          {:ok, term()} | {:error, Component.stop_reason() | :not_a_terminal}
  def run(component, opts) do
    state = component.init(opts)
    style = Style.current(Keyword.get(opts, :style, []))
    terminal = open(input: true)

    {result, terminal} =
      try do
        ask(terminal, component, state, style)
      catch
        kind, reason ->
          Terminal.close(terminal)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    Terminal.close(terminal)
    result
  end

  @doc """
  The terminal for the calling process: the scripted one when `script/1` set one, the
  local terminal when prompts can be drawn on it, and a piped one otherwise.
  """
  @spec open(keyword()) :: Terminal.t()
  def open(opts) do
    case scripted() do
      nil -> open_local(Local.available?(), opts)
      scripted -> scripted
    end
  end

  @doc "The scripted terminal set for the calling process, or `nil`."
  @spec scripted() :: Scripted.t() | nil
  def scripted, do: Process.get(@key)

  @doc "Make `terminal` the calling process's terminal and return the one it replaces."
  @spec script(Scripted.t() | nil) :: Scripted.t() | nil
  def script(nil), do: Process.delete(@key)
  def script(%Scripted{} = terminal), do: Process.put(@key, terminal)

  defp open_local(false, _opts), do: Piped.open()

  defp open_local(true, opts) do
    case Local.open(opts) do
      {:ok, terminal} -> terminal
      {:error, _reason} -> Piped.open()
    end
  end

  defp ask(terminal, component, state, style) do
    if Terminal.interactive?(terminal),
      do: interact(terminal, component, state, style),
      else: {read_line(terminal, component, state), terminal}
  end

  defp interact(terminal, component, state, style) do
    frame = component.render(state, :active, context(terminal, style))
    {event, terminal} = terminal |> Terminal.draw(frame) |> Terminal.next_event(:infinity)
    react(event, terminal, component, state, style)
  end

  defp react(:closed, terminal, component, state, style),
    do: finish(terminal, component, state, style, {:stopped, :eof})

  defp react({:key, :c, [:ctrl]}, terminal, component, state, style),
    do: finish(terminal, component, state, style, {:stopped, :interrupted})

  defp react(event, terminal, component, state, style) do
    case component.handle_event(event, state) do
      {:cont, state} -> interact(terminal, component, state, style)
      {:done, value, state} -> finish(terminal, component, state, style, {:done, value})
      {:stop, reason, state} -> finish(terminal, component, state, style, {:stopped, reason})
    end
  end

  defp finish(terminal, component, state, style, outcome) do
    frame = component.render(state, outcome, context(terminal, style))
    {result(outcome), Terminal.commit(terminal, frame)}
  end

  defp result({:done, value}), do: {:ok, value}
  defp result({:stopped, reason}), do: {:error, reason}

  defp context(terminal, style) do
    {cols, rows} = Terminal.size(terminal)
    %{width: max(cols - 1, 1), rows: max(rows - 1, 1), style: style}
  end

  defp read_line(terminal, component, state) do
    if function_exported?(component, :parse_line, 2),
      do: ask_line(terminal, component, state),
      else: {:error, :not_a_terminal}
  end

  defp ask_line(terminal, component, state) do
    case IO.gets(IO.chardata_to_string(component.line_prompt(state))) do
      line when is_binary(line) ->
        if terminal.newline, do: IO.write("\n")
        answer_line(String.trim_trailing(line, "\n"), terminal, component, state)

      _end_of_input ->
        {:error, :eof}
    end
  end

  defp answer_line(line, terminal, component, state) do
    case component.parse_line(String.trim_trailing(line, "\r"), state) do
      {:ok, value} ->
        {:ok, value}

      {:error, message} ->
        IO.puts(message)
        ask_line(terminal, component, state)
    end
  end
end
