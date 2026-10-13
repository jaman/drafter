defmodule Drafter.Render.Writer do
  @moduledoc """
  The one process that writes a session's terminal, for `Drafter.Compositor`.

      {:ok, writer} = Drafter.Render.Writer.start_link(:tty)
      Drafter.Render.Writer.write(writer, frame_bytes)

  Every write is one call to the sink, in the order the calls were made, so no sequence
  is ever cut by another, and no call blocks the caller or is dropped. `behind?/1`
  tells whether anything handed over is still unwritten, for a caller that would rather
  merge its next frames into one than queue them.

  The sink is a function of iodata, or `{:tty, fallback}` to write `/dev/tty` — which the
  writer opens itself, since a raw file is usable only by the process that opened it —
  using the `fallback` function when `/dev/tty` cannot be opened.
  """

  use GenServer

  @doc "Start a writer whose `sink` is a function of iodata, or `{:tty, fallback}`."
  @spec start_link((iodata() -> term()) | {:tty, (iodata() -> term())}) :: GenServer.on_start()
  def start_link(sink), do: GenServer.start_link(__MODULE__, sink)

  @doc "Write `bytes` after everything already handed over. Asynchronous, never dropped."
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(writer, bytes) do
    :atomics.add(counters(writer), 1, 1)
    GenServer.cast(writer, {:write, bytes})
  end

  @doc "Whether anything handed over by `write/2` is still waiting to be written."
  @spec behind?(GenServer.server()) :: boolean()
  def behind?(writer), do: :atomics.get(counters(writer), 1) > 0

  @doc "Return once everything handed over so far has been written."
  @spec flush(GenServer.server()) :: :ok
  def flush(writer), do: GenServer.call(writer, :flush, :infinity)

  defp counters(writer) do
    case Process.get({__MODULE__, writer}) do
      nil ->
        counters = GenServer.call(writer, :counters)
        Process.put({__MODULE__, writer}, counters)
        counters

      counters ->
        counters
    end
  end

  @impl GenServer
  def init({:tty, fallback}) do
    case :file.open(~c"/dev/tty", [:write, :raw, :binary]) do
      {:ok, tty} -> init(fn bytes -> :file.write(tty, bytes) end)
      {:error, _reason} -> init(fallback)
    end
  end

  def init(sink) when is_function(sink, 1),
    do: {:ok, %{sink: sink, counters: :atomics.new(1, signed: false)}}

  @impl GenServer
  def handle_call(:counters, _from, state), do: {:reply, state.counters, state}
  def handle_call(:flush, _from, state), do: {:reply, :ok, state}

  @impl GenServer
  def handle_cast({:write, bytes}, state) do
    traced(state, "W", bytes)
    :atomics.sub(state.counters, 1, 1)
    {:noreply, state}
  end

  defp traced(state, kind, bytes) do
    if Drafter.Trace.enabled?() do
      started = System.monotonic_time(:microsecond)
      state.sink.(bytes)

      Drafter.Trace.log([
        kind,
        " ",
        Drafter.Trace.ts(),
        " bytes=",
        Integer.to_string(IO.iodata_length(bytes)),
        " write_us=",
        Integer.to_string(System.monotonic_time(:microsecond) - started),
        "\n"
      ])
    else
      state.sink.(bytes)
    end
  end
end
