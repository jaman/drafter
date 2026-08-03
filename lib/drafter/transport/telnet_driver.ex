defmodule Drafter.Transport.TelnetDriver do
  @moduledoc false

  use GenServer

  alias Drafter.Terminal.{ANSI, InputBuffer, Probe}

  @iac 255
  @telnet_do 253
  @telnet_dont 254
  @telnet_will 251
  @telnet_wont 252
  @telnet_sb 250
  @telnet_se 240
  @telnet_naws 31
  @telnet_echo 1
  @telnet_sga 3
  @telnet_ttype 24
  @telnet_ttype_is 0
  @telnet_ttype_send 1
  @telnet_commands [@telnet_do, @telnet_dont, @telnet_will, @telnet_wont]

  @default_env_timeout 250
  @default_probe_timeout 250

  defstruct [
    :socket,
    :event_manager,
    :size,
    :session,
    raw_mode: false,
    input_buffer: "",
    terminal_env: %{},
    env_waiters: []
  ]

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

  @doc """
  The connected client's terminal environment, once it has answered.

  Blocks until the client's TERMINAL-TYPE reply arrives or `timeout` milliseconds
  pass, whichever comes first, and returns what is known by then — an empty map
  for a client that does not answer. Call it after `setup/2`, which is what asks.
  """
  @spec terminal_env(pid(), timeout()) :: %{String.t() => String.t()}
  def terminal_env(server, timeout \\ @default_env_timeout) do
    GenServer.call(server, {:terminal_env, timeout}, timeout + 5_000)
  end

  @doc """
  Ask the connected client's terminal which graphics protocol it supports.

  Returns `:kitty`, `:iterm2`, `:sixel`, or `nil` for a client that names none.
  Call it after `setup/2` and before the app starts reading input.
  """
  @spec probe(pid(), timeout()) :: {:ok, atom() | nil} | :unprobed
  def probe(server, timeout \\ @default_probe_timeout) do
    GenServer.call(server, {:probe, timeout}, timeout + 5_000)
  catch
    :exit, _reason -> :unprobed
  end

  @impl GenServer
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    :inet.setopts(socket, [{:active, true}])
    {:ok, %__MODULE__{socket: socket, session: Keyword.get(opts, :session), size: {80, 24}}}
  end

  @impl GenServer
  def handle_call({:setup, event_manager}, _from, state) do
    negotiate_telnet_options(state.socket)

    send_raw(state.socket, [
      ANSI.enter_alt_screen(),
      ANSI.hide_cursor(),
      ANSI.clear_screen(),
      ANSI.enable_mouse()
    ])

    {:reply, :ok, %{state | event_manager: event_manager, raw_mode: true}}
  end

  def handle_call({:probe, timeout}, _from, state) do
    :inet.setopts(state.socket, [{:active, false}])

    write = fn data -> :gen_tcp.send(state.socket, IO.iodata_to_binary(data)) end
    read = fn slice -> recv_slice(state.socket, slice) end

    {protocol, leftover} = Probe.run(write, read, timeout: timeout)

    :inet.setopts(state.socket, [{:active, true}])

    {:reply, {:ok, protocol}, %{state | input_buffer: state.input_buffer <> leftover}}
  end

  def handle_call({:terminal_env, _timeout}, _from, %__MODULE__{terminal_env: env} = state)
      when map_size(env) > 0 do
    {:reply, env, state}
  end

  def handle_call({:terminal_env, timeout}, from, state) do
    Process.send_after(self(), {:terminal_env_timeout, from}, timeout)
    {:noreply, %{state | env_waiters: [from | state.env_waiters]}}
  end

  def handle_call(:cleanup, _from, state) do
    if state.raw_mode do
      :inet.setopts(state.socket, [{:linger, {true, 2}}])
      send_raw(state.socket, [ANSI.disable_mouse(), ANSI.show_cursor(), ANSI.exit_alt_screen()])
    end

    :gen_tcp.close(state.socket)
    {:reply, :ok, %{state | raw_mode: false}}
  end

  def handle_call(:get_size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:driver_get_size, _from, state) do
    {:reply, state.size, state}
  end

  @impl GenServer
  def handle_cast({:write, data}, state) do
    if state.raw_mode, do: send_raw(state.socket, data)
    {:noreply, state}
  end

  def handle_cast({:driver_write, data}, state) do
    if state.raw_mode, do: send_raw(state.socket, data)
    {:noreply, state}
  end

  def handle_cast({:set_event_manager, em_pid}, state) do
    {:noreply, %{state | event_manager: em_pid}}
  end

  @impl GenServer
  def handle_info({:tcp, _socket, data}, state) do
    {events, new_size, new_buffer, signals} =
      parse_telnet_data(data, state.input_buffer, state.size)

    schedule_input_flush(new_buffer)
    state = Enum.reduce(signals, state, &apply_signal/2)
    new_state = %{state | input_buffer: new_buffer, size: new_size}

    if state.event_manager do
      if new_size != state.size do
        GenServer.cast(state.event_manager, {:event, {:resize, new_size}})
      end

      Enum.each(events, &GenServer.cast(state.event_manager, {:event, &1}))
    end

    {:noreply, new_state}
  end

  def handle_info(:input_flush, state) do
    {events, remaining} = ANSI.flush_sequence(state.input_buffer)

    if state.event_manager do
      Enum.each(events, &GenServer.cast(state.event_manager, {:event, &1}))
    end

    {:noreply, %{state | input_buffer: remaining}}
  end

  def handle_info({:terminal_env_timeout, from}, state) do
    if from in state.env_waiters do
      GenServer.reply(from, state.terminal_env)
      {:noreply, %{state | env_waiters: List.delete(state.env_waiters, from)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, end_session(state)}
  end

  def handle_info({:tcp_error, _socket, _reason}, state) do
    {:stop, :normal, end_session(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp negotiate_telnet_options(socket) do
    iac = @iac
    will = @telnet_will
    do_cmd = @telnet_do
    echo = @telnet_echo
    sga = @telnet_sga
    naws = @telnet_naws
    ttype = @telnet_ttype

    payload = <<iac, will, echo, iac, will, sga, iac, do_cmd, naws, iac, do_cmd, ttype>>
    :gen_tcp.send(socket, payload)
  end

  defp end_session(%__MODULE__{session: session} = state) when is_pid(session) do
    send(session, :shutdown)
    %{state | session: nil}
  end

  defp end_session(state), do: state

  defp send_raw(socket, data) do
    :gen_tcp.send(socket, IO.iodata_to_binary(data))
  end

  defp schedule_input_flush(""), do: :ok

  defp schedule_input_flush(_pending) do
    Process.send_after(self(), :input_flush, InputBuffer.flush_after_ms())
    :ok
  end

  defp parse_telnet_data(data, buffer, current_size) do
    combined = buffer <> data
    {clean_data, new_size, signals} = strip_iac(combined, current_size, [])
    {events, remaining} = ANSI.parse_sequence(clean_data)
    {events, new_size, remaining, Enum.reverse(signals)}
  end

  defp strip_iac(
         <<@iac, @telnet_sb, @telnet_naws, w_high, w_low, h_high, h_low, @iac, @telnet_se,
           rest::binary>>,
         _size,
         signals
       ) do
    width = w_high * 256 + w_low
    height = h_high * 256 + h_low
    strip_iac(rest, {width, height}, signals)
  end

  defp strip_iac(
         <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_is, rest::binary>>,
         size,
         signals
       ) do
    case take_subnegotiation(rest, "") do
      {name, remainder} -> strip_iac(remainder, size, [{:terminal_type, name} | signals])
      :incomplete -> {<<>>, size, signals}
    end
  end

  defp strip_iac(<<@iac, @telnet_will, @telnet_ttype, rest::binary>>, size, signals) do
    strip_iac(rest, size, [:ask_terminal_type | signals])
  end

  defp strip_iac(<<@iac, cmd, _opt, rest::binary>>, size, signals)
       when cmd in @telnet_commands do
    strip_iac(rest, size, signals)
  end

  defp strip_iac(<<@iac, _cmd, rest::binary>>, size, signals) do
    strip_iac(rest, size, signals)
  end

  defp strip_iac(<<byte, rest::binary>>, size, signals) do
    {clean, final_size, final_signals} = strip_iac(rest, size, signals)
    {<<byte>> <> clean, final_size, final_signals}
  end

  defp strip_iac(<<>>, size, signals), do: {<<>>, size, signals}

  defp recv_slice(socket, slice) do
    case :gen_tcp.recv(socket, 0, slice) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :timeout} -> :timeout
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_subnegotiation(<<@iac, @telnet_se, rest::binary>>, acc), do: {acc, rest}

  defp take_subnegotiation(<<byte, rest::binary>>, acc),
    do: take_subnegotiation(rest, acc <> <<byte>>)

  defp take_subnegotiation(<<>>, _acc), do: :incomplete

  defp apply_signal(:ask_terminal_type, state) do
    send_raw(
      state.socket,
      <<@iac, @telnet_sb, @telnet_ttype, @telnet_ttype_send, @iac, @telnet_se>>
    )

    state
  end

  defp apply_signal({:terminal_type, name}, state) do
    env = Map.put(state.terminal_env, "TERM", String.downcase(name))
    Enum.each(state.env_waiters, &GenServer.reply(&1, env))
    %{state | terminal_env: env, env_waiters: []}
  end
end
