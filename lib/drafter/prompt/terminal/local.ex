defmodule Drafter.Prompt.Terminal.Local do
  @moduledoc """
  The terminal the program runs in, used without the alternate screen.

  `open/1` returns a terminal for the calling process, which must also be the process
  that uses and closes it:

      {:ok, terminal} = Drafter.Prompt.Terminal.Local.open()
      {event, terminal} = Drafter.Prompt.Terminal.next_event(terminal, :infinity)
      Drafter.Prompt.Terminal.close(terminal)

  ## Options

    * `:input` - `boolean()`, default `true`. With `true` the terminal is put into raw
      mode, bracketed paste is turned on and keys are read through
      `Drafter.Terminal.Stdin`; closing the terminal undoes all three and leaves the
      terminal in line mode, where a line feed returns to the first column. With `false` the terminal
      mode is left alone and `next_event/2` only waits.

  Frames are written to `/dev/tty`, and to standard output where that cannot be
  opened. While a terminal opened with `input: true` is open, `Ctrl+C` arrives as the
  event `{:key, :c, [:ctrl]}`.

  Events decoded but not consumed when the terminal closes are kept for the next
  terminal the same process opens.
  """

  alias Drafter.Prompt.{Frame, Region, Terminal}
  alias Drafter.Terminal.{ANSI, InputBuffer, RawMode, Stdin, TermiosNif}

  defstruct [:device, :mode, input: true, region: %Region{}, buffer: nil, events: []]

  @type t :: %__MODULE__{
          device: :file.io_device() | :stdio,
          mode: RawMode.mode(),
          input: boolean(),
          region: Region.t(),
          buffer: InputBuffer.t() | nil,
          events: [Terminal.event()]
        }

  @paste_on "\e[?2004h"
  @paste_off "\e[?2004l"

  @doc """
  Whether prompts can be drawn here: standard input is a terminal and `TERM` is not
  `dumb`.
  """
  @spec available?() :: boolean()
  def available?, do: System.get_env("TERM") != "dumb" and stdin_terminal?()

  @doc "Whether standard input is a terminal."
  @spec stdin_terminal?() :: boolean()
  def stdin_terminal? do
    match?({:ok, _size}, TermiosNif.get_winsize(0))
  rescue
    ErlangError -> io_terminal?()
  end

  @doc """
  Open the terminal for the calling process.

  `{:error, reason}` means the terminal could not be put into raw mode; nothing was
  changed.
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts \\ []), do: open_for(Keyword.get(opts, :input, true))

  @doc false
  @spec write(t(), iodata()) :: :ok
  def write(%__MODULE__{device: :stdio}, bytes), do: IO.write(bytes)

  def write(%__MODULE__{device: device}, bytes) do
    :file.write(device, bytes)
    :ok
  end

  @doc false
  @spec shut(t()) :: :ok
  def shut(%__MODULE__{input: false} = terminal) do
    write(terminal, ANSI.show_cursor())
    close_device(terminal.device)
  end

  def shut(%__MODULE__{} = terminal) do
    write(terminal, [ANSI.show_cursor(), @paste_off])
    Stdin.unsubscribe(self())
    RawMode.leave(terminal.mode)
    shell_input(:cooked)
    {flushed, _buffer} = InputBuffer.flush(terminal.buffer)
    Enum.each(terminal.events ++ flushed, &send(self(), {__MODULE__, :carried, &1}))
    close_device(terminal.device)
  end

  @doc false
  @spec await(t(), timeout()) :: {Terminal.event() | :timeout | :closed, t()}
  def await(%__MODULE__{events: [event | rest]} = terminal, _timeout),
    do: {event, %{terminal | events: rest}}

  def await(%__MODULE__{input: false} = terminal, timeout) do
    receive do
    after
      timeout -> {:timeout, terminal}
    end
  end

  def await(%__MODULE__{} = terminal, timeout) do
    receive do
      {:stdin, bytes} ->
        {events, buffer} = InputBuffer.feed(terminal.buffer, bytes)
        await(%{terminal | buffer: buffer, events: events}, timeout)

      :input_flush ->
        {events, buffer} = InputBuffer.flush(terminal.buffer)
        await(%{terminal | buffer: buffer, events: events}, timeout)

      :stdin_closed ->
        {:closed, terminal}
    after
      timeout -> {:timeout, terminal}
    end
  end

  @doc false
  @spec measure() :: {pos_integer(), pos_integer()}
  def measure do
    case TermiosNif.get_winsize() do
      {:ok, {cols, rows, _xpixel, _ypixel}} when cols > 0 and rows > 0 -> {cols, rows}
      _other -> io_size()
    end
  rescue
    ErlangError -> io_size()
  end

  @doc false
  @spec show(t(), Frame.t()) :: t()
  def show(%__MODULE__{} = terminal, %Frame{} = frame) do
    {bytes, region} = Region.draw(terminal.region, frame, measure())
    write(terminal, bytes)
    %{terminal | region: region}
  end

  @doc false
  @spec settle(t()) :: t()
  def settle(%__MODULE__{} = terminal) do
    {bytes, region} = Region.leave(terminal.region)
    write(terminal, bytes)
    %{terminal | region: region}
  end

  @doc false
  @spec interject(t(), iodata()) :: t()
  def interject(%__MODULE__{} = terminal, text) do
    {bytes, region} = Region.clear(terminal.region)
    write(terminal, [bytes, text |> IO.chardata_to_string() |> terminal_lines()])
    %{terminal | region: region}
  end

  defp open_for(false), do: {:ok, %__MODULE__{device: open_device(), input: false}}

  defp open_for(true) do
    with :ok <- shell_input(:raw),
         {:ok, mode} <- enter_raw_mode() do
      terminal = %__MODULE__{
        device: open_device(),
        mode: mode,
        buffer: InputBuffer.new(),
        events: carried()
      }

      Stdin.subscribe(self(), :keep)
      write(terminal, @paste_on)
      {:ok, terminal}
    end
  end

  defp enter_raw_mode do
    with {:error, reason} <- RawMode.enter() do
      shell_input(:cooked)
      {:error, reason}
    end
  end

  defp shell_input(mode) do
    :shell.start_interactive({:noshell, mode})
  rescue
    error in [FunctionClauseError, UndefinedFunctionError] -> {:error, error}
  end

  defp open_device do
    case :file.open(~c"/dev/tty", [:write, :raw, :binary]) do
      {:ok, device} -> device
      {:error, _reason} -> :stdio
    end
  end

  defp close_device(:stdio), do: :ok

  defp close_device(device) do
    :file.close(device)
    :ok
  end

  defp carried do
    receive do
      {__MODULE__, :carried, event} -> [event | carried()]
    after
      0 -> []
    end
  end

  defp terminal_lines(""), do: []

  defp terminal_lines(text) do
    lines = text |> String.replace("\r\n", "\n") |> String.replace("\n", "\r\n")
    if String.ends_with?(lines, "\r\n"), do: lines, else: [lines, "\r\n"]
  end

  defp io_terminal? do
    case :io.getopts(:standard_io) do
      opts when is_list(opts) -> Keyword.get(opts, :stdin, Keyword.get(opts, :terminal, false))
      _error -> false
    end
  end

  defp io_size do
    with {:ok, cols} <- :io.columns(:standard_io),
         {:ok, rows} <- :io.rows(:standard_io) do
      {cols, rows}
    else
      _unknown -> {80, 24}
    end
  end
end

defimpl Drafter.Prompt.Terminal, for: Drafter.Prompt.Terminal.Local do
  alias Drafter.Prompt.Terminal.Local

  def size(_terminal), do: Local.measure()
  def interactive?(_terminal), do: true
  def draw(terminal, frame), do: Local.show(terminal, frame)
  def commit(terminal, frame), do: terminal |> Local.show(frame) |> Local.settle()
  def print(terminal, text), do: Local.interject(terminal, text)
  def next_event(terminal, timeout), do: Local.await(terminal, timeout)
  def close(terminal), do: Local.shut(terminal)
end
