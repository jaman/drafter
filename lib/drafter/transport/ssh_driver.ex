defmodule Drafter.Transport.SSHDriver do
  @moduledoc false

  use GenServer

  alias Drafter.Terminal.{ANSI, InputBuffer, KittyKeyboard, Probe, Reports}

  defstruct [
    :event_manager,
    :size,
    :session,
    buffer: %InputBuffer{},
    raw_mode: false,
    mouse_enabled: false,
    key_release: false,
    probing: false,
    probe_replies: "",
    probe_result: :unprobed,
    probe_waiters: []
  ]

  @default_probe_timeout 250

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec setup(pid(), pid(), keyword()) :: :ok
  def setup(server, event_manager, opts \\ []),
    do: GenServer.call(server, {:setup, event_manager, opts})

  @spec cleanup(pid()) :: :ok
  def cleanup(server), do: GenServer.call(server, :cleanup)

  @doc """
  The graphics protocol the connected client's terminal answered with.

  Blocks until the answer arrives or the probe's deadline passes. Returns
  `:kitty`, `:iterm2`, `:sixel`, or `nil` for a terminal naming none. `setup/2` is
  what asks, so call this after it.
  """
  @spec probe(pid(), timeout()) :: {:ok, atom() | nil} | :unprobed
  def probe(server, timeout \\ @default_probe_timeout) do
    GenServer.call(server, :probe_result, timeout + 5_000)
  catch
    :exit, _reason -> :unprobed
  end

  @spec write(pid(), iodata()) :: :ok
  def write(server, data), do: GenServer.call(server, {:driver_write, data}, :infinity)

  @spec get_size(pid()) :: {pos_integer(), pos_integer()}
  def get_size(server), do: GenServer.call(server, :get_size)

  @impl GenServer
  def init(opts) do
    gl = Keyword.fetch!(opts, :group_leader)
    Process.group_leader(self(), gl)
    size = detect_size()

    {:ok,
     %__MODULE__{size: size, buffer: InputBuffer.new(), session: Keyword.get(opts, :session)}}
  end

  @impl GenServer
  def handle_call({:setup, event_manager, opts}, _from, state) do
    :io.setopts([:binary, {:encoding, :unicode}, {:echo, false}])
    size = detect_size()
    key_release = Keyword.get(opts, :key_release, false)

    IO.write([
      ANSI.enter_alt_screen(),
      ANSI.clear_screen(),
      ANSI.cursor_to(1, 1),
      ANSI.hide_cursor(),
      ANSI.enable_mouse(),
      keyboard_protocol_on(key_release),
      cell_size_query(Keyword.get(opts, :cell_size, false))
    ])

    driver_pid = self()
    spawn_link(fn -> stdin_reader(driver_pid) end)
    spawn_link(fn -> size_poller(driver_pid, size) end)

    IO.write(Probe.query())
    Process.send_after(driver_pid, :probe_deadline, @default_probe_timeout)

    {:reply, :ok,
     %{
       state
       | event_manager: event_manager,
         size: size,
         raw_mode: true,
         mouse_enabled: true,
         key_release: key_release,
         buffer: InputBuffer.new(key_release: key_release),
         probing: true
     }}
  end

  def handle_call(:probe_result, _from, %__MODULE__{probe_result: {:ok, _} = done} = state) do
    {:reply, done, state}
  end

  def handle_call(:probe_result, from, %__MODULE__{probing: true} = state) do
    {:noreply, %{state | probe_waiters: [from | state.probe_waiters]}}
  end

  def handle_call(:probe_result, _from, state), do: {:reply, :unprobed, state}

  def handle_call(:cleanup, _from, state) do
    if state.raw_mode do
      IO.write([
        keyboard_protocol_off(state.key_release),
        ANSI.disable_mouse(),
        ANSI.show_cursor(),
        ANSI.exit_alt_screen()
      ])
    end

    {:reply, :ok, %{state | raw_mode: false, mouse_enabled: false, key_release: false}}
  end

  def handle_call({:driver_write, data}, _from, state) do
    if state.raw_mode, do: IO.write(data)
    {:reply, :ok, state}
  end

  def handle_call(:get_size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:driver_get_size, _from, state) do
    {:reply, state.size, state}
  end

  @impl GenServer
  def handle_cast({:set_event_manager, em_pid}, state) do
    {:noreply, %{state | event_manager: em_pid}}
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

  def handle_info({:stdin, data}, state) do
    {events, buffer} = InputBuffer.feed(state.buffer, data)
    emit_events(state.event_manager, events)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info(:stdin_closed, %{session: session} = state) do
    if is_pid(session), do: send(session, :shutdown)
    {:noreply, %{state | session: nil}}
  end

  def handle_info(:probe_deadline, %__MODULE__{probing: true} = state) do
    {:noreply, finish_probe(state)}
  end

  def handle_info(:probe_deadline, state), do: {:noreply, state}

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

  defp keyboard_protocol_on(true), do: [KittyKeyboard.push(), KittyKeyboard.query()]
  defp keyboard_protocol_on(false), do: []

  defp cell_size_query(true), do: [Reports.cell_size_query()]
  defp cell_size_query(false), do: []

  defp keyboard_protocol_off(true), do: [KittyKeyboard.pop()]
  defp keyboard_protocol_off(false), do: []

  defp finish_probe(state) do
    {protocol, leftover} = Probe.resolve(state.probe_replies)
    Enum.each(state.probe_waiters, &GenServer.reply(&1, {:ok, protocol}))

    {events, buffer} = InputBuffer.feed(state.buffer, leftover)
    emit_events(state.event_manager, events)

    %{
      state
      | probing: false,
        probe_replies: "",
        probe_result: {:ok, protocol},
        probe_waiters: [],
        buffer: buffer
    }
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
        send(driver_pid, :stdin_closed)

      {:error, _} ->
        send(driver_pid, :stdin_closed)

      data when is_binary(data) ->
        send(driver_pid, {:stdin, data})
        stdin_reader(driver_pid)
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
