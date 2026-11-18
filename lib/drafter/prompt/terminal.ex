defprotocol Drafter.Prompt.Terminal do
  @moduledoc """
  Where a prompt is shown and where its keys come from.

  Three implementations ship with Drafter:

    * `Drafter.Prompt.Terminal.Local` — the terminal the program runs in
    * `Drafter.Prompt.Terminal.Piped` — standard input and output when they are not a
      terminal
    * `Drafter.Prompt.Terminal.Scripted` — keys from a list, for tests

  Functions that change what the terminal remembers return the terminal to keep
  using.
  """

  alias Drafter.Prompt.Frame

  @typedoc "A key or paste event as `Drafter.Terminal.ANSI` decodes it."
  @type event :: Drafter.Terminal.ANSI.event()

  @doc "The terminal's size as `{columns, rows}`."
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(terminal)

  @doc "Whether the terminal redraws frames and delivers keys one at a time."
  @spec interactive?(t()) :: boolean()
  def interactive?(terminal)

  @doc "Show `frame` in place of the frame drawn before it."
  @spec draw(t(), Frame.t()) :: t()
  def draw(terminal, frame)

  @doc "Show `frame` as the last frame and move below it, so later output follows it."
  @spec commit(t(), Frame.t()) :: t()
  def commit(terminal, frame)

  @doc """
  Write `text` where the current frame is, pushing the frame out of the way.

  The frame is erased; draw it again afterwards.
  """
  @spec print(t(), iodata()) :: t()
  def print(terminal, text)

  @doc """
  Wait up to `timeout` for the next event.

  Returns the event, `:timeout`, or `:closed` when no more input can arrive.
  """
  @spec next_event(t(), timeout()) :: {event() | :timeout | :closed, t()}
  def next_event(terminal, timeout)

  @doc "Give the terminal back. The terminal must not be used afterwards."
  @spec close(t()) :: :ok
  def close(terminal)
end
