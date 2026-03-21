defmodule Drafter.Event.Manager do
  @moduledoc false

  use GenServer

  alias Drafter.Event

  defstruct [
    :app_pid,
    subscribers: %{},
    event_queue: :queue.new(),
    processing: false
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

  @spec queue_size() :: non_neg_integer()
  def queue_size() do
    GenServer.call(resolve(), :queue_size)
  end

  @spec drain_queue() :: :ok
  def drain_queue() do
    GenServer.call(resolve(), :drain_queue)
  end

  @impl GenServer
  def init(opts) do
    app_pid = Keyword.get(opts, :app_pid)

    state = %__MODULE__{
      app_pid: app_pid,
      subscribers: %{},
      event_queue: :queue.new(),
      processing: false
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, subscriber_pid, filter}, _from, state) do
    Process.monitor(subscriber_pid)

    subscribers = Map.put(state.subscribers, subscriber_pid, filter)
    new_state = %{state | subscribers: subscribers}

    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    subscribers = Map.delete(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: subscribers}

    {:reply, :ok, new_state}
  end

  def handle_call(:queue_size, _from, state) do
    size = :queue.len(state.event_queue)
    {:reply, size, state}
  end

  def handle_call(:drain_queue, _from, state) do
    {:reply, :ok, %{state | event_queue: :queue.new(), processing: false}}
  end

  @impl GenServer
  def handle_cast({:event, event}, state) do
    new_queue = :queue.in(event, state.event_queue)
    new_state = %{state | event_queue: new_queue}

    if not state.processing do
      send(self(), :process_events)
      {:noreply, %{new_state | processing: true}}
    else
      {:noreply, new_state}
    end
  end

  def handle_cast({:events, events}, state) do
    new_queue =
      Enum.reduce(events, state.event_queue, fn event, queue ->
        :queue.in(event, queue)
      end)

    new_state = %{state | event_queue: new_queue}

    if not state.processing do
      send(self(), :process_events)
      {:noreply, %{new_state | processing: true}}
    else
      {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:process_events, state) do
    new_state = process_event_queue(state)

    if :queue.is_empty(new_state.event_queue) do
      {:noreply, %{new_state | processing: false}}
    else
      send(self(), :process_events)
      {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = Map.delete(state.subscribers, pid)
    new_state = %{state | subscribers: subscribers}

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp resolve(), do: Process.get(:drafter_event_manager, __MODULE__)

  defp process_event_queue(state) do
    case :queue.out(state.event_queue) do
      {{:value, event}, new_queue} ->
        dispatch_to_subscribers(event, state)
        %{state | event_queue: new_queue}

      {:empty, queue} ->
        %{state | event_queue: queue}
    end
  end

  defp dispatch_to_subscribers(event, state) do
    Enum.each(state.subscribers, fn {subscriber_pid, filter} ->
      if should_send_event?(event, filter) do
        send_to_subscriber(subscriber_pid, event)
      end
    end)

    if state.app_pid do
      send_to_subscriber(state.app_pid, event)
    end
  end

  defp should_send_event?(_event, :all), do: true

  defp should_send_event?(event, filter) when is_function(filter, 1) do
    try do
      filter.(event)
    rescue
      _ -> false
    end
  end

  defp should_send_event?(_event, _filter), do: false

  defp send_to_subscriber(pid, event) do
    try do
      send(pid, {:tui_event, event})
    rescue
      _ -> :ok
    end
  end
end
