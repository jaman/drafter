defmodule Drafter.Event.Manager do
  @moduledoc """
  Fans events out from the terminal driver to the processes that want them.

  One manager exists per session. Producers cast events to it; it delivers each one
  to every subscriber whose filter accepts it, as the message
  `{:tui_event, event}`. The event shapes are the ones listed in `Drafter.Event`.

      Drafter.Event.Manager.subscribe(self(), &Drafter.Event.key_event?/1)
      receive do
        {:tui_event, {:key, key}} -> key
      end

  A subscriber is monitored and dropped when it exits, so unsubscribing on shutdown
  is not required. Subscribing the same pid twice replaces its filter.

  The `:app_pid` given at start receives every deliverable event regardless of the
  subscriber list.

  `{:bracketed_paste, _}` is withheld unless `Drafter.Clipboard.paste_enabled?/0`
  returns true; every other event is always deliverable.

  Functions without an explicit manager argument resolve it through
  `Drafter.Session.Context` under the `:event_manager` key, so they address the
  caller's own session.
  """

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

  @doc """
  Start a manager.

  Options:

    * `:name` — registered name, default `Drafter.Event.Manager`. Pass `nil` to
      start it unregistered, which is what a session other than the local terminal
      does.
    * `:app_pid` — a process that receives every deliverable event without
      subscribing.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Subscribe `subscriber_pid` to `manager`, for a manager that is not registered
  under this module's name.

  `filter` is `:all` (the default) or a one-argument function returning `true` for
  the events to deliver. A filter that raises is treated as no match. The
  subscriber is monitored; a second subscription for the same pid replaces its
  filter.
  """
  @spec subscribe_to(pid() | atom(), pid(), event_filter()) :: :ok
  def subscribe_to(manager, subscriber_pid, filter \\ :all) do
    GenServer.call(manager, {:subscribe, subscriber_pid, filter})
  end

  @doc """
  Subscribe `subscriber_pid` to this session's manager.

  Defaults to the calling process and to the `:all` filter. See `subscribe_to/3`
  for the filter contract.
  """
  @spec subscribe(pid(), event_filter()) :: :ok
  def subscribe(subscriber_pid \\ self(), filter \\ :all) do
    GenServer.call(resolve(), {:subscribe, subscriber_pid, filter})
  end

  @doc """
  Stop delivering events to `subscriber_pid`, defaulting to the calling process.

  Unnecessary when the subscriber is exiting; the monitor removes it.
  """
  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(subscriber_pid \\ self()) do
    GenServer.call(resolve(), {:unsubscribe, subscriber_pid})
  end

  @doc """
  Deliver `event` to this session's subscribers.

  Asynchronous; use `sync/0` to wait for delivery.
  """
  @spec send_event(Event.t()) :: :ok
  def send_event(event) do
    GenServer.cast(resolve(), {:event, event})
  end

  @doc """
  Deliver each of `events` in order to this session's subscribers.

  Asynchronous; use `sync/0` to wait for delivery.
  """
  @spec send_events([Event.t()]) :: :ok
  def send_events(events) when is_list(events) do
    GenServer.cast(resolve(), {:events, events})
  end

  @doc "Always returns `:ok` immediately. Retained for callers in the runtime loop."
  @spec drain_queue() :: :ok
  def drain_queue, do: :ok

  @doc """
  Returns once every event cast before this call has been dispatched.

  A synchronous round trip through the manager, so it orders after earlier casts
  from the same caller. Call it before observing a subscriber's state to be sure
  the events sent to it have been delivered.
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
