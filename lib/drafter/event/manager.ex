defmodule Drafter.Event.Manager do
  @moduledoc false

  use GenServer

  alias Drafter.Event
  alias Drafter.Session.Context

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

  @doc """
  Returns once every event cast before this call has been dispatched.

  A synchronous round trip, so it orders against earlier casts from the same
  caller. Used to hand an event off to subscribers before observing their state.
  """
  @spec sync() :: :ok
  def sync, do: GenServer.call(resolve(), :sync)

  @doc "As `sync/0`, for a manager that is not globally registered."
  @spec sync(pid() | atom()) :: :ok
  def sync(manager), do: GenServer.call(manager, :sync)

  @impl GenServer
  def init(opts) do
    {:ok, %__MODULE__{app_pid: Keyword.get(opts, :app_pid)}}
  end

  @impl GenServer
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call({:subscribe, subscriber_pid, filter}, _from, state) do
    Process.monitor(subscriber_pid)
    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, subscriber_pid, filter)}}
  end

  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: Map.delete(state.subscribers, subscriber_pid)}}
  end

  @impl GenServer
  def handle_cast({:event, event}, state) do
    if deliverable?(event), do: dispatch_to_subscribers(event, state)
    {:noreply, state}
  end

  def handle_cast({:events, events}, state) do
    events
    |> Enum.filter(&deliverable?/1)
    |> Enum.each(&dispatch_to_subscribers(&1, state))

    {:noreply, state}
  end

  defp deliverable?({:bracketed_paste, _text}), do: Drafter.Clipboard.paste_enabled?()
  defp deliverable?(_event), do: true

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp resolve, do: Context.fetch!(:event_manager)

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
