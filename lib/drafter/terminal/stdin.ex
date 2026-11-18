defmodule Drafter.Terminal.Stdin do
  @moduledoc """
  The one reader of standard input on this node.

  Reading starts at the first `subscribe/2` and continues for the life of the node.
  Each chunk read is sent to the subscriber as `{:stdin, binary}`, and `:stdin_closed`
  is sent when standard input ends. One process is subscribed at a time, and a new
  subscription replaces the previous one. A subscriber that exits is unsubscribed.

  Bytes read while no process is subscribed are held. The next subscriber receives
  them as one `{:stdin, binary}` when it subscribes with `:keep`, and they are dropped
  when it subscribes with `:discard`.

      Drafter.Terminal.Stdin.subscribe()

      receive do
        {:stdin, bytes} -> bytes
      end

  Once reading has started, every byte of standard input passes through this process.
  A process that reads standard input another way after that point competes with it.
  """

  use GenServer

  defstruct reader: nil, subscriber: nil, monitor: nil, held: [], closed: false

  @type held :: :keep | :discard

  @doc "Start the reader's owner and register it under this module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Send standard input to `subscriber` from now on, replacing any other subscriber.

  `held` says what happens to bytes read while nobody was subscribed: `:keep` (the
  default) delivers them first, `:discard` drops them. A subscriber that joins after
  standard input ended is sent `:stdin_closed` at once.
  """
  @spec subscribe(pid(), held()) :: :ok
  def subscribe(subscriber \\ self(), held \\ :keep) when held in [:keep, :discard],
    do: GenServer.call(__MODULE__, {:subscribe, subscriber, held})

  @doc """
  Stop sending standard input to `subscriber`.

  Does nothing when `subscriber` is not the current subscriber. Reading continues and
  what is read is held for the next subscriber.
  """
  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(subscriber \\ self()),
    do: GenServer.call(__MODULE__, {:unsubscribe, subscriber})

  @impl GenServer
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl GenServer
  def handle_call({:subscribe, subscriber, held}, _from, state) do
    state =
      state
      |> drop_subscriber()
      |> ensure_reader()
      |> deliver_held(subscriber, held)

    if state.closed, do: send(subscriber, :stdin_closed)

    {:reply, :ok, %{state | subscriber: subscriber, monitor: Process.monitor(subscriber)}}
  end

  def handle_call({:unsubscribe, subscriber}, _from, %__MODULE__{subscriber: subscriber} = state),
    do: {:reply, :ok, drop_subscriber(state)}

  def handle_call({:unsubscribe, _other}, _from, state), do: {:reply, :ok, state}

  @impl GenServer
  def handle_info({:read, data}, %__MODULE__{subscriber: nil} = state),
    do: {:noreply, %{state | held: [data | state.held]}}

  def handle_info({:read, data}, state) do
    send(state.subscriber, {:stdin, data})
    {:noreply, state}
  end

  def handle_info(:closed, state) do
    if state.subscriber, do: send(state.subscriber, :stdin_closed)
    {:noreply, %{state | closed: true, reader: nil}}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %__MODULE__{monitor: monitor} = state
      ),
      do: {:noreply, %{state | subscriber: nil, monitor: nil}}

  def handle_info(_message, state), do: {:noreply, state}

  defp drop_subscriber(%__MODULE__{monitor: nil} = state), do: state

  defp drop_subscriber(state) do
    Process.demonitor(state.monitor, [:flush])
    %{state | subscriber: nil, monitor: nil}
  end

  defp ensure_reader(%__MODULE__{reader: nil, closed: false} = state) do
    :io.setopts(:stdio, [:binary, {:encoding, :unicode}])
    owner = self()
    %{state | reader: spawn_link(fn -> read(owner) end)}
  end

  defp ensure_reader(state), do: state

  defp deliver_held(%__MODULE__{held: []} = state, _subscriber, _held), do: state

  defp deliver_held(state, _subscriber, :discard), do: %{state | held: []}

  defp deliver_held(state, subscriber, :keep) do
    send(subscriber, {:stdin, state.held |> Enum.reverse() |> IO.iodata_to_binary()})
    %{state | held: []}
  end

  defp read(owner) do
    case IO.read(:stdio, 1) do
      data when is_binary(data) ->
        send(owner, {:read, data})
        read(owner)

      _closed ->
        send(owner, :closed)
    end
  end
end
