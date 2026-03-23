defmodule Drafter.Test.HeadlessDriver do
  @moduledoc false

  use GenServer

  defstruct [
    :event_manager,
    :test_pid,
    buffer: [],
    size: {80, 24},
    render_count: 0,
    mouse_enabled: false,
    alt_screen: false,
    raw_mode: false
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def setup do
    GenServer.call(__MODULE__, :setup)
  end

  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end

  def write(data) do
    GenServer.cast(__MODULE__, {:write, data})
  end

  def get_size do
    GenServer.call(__MODULE__, :get_size)
  end

  def enable_mouse do
    GenServer.cast(__MODULE__, :enable_mouse)
  end

  def disable_mouse do
    GenServer.cast(__MODULE__, :disable_mouse)
  end

  def inject_event(event) do
    GenServer.cast(__MODULE__, {:inject_event, event})
  end

  def get_buffer do
    GenServer.call(__MODULE__, :get_buffer)
  end

  def get_render_count do
    GenServer.call(__MODULE__, :get_render_count)
  end

  def set_size(width, height) do
    GenServer.cast(__MODULE__, {:set_size, width, height})
  end

  def clear_buffer do
    GenServer.cast(__MODULE__, :clear_buffer)
  end

  @impl GenServer
  def init(opts) do
    event_manager = Keyword.get(opts, :event_manager, Drafter.Event.Manager)
    test_pid = Keyword.get(opts, :test_pid)
    size = Keyword.get(opts, :size, {80, 24})

    state = %__MODULE__{
      event_manager: event_manager,
      test_pid: test_pid,
      buffer: [],
      size: size,
      render_count: 0,
      mouse_enabled: false,
      alt_screen: false,
      raw_mode: false
    }

    Process.put(:event_manager, event_manager)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:setup, _from, state) do
    new_state = %{state | raw_mode: true, alt_screen: true, mouse_enabled: true}
    {:reply, :ok, new_state}
  end

  def handle_call(:cleanup, _from, state) do
    new_state = %{state | raw_mode: false, alt_screen: false, mouse_enabled: false}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:get_buffer, _from, state) do
    {:reply, Enum.reverse(state.buffer), state}
  end

  def handle_call(:get_render_count, _from, state) do
    {:reply, state.render_count, state}
  end

  @impl GenServer
  def handle_cast({:write, data}, state) do
    new_buffer = [data | state.buffer]
    new_count = state.render_count + 1

    if state.test_pid do
      send(state.test_pid, {:render, new_count})
    end

    {:noreply, %{state | buffer: new_buffer, render_count: new_count}}
  end

  def handle_cast(:enable_mouse, state) do
    {:noreply, %{state | mouse_enabled: true}}
  end

  def handle_cast(:disable_mouse, state) do
    {:noreply, %{state | mouse_enabled: false}}
  end

  def handle_cast({:inject_event, event}, state) do
    event_manager = state.event_manager
    GenServer.cast(event_manager, {:event, event})
    {:noreply, state}
  end

  def handle_cast({:set_size, width, height}, state) do
    new_size = {width, height}
    event_manager = state.event_manager
    GenServer.cast(event_manager, {:event, {:resize, new_size}})
    {:noreply, %{state | size: new_size}}
  end

  def handle_cast(:clear_buffer, state) do
    {:noreply, %{state | buffer: [], render_count: 0}}
  end
end
