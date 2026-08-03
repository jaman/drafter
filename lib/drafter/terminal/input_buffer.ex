defmodule Drafter.Terminal.InputBuffer do
  @moduledoc """
  Carries partially-received terminal input across reads.

  Terminal input arrives in arbitrary chunks, and a control sequence can be split
  across two of them. `feed/2` decodes whatever is complete and holds the
  undecided tail until the rest arrives.

  A trailing lone `ESC` is held too, since it is both a complete keypress and the
  start of every escape sequence. `flush/1` resolves it as the escape key.
  Whenever bytes are held, an `:input_flush` message is scheduled to the calling
  process after `flush_after_ms/0`; drivers resolve the tail by calling `flush/1`
  on receipt.

      iex> buffer = Drafter.Terminal.InputBuffer.new()
      iex> {events, buffer} = Drafter.Terminal.InputBuffer.feed(buffer, "ab\\e[")
      iex> events
      [{:key, :a}, {:key, :b}]
      iex> {events, _buffer} = Drafter.Terminal.InputBuffer.feed(buffer, "A")
      iex> events
      [{:key, :up}]
  """

  alias Drafter.Terminal.ANSI

  @flush_after_ms 40

  @type t :: %__MODULE__{pending: binary(), timer: reference() | nil}

  defstruct pending: "", timer: nil

  @doc """
  An empty buffer, holding no bytes and with no flush scheduled.

      iex> Drafter.Terminal.InputBuffer.new()
      %Drafter.Terminal.InputBuffer{pending: "", timer: nil}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Milliseconds of silence after which a held sequence is resolved.

      iex> Drafter.Terminal.InputBuffer.flush_after_ms()
      40
  """
  @spec flush_after_ms() :: pos_integer()
  def flush_after_ms, do: @flush_after_ms

  @doc """
  Append a chunk and decode whatever is now complete.

  Returns the decoded events and the updated buffer. When bytes remain undecided
  an `:input_flush` message is scheduled to the calling process, replacing any
  previously scheduled one.

      iex> {events, buffer} = Drafter.Terminal.InputBuffer.feed(Drafter.Terminal.InputBuffer.new(), "hi\\e")
      iex> events
      [{:key, :h}, {:key, :i}]
      iex> buffer.pending
      "\\e"
  """
  @spec feed(t(), binary()) :: {[ANSI.event()], t()}
  def feed(%__MODULE__{} = buffer, data) do
    {events, pending} = ANSI.parse_sequence(buffer.pending <> data)
    {events, reschedule(%{buffer | pending: pending})}
  end

  @doc """
  Resolve any held bytes without waiting for more input.

  Call on `:input_flush`, or when the input stream closes. Any scheduled flush is
  cancelled.

      iex> {_events, buffer} = Drafter.Terminal.InputBuffer.feed(Drafter.Terminal.InputBuffer.new(), "\\e")
      iex> Drafter.Terminal.InputBuffer.flush(buffer)
      {[{:key, :escape}], %Drafter.Terminal.InputBuffer{pending: "", timer: nil}}

  An empty buffer yields no events.

      iex> Drafter.Terminal.InputBuffer.flush(Drafter.Terminal.InputBuffer.new())
      {[], %Drafter.Terminal.InputBuffer{pending: "", timer: nil}}
  """
  @spec flush(t()) :: {[ANSI.event()], t()}
  def flush(%__MODULE__{pending: ""} = buffer), do: {[], cancel(buffer)}

  def flush(%__MODULE__{} = buffer) do
    {events, pending} = ANSI.flush_sequence(buffer.pending)
    {events, %{cancel(buffer) | pending: pending}}
  end

  @doc """
  Discard held bytes and any pending flush, decoding nothing.

      iex> {_events, buffer} = Drafter.Terminal.InputBuffer.feed(Drafter.Terminal.InputBuffer.new(), "\\e[")
      iex> Drafter.Terminal.InputBuffer.reset(buffer)
      %Drafter.Terminal.InputBuffer{pending: "", timer: nil}
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = buffer), do: %{cancel(buffer) | pending: ""}

  defp reschedule(buffer) do
    buffer = cancel(buffer)

    if buffer.pending == "" do
      buffer
    else
      %{buffer | timer: Process.send_after(self(), :input_flush, @flush_after_ms)}
    end
  end

  defp cancel(%__MODULE__{timer: nil} = buffer), do: buffer

  defp cancel(%__MODULE__{timer: timer} = buffer) do
    Process.cancel_timer(timer)
    %{buffer | timer: nil}
  end
end
