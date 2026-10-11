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

  The buffer also remembers which mouse buttons are down, from the presses and
  releases it decodes. A motion report that names a button the terminal never
  reported pressed, or reported released since, is delivered as a `:move`, not a
  `:drag`: a terminal in any-motion mode may encode a free pointer's motion with a
  button number rather than the "no button" code.

  It also remembers the last `{:cell_size, size}` and `{:pixel_mouse, on?}` reports it
  decoded, and passes both to every parse, so SGR mouse reports are read as pixels
  while the terminal has confirmed pixel mode and the cell size is known. See "Pixel
  mouse reports" in `Drafter.Terminal.ANSI`.

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

  @type t :: %__MODULE__{
          pending: binary(),
          timer: reference() | nil,
          key_release: boolean(),
          held: MapSet.t(atom()),
          pixel_mouse: boolean(),
          cell_size: {pos_integer(), pos_integer()} | nil
        }

  defstruct pending: "",
            timer: nil,
            key_release: false,
            held: MapSet.new(),
            pixel_mouse: false,
            cell_size: nil

  @doc """
  An empty buffer, holding no bytes and with no flush scheduled.

      iex> Drafter.Terminal.InputBuffer.new()
      %Drafter.Terminal.InputBuffer{pending: "", timer: nil, key_release: false}

  ## Options

    * `:key_release` - `boolean()`, passed to every parse as
      `Drafter.Terminal.ANSI.parse_sequence/2` describes. Default `false`.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: %__MODULE__{key_release: Keyword.get(opts, :key_release, false)}

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
    {events, pending} = ANSI.parse_sequence(buffer.pending <> data, parse_opts(buffer))
    {events, held} = track_buttons(events, buffer.held)
    {events, reschedule(%{read_reports(buffer, events) | pending: pending, held: held})}
  end

  defp parse_opts(buffer) do
    [
      key_release: buffer.key_release,
      pixel_mouse: buffer.pixel_mouse,
      cell_size: buffer.cell_size
    ]
  end

  defp read_reports(buffer, events), do: Enum.reduce(events, buffer, &read_report/2)

  defp read_report({:cell_size, size}, buffer), do: %{buffer | cell_size: size}
  defp read_report({:pixel_mouse, on?}, buffer), do: %{buffer | pixel_mouse: on?}
  defp read_report(_event, buffer), do: buffer

  defp track_buttons(events, held) do
    {events, held} =
      Enum.reduce(events, {[], held}, fn
        {:mouse, %{type: :mouse_down, button: button}} = event, {acc, held} ->
          {[event | acc], MapSet.put(held, button)}

        {:mouse, %{type: :mouse_up, button: button}} = event, {acc, held} ->
          {[event | acc], MapSet.delete(held, button)}

        {:mouse, %{type: :drag, button: button} = payload} = event, {acc, held} ->
          if MapSet.member?(held, button),
            do: {[event | acc], held},
            else:
              {[{:mouse, payload |> Map.delete(:button) |> Map.put(:type, :move)} | acc], held}

        event, {acc, held} ->
          {[event | acc], held}
      end)

    {Enum.reverse(events), held}
  end

  @doc """
  Resolve any held bytes without waiting for more input.

  Call on `:input_flush`, or when the input stream closes. Any scheduled flush is
  cancelled.

      iex> {_events, buffer} = Drafter.Terminal.InputBuffer.feed(Drafter.Terminal.InputBuffer.new(), "\\e")
      iex> {events, %Drafter.Terminal.InputBuffer{pending: "", timer: nil}} = Drafter.Terminal.InputBuffer.flush(buffer)
      iex> events
      [{:key, :escape}]

  An empty buffer yields no events.

      iex> {[], %Drafter.Terminal.InputBuffer{pending: ""}} = Drafter.Terminal.InputBuffer.flush(Drafter.Terminal.InputBuffer.new())
  """
  @spec flush(t()) :: {[ANSI.event()], t()}
  def flush(%__MODULE__{pending: ""} = buffer), do: {[], cancel(buffer)}

  def flush(%__MODULE__{} = buffer) do
    {events, pending} = ANSI.flush_sequence(buffer.pending, parse_opts(buffer))
    {events, %{cancel(read_reports(buffer, events)) | pending: pending}}
  end

  @doc """
  Discard held bytes and any pending flush, decoding nothing.

      iex> {_events, buffer} = Drafter.Terminal.InputBuffer.feed(Drafter.Terminal.InputBuffer.new(), "\\e[")
      iex> %Drafter.Terminal.InputBuffer{pending: "", timer: nil} = Drafter.Terminal.InputBuffer.reset(buffer)
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
