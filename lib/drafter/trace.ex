defmodule Drafter.Trace do
  @moduledoc false

  use GenServer

  @started_at {__MODULE__, :started_at}
  @enabled {__MODULE__, :enabled}
  @exit_stamped {__MODULE__, :exit_stamped}

  @doc """
  Whether `DRAFTER_TRACE` is set.

  Read once and cached, because callers on the input and render paths check this
  before building a trace line.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case :persistent_term.get(@enabled, nil) do
      nil ->
        value = System.get_env("DRAFTER_TRACE") not in [nil, ""]
        :persistent_term.put(@enabled, value)
        value

      value ->
        value
    end
  end

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

  @doc """
  Writes `label` and the current epoch to stderr, synchronously.

  For the last moment before the runtime is halted, where the trace log is no
  longer a useful place to look: stderr interleaves with the shell, so the value
  can be compared against a timestamp taken by the shell after the process exits.

  Silent unless `DRAFTER_TRACE` is set.
  """
  @spec stamp(String.t()) :: :ok
  def stamp(label) do
    if enabled?() do
      micro = System.system_time(:microsecond)

      IO.write(:standard_error, [
        "DRAFTER ",
        label,
        " epoch=",
        Integer.to_string(div(micro, 1_000_000)),
        ?.,
        String.pad_leading(Integer.to_string(rem(micro, 1_000_000)), 6, "0"),
        "\n"
      ])
    end

    :ok
  end

  @doc """
  Register a `stamp/1` to run as the last thing the VM does, once.

  `System.halt/1` skips `System.at_exit/1`, so this covers the graceful shutdown
  path; `stamp/1` is called directly on the halting path.

  Silent unless `DRAFTER_TRACE` is set.
  """
  @spec stamp_on_exit() :: :ok
  def stamp_on_exit do
    if enabled?() and not :persistent_term.get(@exit_stamped, false) do
      :persistent_term.put(@exit_stamped, true)
      System.at_exit(fn _status -> stamp("vm_exit") end)
    end

    :ok
  end

  @doc "Append a line and block until written. For rare events that precede a possible exit (e.g. quit)."
  @spec log_sync(iodata()) :: :ok
  def log_sync(iodata) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, {:log, iodata})
    end
  end

  @doc """
  Local wall-clock time as `HH:MM:SS.mmmmmm`, for reading against a stopwatch.

  Also carries `+Nms` — milliseconds since the trace started — so gaps can be read
  without subtracting timestamps by hand.
  """
  @spec ts() :: binary()
  def ts do
    micro = System.system_time(:microsecond)

    {{_year, _month, _day}, {hour, minute, second}} =
      :calendar.system_time_to_local_time(micro, :microsecond)

    IO.iodata_to_binary([
      pad(hour),
      ?:,
      pad(minute),
      ?:,
      pad(second),
      ?.,
      String.pad_leading(Integer.to_string(rem(micro, 1_000_000)), 6, "0"),
      " epoch=",
      Integer.to_string(div(micro, 1_000_000)),
      ?.,
      String.pad_leading(Integer.to_string(rem(micro, 1_000_000)), 6, "0"),
      " +",
      Integer.to_string(elapsed_ms()),
      "ms"
    ])
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp elapsed_ms do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@started_at, nil) do
      nil ->
        :persistent_term.put(@started_at, now)
        0

      started ->
        now - started
    end
  end

  @impl GenServer
  def init(_opts) do
    {:ok, dev} = :file.open(path(), [:write, :raw])
    {:ok, dev}
  end

  # `DRAFTER_TRACE=1` writes ./drafter_trace.log; any other value names the file, so runs being
  # compared against each other do not overwrite one another.
  defp path do
    case System.get_env("DRAFTER_TRACE") do
      value when value in [nil, "", "1", "true"] -> Path.join(File.cwd!(), "drafter_trace.log")
      name -> Path.expand(name)
    end
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
