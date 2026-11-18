defmodule Drafter.Prompt.Terminal.Piped do
  @moduledoc """
  Standard input and output when they are not a terminal a prompt can draw on.

  Nothing is redrawn: `draw/2` shows nothing, `commit/2` and `print/2` write plain
  text to standard output, and `next_event/2` always answers `:closed`. Prompts ask
  their question on one line and read the answer as a line; see
  `c:Drafter.Prompt.Component.parse_line/2`.

  `newline` is `true` when standard input is not a terminal. A line break is then
  written after each answer is read, since the one that ended the answer is not shown.
  """

  alias Drafter.Prompt.Terminal.Local

  defstruct newline: false

  @type t :: %__MODULE__{newline: boolean()}

  @doc "A piped terminal for the calling process."
  @spec open() :: t()
  def open, do: %__MODULE__{newline: not Local.stdin_terminal?()}
end

defimpl Drafter.Prompt.Terminal, for: Drafter.Prompt.Terminal.Piped do
  alias Drafter.Prompt.Frame

  def size(_terminal), do: {80, 24}
  def interactive?(_terminal), do: false
  def draw(terminal, _frame), do: terminal

  def commit(terminal, frame) do
    IO.puts(Frame.text(frame))
    terminal
  end

  def print(terminal, text) do
    IO.write(text)
    terminal
  end

  def next_event(terminal, _timeout), do: {:closed, terminal}
  def close(_terminal), do: :ok
end
