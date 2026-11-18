defmodule Drafter.Prompt.Terminal.Scripted do
  @moduledoc """
  A terminal whose keys come from a list and whose output is kept as text.

  Events are handed out in order, and `:closed` once they run out. Only committed
  frames and printed text are kept; frames drawn on the way are dropped, so the
  transcript does not depend on timing.

      terminal = Drafter.Prompt.Terminal.Scripted.start([{:key, :y}])
      {{:key, :y}, terminal} = Drafter.Prompt.Terminal.next_event(terminal, :infinity)
      {:closed, _terminal} = Drafter.Prompt.Terminal.next_event(terminal, :infinity)
      Drafter.Prompt.Terminal.Scripted.stop(terminal)

  The terminal is a process, so it can be used from any process and by several
  prompts in a row. `Drafter.Prompt.Script` wraps it for tests.

  ## Options

    * `:size` - `{columns, rows}` reported to prompts. Default `{80, 24}`.
  """

  alias Drafter.Prompt.{Frame, Terminal}

  @enforce_keys [:store]
  defstruct [:store, size: {80, 24}]

  @type t :: %__MODULE__{store: pid(), size: {pos_integer(), pos_integer()}}

  @doc "Start a terminal that will hand out `events`."
  @spec start([Terminal.event()], keyword()) :: t()
  def start(events, opts \\ []) when is_list(events) do
    {:ok, store} = Agent.start_link(fn -> %{events: events, output: []} end)
    %__MODULE__{store: store, size: Keyword.get(opts, :size, {80, 24})}
  end

  @doc "Everything committed and printed so far, as plain text."
  @spec transcript(t()) :: String.t()
  def transcript(%__MODULE__{store: store}) do
    Agent.get(store, fn %{output: output} -> output |> Enum.reverse() |> IO.iodata_to_binary() end)
  end

  @doc "The events not yet handed out."
  @spec remaining(t()) :: [Terminal.event()]
  def remaining(%__MODULE__{store: store}), do: Agent.get(store, & &1.events)

  @doc "Stop the terminal's process."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{store: store}), do: Agent.stop(store)

  @doc false
  @spec record(t(), iodata()) :: t()
  def record(%__MODULE__{store: store} = terminal, text) do
    Agent.update(store, fn state -> %{state | output: [text | state.output]} end)
    terminal
  end

  @doc false
  @spec take(t()) :: Terminal.event() | :closed
  def take(%__MODULE__{store: store}) do
    Agent.get_and_update(store, fn
      %{events: [event | rest]} = state -> {event, %{state | events: rest}}
      %{events: []} = state -> {:closed, state}
    end)
  end

  @doc false
  @spec committed(Frame.t()) :: iodata()
  def committed(%Frame{} = frame), do: [Frame.text(frame), "\n"]
end

defimpl Drafter.Prompt.Terminal, for: Drafter.Prompt.Terminal.Scripted do
  alias Drafter.Prompt.Terminal.Scripted

  def size(terminal), do: terminal.size
  def interactive?(_terminal), do: true
  def draw(terminal, _frame), do: terminal
  def commit(terminal, frame), do: Scripted.record(terminal, Scripted.committed(frame))
  def print(terminal, text), do: Scripted.record(terminal, text)
  def next_event(terminal, _timeout), do: {Scripted.take(terminal), terminal}
  def close(_terminal), do: :ok
end
