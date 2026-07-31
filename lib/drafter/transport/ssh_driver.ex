defmodule Drafter.Transport.SSHDriver do
  @moduledoc false

  use GenServer

  alias Drafter.Terminal.{ANSI, Driver, InputBuffer}

  defstruct [:event_manager, :size, buffer: %InputBuffer{}, raw_mode: false, mouse_enabled: false]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec setup(pid(), pid()) :: :ok
  def setup(server, event_manager), do: GenServer.call(server, {:setup, event_manager})

  @spec cleanup(pid()) :: :ok
  def cleanup(server), do: GenServer.call(server, :cleanup)

  @spec write(pid(), iodata()) :: :ok
  def write(server, data), do: GenServer.cast(server, {:write, data})

  @spec get_size(pid()) :: {pos_integer(), pos_integer()}
  def get_size(server), do: GenServer.call(server, :get_size)

  @impl GenServer
  def init(opts) do
    gl = Keyword.fetch!(opts, :group_leader)
    Process.group_leader(self(), gl)
    size = detect_size()
    {:ok, %__MODULE__{size: size, buffer: InputBuffer.new()}}
  end

  @impl GenServer
  def handle_call({:setup, event_manager}, _from, state) do
    :io.setopts([:binary, {:encoding, :unicode}, {:echo, false}])
    size = detect_size()

    IO.write([
      ANSI.enter_alt_screen(),
      ANSI.clear_screen(),
      ANSI.cursor_to(1, 1),
      ANSI.hide_cursor(),
      ANSI.enable_mouse()
    ])

    driver_pid = self()
    spawn_link(fn -> stdin_reader(driver_pid) end)
    spawn_link(fn -> size_poller(driver_pid, size) end)

    {:reply, :ok,
     %{state | event_manager: event_manager, size: size, raw_mode: true, mouse_enabled: true}}
  end

  def handle_call(:cleanup, _from, state) do
    if state.raw_mode do
      Driver.write_synchronously([
        ANSI.disable_mouse(),
        ANSI.show_cursor(),
        ANSI.exit_alt_screen()
      ])
    end

    {:reply, :ok, %{state | raw_mode: false, mouse_enabled: false}}
  end

  def handle_call(:get_size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:driver_get_size, _from, state) do
    {:reply, state.size, state}
  end

  @impl GenServer
  def handle_cast({:write, data}, state) do
    if state.raw_mode, do: IO.write(data)
    {:noreply, state}
  end

  def handle_cast({:driver_write, data}, state) do
    if state.raw_mode, do: IO.write(data)
    {:noreply, state}
  end

  def handle_cast({:set_event_manager, em_pid}, state) do
    {:noreply, %{state | event_manager: em_pid}}
  end

  @impl GenServer
  def handle_info({:stdin, data}, state) do
    {events, buffer} = InputBuffer.feed(state.buffer, data)
    emit_events(state.event_manager, events)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info(:input_flush, state) do
    {events, buffer} = InputBuffer.flush(state.buffer)
    emit_events(state.event_manager, events)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info({:resize, new_size}, state) do
    if state.event_manager do
      GenServer.cast(state.event_manager, {:event, {:resize, new_size}})
    end

    {:noreply, %{state | size: new_size}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp emit_events(nil, _events), do: :ok
  defp emit_events(_event_manager, []), do: :ok

  defp emit_events(event_manager, events) do
    Enum.each(events, &GenServer.cast(event_manager, {:event, &1}))
  end

  defp detect_size do
    case {:io.columns(), :io.rows()} do
      {{:ok, cols}, {:ok, rows}} -> {cols, rows}
      _ -> {80, 24}
    end
  end

  defp stdin_reader(driver_pid) do
    case IO.binread(:stdio, 1) do
      :eof ->
        :ok

      {:error, _} ->
        send(driver_pid, {:stdin, "\x03"})
        stdin_reader(driver_pid)

      "\e" ->
        read_escape_sequence(driver_pid, "\e")

      data when is_binary(data) ->
        send(driver_pid, {:stdin, data})
        stdin_reader(driver_pid)
    end
  end

  defp read_escape_sequence(driver_pid, buffer) do
    receive do
      :escape_timeout ->
        send(driver_pid, {:stdin, buffer})
        stdin_reader(driver_pid)
    after
      0 ->
        case IO.binread(:stdio, 1) do
          :eof ->
            send(driver_pid, {:stdin, buffer})

          {:error, _} ->
            send(driver_pid, {:stdin, buffer})
            stdin_reader(driver_pid)

          "[" ->
            read_csi_sequence(driver_pid, buffer <> "[")

          char when is_binary(char) ->
            send(driver_pid, {:stdin, buffer <> char})
            stdin_reader(driver_pid)
        end
    end
  end

  defp read_csi_sequence(driver_pid, buffer) do
    case IO.binread(:stdio, 1) do
      :eof ->
        send(driver_pid, {:stdin, buffer})

      {:error, _} ->
        send(driver_pid, {:stdin, buffer})
        stdin_reader(driver_pid)

      char when is_binary(char) ->
        new_buf = buffer <> char

        cond do
          String.match?(char, ~r/[a-zA-Z~]/) ->
            send(driver_pid, {:stdin, new_buf})
            stdin_reader(driver_pid)

          char == "<" ->
            read_sgr_mouse_sequence(driver_pid, new_buf)

          true ->
            read_csi_sequence(driver_pid, new_buf)
        end
    end
  end

  defp read_sgr_mouse_sequence(driver_pid, buffer) do
    case IO.binread(:stdio, 1) do
      :eof ->
        send(driver_pid, {:stdin, buffer})

      {:error, _} ->
        send(driver_pid, {:stdin, buffer})
        stdin_reader(driver_pid)

      char when is_binary(char) ->
        new_buf = buffer <> char

        if char in ["M", "m"] do
          send(driver_pid, {:stdin, new_buf})
          stdin_reader(driver_pid)
        else
          read_sgr_mouse_sequence(driver_pid, new_buf)
        end
    end
  end

  defp size_poller(driver_pid, last_size) do
    :timer.sleep(500)

    if Process.alive?(driver_pid) do
      current = detect_size()
      if current != last_size, do: send(driver_pid, {:resize, current})
      size_poller(driver_pid, current)
    end
  end
end
