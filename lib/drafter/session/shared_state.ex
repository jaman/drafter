defmodule Drafter.Session.SharedState do
  @moduledoc false

  use GenServer

  @spec get_or_start(module(), keyword()) :: pid()
  def get_or_start(app_module, opts \\ []) do
    case Registry.lookup(Drafter.Session.Registry, {:shared_state, app_module}) do
      [{pid, _}] ->
        pid

      [] ->
        case GenServer.start_link(
               __MODULE__,
               [app_module: app_module] ++ opts,
               name: {:via, Registry, {Drafter.Session.Registry, {:shared_state, app_module}}}
             ) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  @spec get_state(pid()) :: map()
  def get_state(server), do: GenServer.call(server, :get_state)

  @spec update_state(pid(), map()) :: :ok
  def update_state(server, new_state), do: GenServer.call(server, {:update_state, new_state})

  @spec subscribe(pid()) :: :ok
  def subscribe(server), do: GenServer.call(server, {:subscribe, self()})

  @impl GenServer
  def init(opts) do
    app_module = Keyword.fetch!(opts, :app_module)
    mount_props = Keyword.get(opts, :mount_props, %{})
    app_state = app_module.mount(mount_props)
    {:ok, %{app_state: app_state, subscribers: MapSet.new()}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.app_state, state}
  end

  def handle_call({:update_state, new_state}, _from, state) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:shared_state_updated, new_state})
    end)

    {:reply, :ok, %{state | app_state: new_state}}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
