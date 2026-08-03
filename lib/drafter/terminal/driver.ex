defmodule Drafter.Terminal.Driver do
  @moduledoc """
  Owns the local terminal: raw mode, alternate screen, mouse reporting, input decoding.

  A singleton registered under this module's name. `setup/1` puts the terminal into
  raw mode, switches to the alternate screen, hides the cursor and enables mouse and
  bracketed-paste reporting. `cleanup/0` undoes all of it and restores the saved
  terminal mode; it also runs from `terminate/2`.

  Input is not read until `start_input/0` is called, so a caller can drain whatever
  the terminal echoed during startup first:

      Drafter.Terminal.Driver.setup()
      Drafter.Terminal.Driver.drain_pending_input()
      Drafter.Terminal.Driver.start_input()

  Decoded input is cast to the event manager as `{:event, event}`; the manager then
  delivers `{:tui_event, event}` to its subscribers. Event shapes are the ones
  `Drafter.Terminal.ANSI` produces, plus `{:resize, {cols, rows}}` emitted on
  `SIGWINCH`.

  The event manager is chosen at `init/1` by the `:event_manager` option, defaulting
  to `Drafter.Event.Manager`.

  Raw mode is entered through the termios NIF where it loads, and through `stty`
  otherwise. On a non-unix system neither runs and the terminal mode is left alone,
  while the rest of `setup/1` still happens.

  Terminal size is read by `TIOCGWINSZ`, falling back to Erlang's IO dimensions and
  then to `tput`; `80` by `24` if all of them fail. Setting `DRAFTER_TPUT_SIZE` to a
  non-empty value forces the `tput` path. On Windows the size comes from PowerShell,
  and `80` by `24` if that fails.
  """

  use GenServer

  alias Drafter.Event
  alias Drafter.Terminal.{ANSI, InputBuffer, Probe, TermiosNif}

  defstruct [
    :shell_pid,
    :stdin_reader_pid,
    :terminal_mode,
    buffer: %InputBuffer{},
    mouse_enabled: false,
    alt_screen: false,
    raw_mode: false,
    size: {80, 24},
    probing: false,
    probe_replies: "",
    probe_result: :unprobed,
    probe_waiters: []
  ]

  @default_probe_timeout 250

  @typedoc """
  The driver's own state.

  `shell_pid` holds whatever `:shell.start_interactive/1` returned, which is `:ok`
  or an error tuple rather than a pid.
  """
  @type state :: %__MODULE__{
          shell_pid: :ok | {:error, term()} | nil,
          stdin_reader_pid: pid() | nil,
          terminal_mode: terminal_mode(),
          buffer: InputBuffer.t(),
          mouse_enabled: boolean(),
          alt_screen: boolean(),
          raw_mode: boolean(),
          size: {pos_integer(), pos_integer()}
        }

  @typedoc """
  How raw mode was entered, and so how it is undone.

  `:nif` means the termios NIF holds the saved settings, `{:stty, saved}` means
  `stty` does and `saved` is the `stty -g` string, and `nil` means raw mode is not
  in force.
  """
  @type terminal_mode :: :nif | {:stty, binary()} | nil

  @doc """
  Start the driver and register it under this module's name.

  The name is fixed, so only one driver runs per node and every function in this
  module addresses it without being told which.

  Options:

    * `:event_manager` — process name or pid decoded events are cast to, default
      `Drafter.Event.Manager`

  The terminal is measured here but not altered; `setup/1` does that.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Put the terminal into TUI mode.

  Enters raw mode, switches to the alternate screen, hides the cursor, clears it,
  and enables mouse and bracketed-paste reporting. `mouse_opts` defaults to `[]`
  and is passed to `Drafter.Terminal.ANSI.enable_mouse/1`, whose only key is
  `:hover`.

  Terminal size is measured again on success, and `SIGWINCH` starts being watched.
  On a system where the signal cannot be watched, size is polled instead and a
  change is reported the same way.

  Returns `{:error, reason}` if raw mode could not be entered, leaving the terminal
  untouched. Input reading does not begin here; call `start_input/0`.
  """
  @spec setup(keyword()) :: :ok | {:error, term()}
  def setup(mouse_opts \\ []) do
    GenServer.call(__MODULE__, {:setup, mouse_opts})
  end

  @doc """
  Restore the terminal to the state it was in before `setup/1`.

  Disables bracketed paste and mouse reporting, shows the cursor, leaves the
  alternate screen, restores the saved terminal mode and stops the stdin reader.
  Safe to call when `setup/1` was never called or already undone.

  Mouse reporting is turned off as `Drafter.Terminal.ANSI.disable_mouse/1` does
  with its defaults, so it clears the any-motion mode that `setup/1` enables when
  `:hover` is left at `true`. Everything except the stdin reader is skipped when
  raw mode is not in force. The sequences are written straight to `/dev/tty` by
  `write_synchronously/1`, so they land even while the driver is shutting down.

  Also runs from `terminate/2`.
  """
  @spec cleanup() :: :ok
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end

  @doc """
  Write bytes to the terminal.

  Asynchronous. Bytes are discarded unless the terminal is in raw mode.
  """
  @spec write(iodata()) :: :ok
  def write(data) do
    GenServer.cast(__MODULE__, {:write, data})
  end

  @doc "The last known terminal size as `{cols, rows}`, without re-measuring."
  @spec get_size() :: {pos_integer(), pos_integer()}
  def get_size do
    GenServer.call(__MODULE__, :get_size)
  end

  @doc "Measure the terminal again and return the new `{cols, rows}`."
  @spec refresh_size() :: {pos_integer(), pos_integer()}
  def refresh_size do
    GenServer.call(__MODULE__, :refresh_size)
  end

  @doc """
  Discard stdin that has arrived but not been turned into events.

  Drops queued `{:stdin, _}` messages, flushes the operating system's input queue
  and empties the partial-sequence buffer. Nothing is emitted to the event manager.
  """
  @spec drain_pending_input() :: :ok
  def drain_pending_input do
    GenServer.call(__MODULE__, :drain_pending_input)
  end

  @doc """
  Start reading stdin and emitting events.

  Idempotent: a second call while a reader is running does nothing.
  """
  @spec start_input() :: :ok
  def start_input do
    GenServer.call(__MODULE__, :start_input)
  end

  @doc """
  The graphics protocol this terminal answered the startup probe with.

  Returns `{:ok, protocol}` where `protocol` is `:kitty`, `:iterm2`, `:sixel`, or
  `nil` for a terminal that answered naming none. Returns `:unprobed` when there
  was no terminal to ask, which is the caller's cue to fall back to guessing from
  the environment.

  Asking writes to the terminal and reads its answer, so call this after
  `start_input/0` and after any `drain_pending_input/0`, which would otherwise
  discard the answer. Blocks until the terminal answers or `timeout` passes, and
  never longer: a driver with no terminal replies at once, and one that fails to
  reply at all is reported as `:unprobed` rather than taking the caller down.
  """
  @spec probe(timeout()) :: {:ok, atom() | nil} | :unprobed
  def probe(timeout \\ @default_probe_timeout) do
    GenServer.call(__MODULE__, {:probe, timeout}, timeout + 5_000)
  catch
    :exit, _reason -> :unprobed
  end

  @doc """
  Turn mouse reporting on, if the terminal is in raw mode and it is currently off.

  `opts` defaults to `[]` and is passed to `Drafter.Terminal.ANSI.enable_mouse/1`,
  whose only key is `:hover`. Asynchronous, and silently does nothing when raw mode
  is not in force or reporting is already on.
  """
  @spec enable_mouse(keyword()) :: :ok
  def enable_mouse(opts \\ []) do
    GenServer.cast(__MODULE__, {:enable_mouse, opts})
  end

  @doc """
  Turn mouse reporting off, if the terminal is in raw mode and it is currently on.

  `opts` defaults to `[]` and is passed to `Drafter.Terminal.ANSI.disable_mouse/1`,
  whose only key is `:hover`; it must match what `enable_mouse/1` was given, or the
  mode that was set is not the mode that is cleared. Asynchronous, and silently does
  nothing when raw mode is not in force or reporting is already off.
  """
  @spec disable_mouse(keyword()) :: :ok
  def disable_mouse(opts \\ []) do
    GenServer.cast(__MODULE__, {:disable_mouse, opts})
  end

  @impl GenServer
  def init(opts) do
    event_manager = Keyword.get(opts, :event_manager, Event.Manager)

    state = %__MODULE__{
      shell_pid: nil,
      terminal_mode: nil,
      buffer: InputBuffer.new(),
      mouse_enabled: false,
      alt_screen: false,
      raw_mode: false,
      size: detect_terminal_size()
    }

    Process.put(:event_manager, event_manager)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:setup, mouse_opts}, _from, state) do
    case setup_terminal(state, mouse_opts) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:cleanup, _from, state) do
    new_state = cleanup_terminal(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:refresh_size, _from, state) do
    size = detect_terminal_size()
    {:reply, size, %{state | size: size}}
  end

  def handle_call(:drain_pending_input, _from, state) do
    drain_stdin_messages()
    flush_os_stdin_buffer()
    {:reply, :ok, %{state | buffer: InputBuffer.reset(state.buffer)}}
  end

  def handle_call(:start_input, _from, state) do
    if state.stdin_reader_pid do
      {:reply, :ok, state}
    else
      pid = setup_stdin()
      {:reply, :ok, %{state | stdin_reader_pid: pid}}
    end
  end

  def handle_call({:probe, _timeout}, _from, %__MODULE__{probe_result: {:ok, _} = done} = state) do
    {:reply, done, state}
  end

  def handle_call({:probe, _timeout}, _from, %__MODULE__{raw_mode: false} = state) do
    {:reply, :unprobed, state}
  end

  def handle_call({:probe, timeout}, from, state) do
    write_synchronously(Probe.query())
    Process.send_after(self(), :probe_deadline, timeout)

    {:noreply,
     %{state | probing: true, probe_replies: "", probe_waiters: [from | state.probe_waiters]}}
  end

  @impl GenServer
  def handle_cast({:write, data}, state) do
    if state.raw_mode do
      IO.write(data)
    end

    {:noreply, state}
  end

  def handle_cast({:enable_mouse, opts}, state) do
    if state.raw_mode and not state.mouse_enabled do
      IO.write(ANSI.enable_mouse(opts))
      {:noreply, %{state | mouse_enabled: true}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:disable_mouse, opts}, state) do
    if state.raw_mode and state.mouse_enabled do
      IO.write(ANSI.disable_mouse(opts))
      {:noreply, %{state | mouse_enabled: false}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:stdin, data}, %__MODULE__{probing: true} = state) do
    replies = state.probe_replies <> data

    if Probe.settled?(replies) do
      {:noreply, finish_probe(%{state | probe_replies: replies})}
    else
      {:noreply, %{state | probe_replies: replies}}
    end
  end

  def handle_info(:probe_deadline, %__MODULE__{probing: true} = state) do
    {:noreply, finish_probe(state)}
  end

  def handle_info(:probe_deadline, state), do: {:noreply, state}

  def handle_info({:stdin, data}, state) do
    if Drafter.Trace.enabled?(),
      do: Drafter.Trace.log(["S ", Drafter.Trace.ts(), " ", Base.encode16(data), "\n"])

    {events, buffer} = InputBuffer.feed(state.buffer, data)
    emit_events(events)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info(:input_flush, state) do
    {events, buffer} = InputBuffer.flush(state.buffer)
    emit_events(events)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info({:signal, :winch}, state) do
    new_size = detect_terminal_size()
    event_manager = Process.get(:event_manager)
    GenServer.cast(event_manager, {:event, {:resize, new_size}})

    {:noreply, %{state | size: new_size}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cleanup_terminal(state)
    :ok
  end

  defp setup_terminal(state, mouse_opts) do
    shell_pid = :shell.start_interactive({:noshell, :raw})

    case enter_terminal_mode() do
      {:ok, terminal_mode} ->
        maybe_stop_stdin_reader(state.stdin_reader_pid)
        setup_signal_handling()
        setup_exit_handler()

        IO.write([
          ANSI.enter_alt_screen(),
          ANSI.hide_cursor(),
          ANSI.clear_screen(),
          ANSI.enable_mouse(mouse_opts),
          "\e[?2004h"
        ])

        new_state = %{
          state
          | shell_pid: shell_pid,
            stdin_reader_pid: nil,
            terminal_mode: terminal_mode,
            raw_mode: true,
            alt_screen: true,
            mouse_enabled: true,
            size: detect_terminal_size()
        }

        {:ok, new_state}

      {:error, reason} ->
        maybe_stop_shell(shell_pid)
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end

  defp enter_terminal_mode do
    case :os.type() do
      {:unix, _} ->
        case nif_enter_raw_mode() do
          {:ok, _} -> {:ok, :nif}
          _ -> enter_terminal_mode_with_stty()
        end

      _ ->
        {:ok, nil}
    end
  end

  defp enter_terminal_mode_with_stty do
    with {saved_mode, 0} <- System.cmd("stty", ["-g"], stderr_to_stdout: true),
         {_, 0} <- System.cmd("stty", ["raw", "-echo", "-ixon"], stderr_to_stdout: true) do
      {:ok, {:stty, String.trim(saved_mode)}}
    else
      {output, _code} -> {:error, {:stty_failed, String.trim(output)}}
      other -> {:error, {:stty_failed, other}}
    end
  end

  defp setup_exit_handler do
    Process.flag(:trap_exit, true)
  end

  @doc """
  Write bytes to the controlling terminal and return once they have been handed over.

  Opens `/dev/tty` directly, bypassing the driver process and the Erlang IO server,
  so the bytes land even while the driver is shutting down. Falls back to `IO.write/1`
  when `/dev/tty` cannot be opened. An empty list writes nothing.
  """
  @spec write_synchronously(iodata()) :: :ok
  def write_synchronously([]), do: :ok

  def write_synchronously(iodata) do
    case :file.open(~c"/dev/tty", [:write, :raw, :binary]) do
      {:ok, tty} ->
        :file.write(tty, iodata)
        :file.close(tty)
        :ok

      {:error, _reason} ->
        IO.write(iodata)
        :ok
    end
  end

  defp cleanup_terminal(state) do
    TermiosNif.set_tui_inactive()

    if state.raw_mode do
      cleanup_sequences = []

      cleanup_sequences = cleanup_sequences ++ ["\e[?2004l"]

      cleanup_sequences =
        if state.mouse_enabled do
          cleanup_sequences ++ [ANSI.disable_mouse()]
        else
          cleanup_sequences
        end

      cleanup_sequences =
        if state.alt_screen do
          cleanup_sequences ++ [ANSI.show_cursor(), ANSI.exit_alt_screen()]
        else
          cleanup_sequences
        end

      write_synchronously(cleanup_sequences)

      restore_terminal_mode(state.terminal_mode)

      if state.shell_pid do
        maybe_stop_shell(state.shell_pid)
      end
    end

    maybe_stop_stdin_reader(state.stdin_reader_pid)

    %{
      state
      | raw_mode: false,
        alt_screen: false,
        mouse_enabled: false,
        shell_pid: nil,
        stdin_reader_pid: nil,
        terminal_mode: nil
    }
  end

  defp restore_terminal_mode(nil), do: :ok

  defp restore_terminal_mode(:nif) do
    _ = nif_exit_raw_mode()
    :ok
  end

  defp restore_terminal_mode({:stty, saved_mode}) do
    _ = System.cmd("stty", [saved_mode], stderr_to_stdout: true)
    :ok
  end

  defp maybe_stop_shell(nil), do: :ok

  defp maybe_stop_shell(shell_pid) do
    Process.exit(shell_pid, :normal)
  rescue
    _ -> :ok
  end

  defp nif_enter_raw_mode do
    {:ok, TermiosNif.enter_raw_mode()}
  catch
    :error, :undef -> :nif_not_loaded
  end

  defp nif_exit_raw_mode do
    TermiosNif.exit_raw_mode()
  catch
    :error, :undef -> :ok
  end

  defp setup_stdin do
    :io.setopts(:stdio, [:binary, {:encoding, :unicode}])
    spawn_link(&stdin_reader/0)
  end

  defp stdin_reader do
    case IO.read(:stdio, 1) do
      data when is_binary(data) ->
        send(__MODULE__, {:stdin, data})
        stdin_reader()

      _ ->
        :ok
    end
  end

  defp maybe_stop_stdin_reader(nil), do: :ok

  defp maybe_stop_stdin_reader(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp emit_events([]), do: :ok

  defp emit_events(events) do
    event_manager = Process.get(:event_manager)
    Enum.each(events, &GenServer.cast(event_manager, {:event, &1}))
  end

  defp finish_probe(state) do
    {protocol, leftover} = Probe.resolve(state.probe_replies)
    Enum.each(state.probe_waiters, &GenServer.reply(&1, {:ok, protocol}))

    {events, buffer} = InputBuffer.feed(state.buffer, leftover)
    emit_events(events)

    %{
      state
      | probing: false,
        probe_replies: "",
        probe_result: {:ok, protocol},
        probe_waiters: [],
        buffer: buffer
    }
  end

  defp drain_stdin_messages do
    receive do
      {:stdin, _} -> drain_stdin_messages()
    after
      0 -> :ok
    end
  end

  defp flush_os_stdin_buffer do
    case :os.type() do
      {:unix, _} ->
        try do
          TermiosNif.flush_stdin()
        catch
          :error, :undef -> :ok
          _, _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp setup_signal_handling do
    case :os.type() do
      {:unix, _} -> if watch_sigwinch() == :ok, do: :ok, else: start_size_poll()
      _ -> :ok
    end
  end

  defp start_size_poll do
    spawn_link(fn -> poll_terminal_size() end)
    :ok
  end

  defp watch_sigwinch do
    driver = self()
    :os.set_signal(:sigwinch, :handle)

    :gen_event.add_sup_handler(
      :erl_signal_server,
      {Drafter.Terminal.SignalWatcher, driver},
      driver
    )

    :ok
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp poll_terminal_size do
    initial_size = detect_terminal_size()
    poll_size_loop(initial_size)
  end

  defp poll_size_loop(last_size) do
    :timer.sleep(500)
    current_size = detect_terminal_size()

    if current_size != last_size do
      send(__MODULE__, {:signal, :winch})
      poll_size_loop(current_size)
    else
      poll_size_loop(last_size)
    end
  end

  defp detect_terminal_size do
    case :os.type() do
      {:win32, _} -> detect_terminal_size_windows()
      _ -> detect_terminal_size_unix()
    end
  end

  defp detect_terminal_size_unix do
    if System.get_env("DRAFTER_TPUT_SIZE") in [nil, ""] do
      with :error <- ioctl_terminal_size(),
           {cols, rows} when not (is_integer(cols) and is_integer(rows)) <-
             {io_size(:columns), io_size(:rows)} do
        tput_terminal_size()
      else
        {cols, rows} -> {cols, rows}
      end
    else
      tput_terminal_size()
    end
  end

  defp ioctl_terminal_size do
    case TermiosNif.get_winsize() do
      {:ok, {cols, rows, _xpixel, _ypixel}} when cols > 0 and rows > 0 -> {cols, rows}
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp io_size(dimension) do
    case apply(:io, dimension, [:standard_io]) do
      {:ok, n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp tput_terminal_size do
    case System.cmd("tput", ["cols"]) do
      {cols_str, 0} ->
        case System.cmd("tput", ["lines"]) do
          {lines_str, 0} ->
            {String.trim(cols_str) |> String.to_integer(),
             String.trim(lines_str) |> String.to_integer()}

          _ ->
            {80, 24}
        end

      _ ->
        {80, 24}
    end
  end

  defp detect_terminal_size_windows do
    with {"" <> cols_str, 0} <-
           System.cmd("powershell", ["-Command", "$Host.UI.RawUI.WindowSize.Width"]),
         {"" <> lines_str, 0} <-
           System.cmd("powershell", ["-Command", "$Host.UI.RawUI.WindowSize.Height"]),
         {cols, ""} <- Integer.parse(String.trim(cols_str)),
         {lines, ""} <- Integer.parse(String.trim(lines_str)) do
      {cols, lines}
    else
      _ -> {80, 24}
    end
  end
end
