defmodule Drafter.Transport.SSHChannel do
  @moduledoc false

  @behaviour :ssh_server_channel

  alias Drafter.{Compositor, Event, EventHandler, ScreenManager, Session, ThemeManager}
  alias Drafter.Terminal.{ANSI, InputBuffer}

  defstruct [
    :conn_ref,
    :channel_id,
    :event_manager,
    :app_module,
    :mode,
    :mount_props,
    size: {80, 24},
    raw_mode: false,
    buffer: %InputBuffer{}
  ]

  @spec write(pid(), iodata()) :: :ok
  def write(channel_pid, data) do
    send(channel_pid, {:write_output, data})
    :ok
  end

  @spec get_size(pid()) :: {pos_integer(), pos_integer()}
  def get_size(channel_pid) do
    ref = make_ref()
    send(channel_pid, {:get_size, self(), ref})

    receive do
      {:size_reply, ^ref, size} -> size
    after
      5_000 -> {80, 24}
    end
  end

  @spec setup(pid(), pid()) :: :ok
  def setup(channel_pid, event_manager) do
    ref = make_ref()
    send(channel_pid, {:setup, event_manager, self(), ref})

    receive do
      {:setup_done, ^ref} -> :ok
    after
      5_000 -> :ok
    end
  end

  @spec cleanup(pid()) :: :ok
  def cleanup(channel_pid) do
    send(channel_pid, :cleanup)
    :ok
  end

  @impl :ssh_server_channel
  def init(opts) do
    app_module = Keyword.fetch!(opts, :app_module)
    mode = Keyword.get(opts, :mode, :isolated)
    mount_props = Keyword.get(opts, :mount_props, %{})
    Process.flag(:trap_exit, true)

    {:ok,
     %__MODULE__{
       app_module: app_module,
       mode: mode,
       mount_props: mount_props
     }}
  end

  @impl :ssh_server_channel
  def handle_ssh_msg(
        {:ssh_cm, conn_ref, {:pty, channel_id, want_reply, {_term, width, height, _, _, _}}},
        state
      ) do
    :ssh_connection.reply_request(conn_ref, want_reply, :success, channel_id)
    size = if width > 0 and height > 0, do: {width, height}, else: {80, 24}
    {:ok, %{state | conn_ref: conn_ref, channel_id: channel_id, size: size}}
  end

  def handle_ssh_msg({:ssh_cm, conn_ref, {:shell, channel_id, want_reply}}, state) do
    :ssh_connection.reply_request(conn_ref, want_reply, :success, channel_id)
    send(self(), :start_session)
    {:ok, %{state | conn_ref: conn_ref, channel_id: channel_id}}
  end

  def handle_ssh_msg({:ssh_cm, _conn_ref, {:data, _channel_id, _type, data}}, state) do
    {events, buffer} = InputBuffer.feed(state.buffer, data)
    emit_events(state.event_manager, events)
    {:ok, %{state | buffer: buffer}}
  end

  def handle_ssh_msg(
        {:ssh_cm, _conn_ref, {:window_change, _channel_id, width, height, _, _}},
        state
      ) do
    size = {width, height}

    if state.event_manager do
      GenServer.cast(state.event_manager, {:event, {:resize, size}})
    end

    {:ok, %{state | size: size}}
  end

  def handle_ssh_msg({:ssh_cm, _conn_ref, {:eof, _channel_id}}, state) do
    {:ok, state}
  end

  def handle_ssh_msg(_msg, state), do: {:ok, state}

  @impl :ssh_server_channel
  def handle_msg(:start_session, state) do
    channel_pid = self()
    username = get_username(state.conn_ref)
    full_props = Map.put(state.mount_props, :username, username)

    spawn_link(fn ->
      session_ctx = start_session_services(channel_pid)
      setup(channel_pid, session_ctx.event_manager)
      Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)
      session_opts = build_session_opts(state.app_module, state.mode, full_props)

      try do
        Drafter.run_session(state.app_module, session_ctx, session_opts)
      after
        cleanup(channel_pid)
        stop_session_services(session_ctx)
      end
    end)

    {:ok, state}
  end

  def handle_msg({:write_output, data}, state) do
    if state.raw_mode and state.conn_ref do
      :ssh_connection.send(state.conn_ref, state.channel_id, IO.iodata_to_binary(data))
    end

    {:ok, state}
  end

  def handle_msg({:get_size, from, ref}, state) do
    send(from, {:size_reply, ref, state.size})
    {:ok, state}
  end

  def handle_msg({:setup, event_manager, from, ref}, state) do
    send_to_client(state, [
      ANSI.enter_alt_screen(),
      ANSI.hide_cursor(),
      ANSI.clear_screen(),
      ANSI.enable_mouse()
    ])

    send(from, {:setup_done, ref})
    {:ok, %{state | event_manager: event_manager, raw_mode: true}}
  end

  def handle_msg(:cleanup, state) do
    send_to_client(state, [
      ANSI.disable_mouse(),
      ANSI.show_cursor(),
      ANSI.exit_alt_screen()
    ])

    {:ok, %{state | raw_mode: false, event_manager: nil}}
  end

  def handle_msg({:EXIT, _pid, :normal}, state) do
    {:stop, state.channel_id, state}
  end

  def handle_msg({:EXIT, _pid, _reason}, state) do
    send_to_client(state, [
      ANSI.disable_mouse(),
      ANSI.show_cursor(),
      ANSI.exit_alt_screen()
    ])

    {:stop, state.channel_id, state}
  end

  def handle_msg(:input_flush, state) do
    {events, buffer} = InputBuffer.flush(state.buffer)
    emit_events(state.event_manager, events)
    {:ok, %{state | buffer: buffer}}
  end

  def handle_msg(_msg, state), do: {:ok, state}

  defp emit_events(nil, _events), do: :ok
  defp emit_events(_event_manager, []), do: :ok

  defp emit_events(event_manager, events) do
    Enum.each(events, &GenServer.cast(event_manager, {:event, &1}))
  end

  @impl :ssh_server_channel
  def terminate(_reason, _state), do: :ok

  defp send_to_client(%{conn_ref: nil}, _sequences), do: :ok
  defp send_to_client(%{channel_id: nil}, _sequences), do: :ok

  defp send_to_client(state, sequences) do
    data = IO.iodata_to_binary(sequences)
    :ssh_connection.send(state.conn_ref, state.channel_id, data)
  end

  defp get_username(conn_ref) do
    case :ssh.connection_info(conn_ref, [:user]) do
      [{:user, username}] -> to_string(username)
      _ -> "guest"
    end
  end

  defp start_session_services(channel_pid) do
    {:ok, em} = Event.Manager.start_link(name: nil)

    {:ok, comp} =
      Compositor.start_link(
        name: nil,
        terminal_driver: {__MODULE__, channel_pid},
        event_manager: em
      )

    {:ok, tm} = ThemeManager.start_link(name: nil)
    {:ok, eh} = EventHandler.start_link(name: nil)
    {:ok, sm} = ScreenManager.start_link(name: nil, event_handler: eh)

    %{
      event_manager: em,
      compositor: comp,
      screen_manager: sm,
      theme_manager: tm,
      event_handler: eh
    }
  end

  defp stop_session_services(ctx) do
    for {_, pid} <- ctx, is_pid(pid), Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end
  end

  defp build_session_opts(app_module, :shared, mount_props) do
    shared_state = Session.SharedState.get_or_start(app_module)
    [mode: :shared, shared_state: shared_state, props: mount_props]
  end

  defp build_session_opts(_app_module, mode, mount_props) do
    [mode: mode, props: mount_props]
  end
end
