defmodule Drafter.Transport.TelnetDriver do
  @moduledoc false

  use GenServer

  alias Drafter.Terminal.{ANSI, InputBuffer}

  @iac 255
  @telnet_do 253
  @telnet_will 251
  @telnet_sb 250
  @telnet_se 240
  @telnet_naws 31
  @telnet_echo 1
  @telnet_sga 3

  defstruct [:socket, :event_manager, :size, :session, raw_mode: false, input_buffer: ""]

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
    {events, new_size, new_buffer} = parse_telnet_data(data, state.input_buffer, state.size)
    schedule_input_flush(new_buffer)
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

    payload = <<iac, will, echo, iac, will, sga, iac, do_cmd, naws>>
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
    {clean_data, new_size} = strip_iac(combined, current_size)
    {events, remaining} = ANSI.parse_sequence(clean_data)
    {events, new_size, remaining}
  end

  defp strip_iac(
         <<@iac, @telnet_sb, @telnet_naws, w_high, w_low, h_high, h_low, @iac, @telnet_se,
           rest::binary>>,
         _size
       ) do
    width = w_high * 256 + w_low
    height = h_high * 256 + h_low
    strip_iac(rest, {width, height})
  end

  defp strip_iac(<<@iac, cmd, _opt, rest::binary>>, size)
       when cmd in [@telnet_do, @telnet_will, @telnet_sga] do
    strip_iac(rest, size)
  end

  defp strip_iac(<<@iac, _cmd, rest::binary>>, size) do
    strip_iac(rest, size)
  end

  defp strip_iac(<<byte, rest::binary>>, size) do
    {clean, final_size} = strip_iac(rest, size)
    {<<byte>> <> clean, final_size}
  end

  defp strip_iac(<<>>, size), do: {<<>>, size}
end
