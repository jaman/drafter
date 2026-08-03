defmodule Drafter.Trace do
  @moduledoc false

  use GenServer

  @started_at {__MODULE__, :started_at}
  @enabled {__MODULE__, :enabled}
  @exit_stamped {__MODULE__, :exit_stamped}

  @doc """
  Whether `DRAFTER_TRACE` is set to a non-empty value.

  The environment variable is read on the first call and the answer cached for
  the lifetime of the VM; changing it afterwards has no effect.
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

  @doc """
  Start the shared trace log, unless `DRAFTER_TRACE` is unset or it is already running.

  `DRAFTER_TRACE=1` (or `true`) writes `drafter_trace.log` in the current
  directory; any other value is taken as the path to write. Always returns `:ok`.
  """
  @spec ensure_started() :: :ok
  def ensure_started do
    if enabled?() and Process.whereis(__MODULE__) == nil do
      _ = start_link([])
    end

    :ok
  end

  @doc """
  Append `iodata` to the trace log without waiting for the write.

  A no-op when the trace log is not running.
  """
  @spec log(iodata()) :: :ok
  def log(iodata) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:log, iodata})
    end
  end

  @doc """
  Write `label` and the current epoch time to stderr, synchronously.

  The line has the form `DRAFTER <label> epoch=<seconds>.<microseconds>`. Writing
  to stderr rather than the trace log means it survives the trace GenServer being
  gone, so it is usable at the point the runtime is being halted.

  Does nothing unless `DRAFTER_TRACE` is set. Always returns `:ok`.
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
  Register `stamp("vm_exit")` with `System.at_exit/1`, at most once per VM.

  Covers the graceful shutdown path only: `System.halt/1` skips `System.at_exit/1`,
  so a halting caller must call `stamp/1` itself.

  Does nothing unless `DRAFTER_TRACE` is set. Always returns `:ok`.
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
  A timestamp of the form `HH:MM:SS.uuuuuu epoch=<seconds>.<microseconds> +Nms`.

  The clock time is local. `+Nms` is the number of milliseconds elapsed since the
  first call to this function in the current VM, which reports `+0ms`.
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
