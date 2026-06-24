defmodule Drafter.Trace do
  @moduledoc false

  use GenServer

  @spec enabled?() :: boolean()
  def enabled?, do: System.get_env("DRAFTER_TRACE") not in [nil, ""]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Start the shared trace log if DRAFTER_TRACE is set and it isn't running yet."
  @spec ensure_started() :: :ok
  def ensure_started do
    if enabled?() and Process.whereis(__MODULE__) == nil do
      _ = start_link([])
    end

    :ok
  end

  @doc "Append a line (fire-and-forget). For high-frequency events."
  @spec log(iodata()) :: :ok
  def log(iodata) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:log, iodata})
    end
  end

  @doc "Append a line and block until written. For rare events that precede a possible exit (e.g. quit)."
  @spec log_sync(iodata()) :: :ok
  def log_sync(iodata) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, {:log, iodata})
    end
  end

  @spec ts() :: binary()
  def ts, do: Integer.to_string(System.monotonic_time(:microsecond))

  @impl GenServer
  def init(_opts) do
    path = Path.join(File.cwd!(), "drafter_trace.log")
    {:ok, dev} = :file.open(path, [:write, :raw])
    {:ok, dev}
  end

  @impl GenServer
  def handle_cast({:log, iodata}, dev) do
    :file.write(dev, iodata)
    {:noreply, dev}
  end

  @impl GenServer
  def handle_call({:log, iodata}, _from, dev) do
    :file.write(dev, iodata)
    {:reply, :ok, dev}
  end
end
