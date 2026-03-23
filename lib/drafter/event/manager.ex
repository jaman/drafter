defmodule Drafter.Event.Manager do
  @moduledoc false

  use GenServer

  alias Drafter.Event

  defstruct [
    :app_pid,
    subscribers: %{}
  ]

  @type subscriber :: pid()
  @type event_filter :: (Event.t() -> boolean()) | :all
  @type subscription :: {subscriber(), event_filter()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec subscribe_to(pid() | atom(), pid(), event_filter()) :: :ok
  def subscribe_to(manager, subscriber_pid, filter \\ :all) do
    GenServer.call(manager, {:subscribe, subscriber_pid, filter})
  end

  @spec subscribe(pid(), event_filter()) :: :ok
  def subscribe(subscriber_pid \\ self(), filter \\ :all) do
    GenServer.call(resolve(), {:subscribe, subscriber_pid, filter})
  end

  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(subscriber_pid \\ self()) do
    GenServer.call(resolve(), {:unsubscribe, subscriber_pid})
  end

  @spec send_event(Event.t()) :: :ok
  def send_event(event) do
    GenServer.cast(resolve(), {:event, event})
  end

  @spec send_events([Event.t()]) :: :ok
  def send_events(events) when is_list(events) do
    GenServer.cast(resolve(), {:events, events})
  end

  @spec drain_queue() :: :ok
  def drain_queue, do: :ok

  @impl GenServer
  def init(opts) do
    {:ok, %__MODULE__{app_pid: Keyword.get(opts, :app_pid)}}
  end

  @impl GenServer
  def handle_call({:subscribe, subscriber_pid, filter}, _from, state) do
    Process.monitor(subscriber_pid)
    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, subscriber_pid, filter)}}
  end

  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: Map.delete(state.subscribers, subscriber_pid)}}
  end

  @impl GenServer
  def handle_cast({:event, event}, state) do
    dispatch_to_subscribers(event, state)
    {:noreply, state}
  end

  def handle_cast({:events, events}, state) do
    Enum.each(events, &dispatch_to_subscribers(&1, state))
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp resolve do
    Process.get(:drafter_event_manager) ||
      raise "No Event.Manager in process dictionary. Ensure a Drafter session is running."
  end

  defp dispatch_to_subscribers(event, state) do
    Enum.each(state.subscribers, fn {pid, filter} ->
      if matches_filter?(event, filter), do: send_event_to(pid, event)
    end)

    if state.app_pid, do: send_event_to(state.app_pid, event)
  end

  defp matches_filter?(_event, :all), do: true

  defp matches_filter?(event, filter) when is_function(filter, 1) do
    filter.(event)
  rescue
    _ -> false
  end

  defp matches_filter?(_event, _filter), do: false

  defp send_event_to(pid, event) do
    send(pid, {:tui_event, event})
  rescue
    _ -> :ok
  end
end
