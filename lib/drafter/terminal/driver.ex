defmodule Drafter.Terminal.Driver do
  @moduledoc false

  use GenServer

  alias Drafter.Event
  alias Drafter.Terminal.{ANSI, TermiosNif}

  defstruct [
    :shell_pid,
    :stdin_reader_pid,
    :terminal_mode,
    buffer: "",
    mouse_enabled: false,
    alt_screen: false,
    raw_mode: false,
    size: {80, 24}
  ]

  @type state :: %__MODULE__{
          shell_pid: pid() | nil,
          stdin_reader_pid: pid() | nil,
          terminal_mode: terminal_mode(),
          buffer: binary(),
          mouse_enabled: boolean(),
          alt_screen: boolean(),
          raw_mode: boolean(),
          size: {pos_integer(), pos_integer()}
        }

  @type terminal_mode :: :nif | {:stty, binary()} | nil

  @doc "Start the terminal driver"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Setup terminal for TUI mode"
  @spec setup() :: :ok | {:error, term()}
  def setup(mouse_opts \\ []) do
    GenServer.call(__MODULE__, {:setup, mouse_opts})
  end

  @doc "Cleanup and restore terminal"
  @spec cleanup() :: :ok
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end

  @doc "Write output to terminal"
  @spec write(iodata()) :: :ok
  def write(data) do
    GenServer.cast(__MODULE__, {:write, data})
  end

  @doc "Get current terminal size"
  @spec get_size() :: {pos_integer(), pos_integer()}
  def get_size do
    GenServer.call(__MODULE__, :get_size)
  end

  @doc "Discard any pending stdin input not yet processed"
  @spec drain_pending_input() :: :ok
  def drain_pending_input do
    GenServer.call(__MODULE__, :drain_pending_input)
  end

  @doc "Begin reading stdin — call once after startup drain sequence"
  @spec start_input() :: :ok
  def start_input do
    GenServer.call(__MODULE__, :start_input)
  end

  @doc "Enable mouse events"
  @spec enable_mouse(keyword()) :: :ok
  def enable_mouse(opts \\ []) do
    GenServer.cast(__MODULE__, {:enable_mouse, opts})
  end

  @doc "Disable mouse events"
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
      buffer: "",
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

  def handle_call(:drain_pending_input, _from, state) do
    drain_stdin_messages()
    flush_os_stdin_buffer()
    {:reply, :ok, %{state | buffer: ""}}
  end

  def handle_call(:start_input, _from, state) do
    if state.stdin_reader_pid do
      {:reply, :ok, state}
    else
      pid = setup_stdin()
      {:reply, :ok, %{state | stdin_reader_pid: pid}}
    end
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
  def handle_info({:stdin, data}, state) do
    new_buffer = state.buffer <> data
    {events, remaining_buffer} = ANSI.parse_sequence(new_buffer)

    event_manager = Process.get(:event_manager)

    Enum.each(events, fn event ->
      GenServer.cast(event_manager, {:event, event})
    end)

    {:noreply, %{state | buffer: remaining_buffer}}
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

      if cleanup_sequences != 0 do
        IO.write(cleanup_sequences)
        Process.sleep(50)
      end

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
    spawn_link(fn -> stdin_reader() end)
  end

  defp maybe_stop_stdin_reader(nil), do: :ok

  defp maybe_stop_stdin_reader(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
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

  defp stdin_reader do
    case IO.read(:stdio, 1) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      "\e" ->
        read_escape_sequence("\e")

      data when is_binary(data) ->
        send(__MODULE__, {:stdin, data})
        stdin_reader()
    end
  end

  defp read_escape_sequence(buffer) do
    drain_stale_escape_timeouts()
    timer_ref = Process.send_after(self(), :escape_timeout, 100)

    case IO.read(:stdio, 1) do
      :eof ->
        cancel_escape_timer(timer_ref)
        send(__MODULE__, {:stdin, buffer})

      {:error, _} ->
        cancel_escape_timer(timer_ref)
        send(__MODULE__, {:stdin, buffer})
        stdin_reader()

      "[" ->
        cancel_escape_timer(timer_ref)
        read_csi_sequence(buffer <> "[")

      char when is_binary(char) ->
        cancel_escape_timer(timer_ref)
        send(__MODULE__, {:stdin, buffer <> char})
        stdin_reader()
    end
  end

  defp drain_stale_escape_timeouts do
    receive do
      :escape_timeout -> drain_stale_escape_timeouts()
    after
      0 -> :ok
    end
  end

  defp cancel_escape_timer(timer_ref) do
    Process.cancel_timer(timer_ref)

    receive do
      :escape_timeout -> :ok
    after
      0 -> :ok
    end
  end

  defp read_csi_sequence(buffer) do
    case IO.read(:stdio, 1) do
      :eof ->
        send(__MODULE__, {:stdin, buffer})

      {:error, _} ->
        send(__MODULE__, {:stdin, buffer})
        stdin_reader()

      "<" ->
        read_sgr_mouse_sequence(buffer <> "<")

      char when is_binary(char) ->
        dispatch_csi_char(buffer <> char, char)
    end
  end

  defp dispatch_csi_char(buffer, <<byte>> ) when byte in ?a..?z or byte in ?A..?Z or byte == ?~ do
    send(__MODULE__, {:stdin, buffer})
    stdin_reader()
  end

  defp dispatch_csi_char(buffer, _char), do: read_csi_sequence(buffer)

  defp read_sgr_mouse_sequence(buffer) do
    case IO.read(:stdio, 1) do
      :eof ->
        send(__MODULE__, {:stdin, buffer})

      {:error, _} ->
        send(__MODULE__, {:stdin, buffer})
        stdin_reader()

      char when char == "M" or char == "m" ->
        send(__MODULE__, {:stdin, buffer <> char})
        stdin_reader()

      char when is_binary(char) ->
        read_sgr_mouse_sequence(buffer <> char)
    end
  end

  defp setup_signal_handling do
    case :os.type() do
      {:unix, _} ->
        spawn_link(fn -> poll_terminal_size() end)

      _ ->
        :ok
    end
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
