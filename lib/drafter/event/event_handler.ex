defmodule Drafter.EventHandler do
  @moduledoc """
  Dispatches events to registered callback functions, in registration levels.

  Handlers are kept as an ordered list of levels. Dispatch walks the levels from
  first to last, calls every handler in a level whose pattern matches, and stops as
  soon as a level contains a matching non-passthrough handler that returned
  `:handled`. Registration decides the order: `:top` puts a handler in a new first
  level, `:bottom` in a new last one, and `{:after, pid}` in a new level directly
  after the level containing that owner's handler.

      Drafter.EventHandler.register_handler({:type, :key}, &handle/1, self())
      Drafter.EventHandler.dispatch_event_sync({:key, :escape})
      #=> :handled

  Event patterns:

    * `:any` — every event
    * `{:type, type}` — any two-element event tuple tagged `type`
    * `{type, sub_type}` — a two-element event tuple tagged `type` whose payload is
      a map with `type: sub_type`, which is how a mouse sub-kind is selected

  A handler function takes the event and returns `:handled` to consume it or
  anything else to let dispatch continue. Exceptions raised inside it are caught and
  turned into `{:error, exception}`, which does not count as handled.

  Handlers are removed when their owner process exits; owners are monitored at
  registration. Dead owners are also swept on every dispatch.

  The functions here resolve the handler process through `Drafter.Session.Context`
  under the `:event_handler` key, except `register_handler/4` which accepts an
  explicit `:target`.
  """

  use GenServer

  alias Drafter.Session.Context

  defstruct [:handlers, :monitors]

  @doc """
  Start a handler process.

  Options:

    * `:name` — registered name, default `Drafter.EventHandler`. Pass `nil` to start
      it unregistered, which is what a session other than the local terminal does.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Register `handler_fn` for events matching `event_pattern`, owned by `owner_pid`.

  `event_pattern` is `:any`, `{:type, type}` or `{type, sub_type}`. `handler_fn`
  takes the event and returns `:handled` to consume it.

  Options:

    * `:passthrough` — when `true` the handler never consumes the event, whatever it
      returns. Default `false`.
    * `:level` — `:top` (default) inserts a new first level, `:bottom` a new last
      one, `{:after, pid}` a new level right after the one holding `pid`'s handler.
    * `:target` — the handler process to register with; defaults to the session's.

  Returns `{:ok, handler_process}`, or `{:error, :dead_process}` if `owner_pid` is
  not alive. The registration is dropped when `owner_pid` exits.
  """
  @spec register_handler(term(), function(), pid(), keyword()) :: {:ok, pid()} | {:error, term()}
  def register_handler(event_pattern, handler_fn, owner_pid, opts \\ []) do
    passthrough = Keyword.get(opts, :passthrough, false)
    level = Keyword.get(opts, :level, :top)

    target =
      case Keyword.fetch(opts, :target) do
        {:ok, pid} -> pid
        :error -> resolve()
      end

    GenServer.call(target, {:register, event_pattern, handler_fn, owner_pid, passthrough, level})
  end

  @doc """
  Remove handlers owned by `owner_pid`.

  With `event_pattern` `nil` (the default) every handler that owner registered is
  removed and the monitor on it is released. With a pattern, only handlers
  registered under exactly that pattern are removed. Levels left empty are dropped.
  """
  @spec unregister_handler(pid(), term()) :: :ok
  def unregister_handler(owner_pid, event_pattern \\ nil) do
    GenServer.call(resolve(), {:unregister, owner_pid, event_pattern})
  end

  @doc """
  Dispatch `event` without waiting for the handlers to run.

  Returns `:ok` immediately and discards whether anything handled the event; use
  `dispatch_event_sync/1` when that matters.
  """
  @spec dispatch_event(term()) :: :ok
  def dispatch_event(event) do
    GenServer.cast(resolve(), {:dispatch, event})
  end

  @doc """
  Dispatch `event` and return once every handler that ran has returned.

  `:handled` means a matching non-passthrough handler consumed the event and later
  levels were skipped. `:passthrough` means it was not consumed, whether or not
  handlers ran.
  """
  @spec dispatch_event_sync(term()) :: :handled | :passthrough
  def dispatch_event_sync(event) do
    GenServer.call(resolve(), {:dispatch, event})
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      handlers: [],
      monitors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:register, event_pattern, handler_fn, owner_pid, passthrough, :top},
        _from,
        state
      ) do
    if Process.alive?(owner_pid) do
      ref = Process.monitor(owner_pid)

      handler = %{
        event_pattern: event_pattern,
        handler_fn: handler_fn,
        owner_pid: owner_pid,
        passthrough: passthrough
      }

      new_handlers = [[handler] | state.handlers]
      new_monitors = Map.put(state.monitors, owner_pid, ref)

      {:reply, {:ok, self()}, %{state | handlers: new_handlers, monitors: new_monitors}}
    else
      {:reply, {:error, :dead_process}, state}
    end
  end

  def handle_call(
        {:register, event_pattern, handler_fn, owner_pid, passthrough, :bottom},
        _from,
        state
      ) do
    if Process.alive?(owner_pid) do
      ref = Map.get(state.monitors, owner_pid) || Process.monitor(owner_pid)

      handler = %{
        event_pattern: event_pattern,
        handler_fn: handler_fn,
        owner_pid: owner_pid,
        passthrough: passthrough
      }

      new_handlers = state.handlers ++ [[handler]]
      new_monitors = Map.put(state.monitors, owner_pid, ref)

      {:reply, {:ok, self()}, %{state | handlers: new_handlers, monitors: new_monitors}}
    else
      {:reply, {:error, :dead_process}, state}
    end
  end

  def handle_call(
        {:register, event_pattern, handler_fn, owner_pid, passthrough, {:after, target_pid}},
        _from,
        state
      ) do
    if Process.alive?(owner_pid) do
      ref = Map.get(state.monitors, owner_pid) || Process.monitor(owner_pid)

      handler = %{
        event_pattern: event_pattern,
        handler_fn: handler_fn,
        owner_pid: owner_pid,
        passthrough: passthrough
      }

      new_handlers = insert_after(state.handlers, target_pid, [handler])
      new_monitors = Map.put(state.monitors, owner_pid, ref)

      {:reply, {:ok, self()}, %{state | handlers: new_handlers, monitors: new_monitors}}
    else
      {:reply, {:error, :dead_process}, state}
    end
  end

  def handle_call({:unregister, owner_pid, nil}, _from, state) do
    new_handlers =
      Enum.map(state.handlers, fn level ->
        Enum.reject(level, &(&1.owner_pid == owner_pid))
      end)
      |> Enum.reject(&(&1 == []))

    case Map.get(state.monitors, owner_pid) do
      nil ->
        {:reply, :ok, %{state | handlers: new_handlers}}

      ref ->
        Process.demonitor(ref, [:flush])
        new_monitors = Map.delete(state.monitors, owner_pid)
        {:reply, :ok, %{state | handlers: new_handlers, monitors: new_monitors}}
    end
  end

  def handle_call({:unregister, owner_pid, event_pattern}, _from, state) do
    new_handlers =
      Enum.map(state.handlers, fn level ->
        Enum.reject(level, fn h ->
          h.owner_pid == owner_pid and match_event_pattern?(event_pattern, h.event_pattern)
        end)
      end)
      |> Enum.reject(&(&1 == []))

    if Enum.any?(state.handlers, fn level ->
         Enum.any?(level, &(&1.owner_pid == owner_pid))
       end) do
      {:reply, :ok, %{state | handlers: new_handlers}}
    else
      case Map.get(state.monitors, owner_pid) do
        nil ->
          {:reply, :ok, %{state | handlers: new_handlers}}

        ref ->
          Process.demonitor(ref, [:flush])
          new_monitors = Map.delete(state.monitors, owner_pid)
          {:reply, :ok, %{state | handlers: new_handlers, monitors: new_monitors}}
      end
    end
  end

  def handle_call({:dispatch, event}, _from, state) do
    cleaned_handlers = cleanup_dead_handlers(state.handlers)
    new_state = %{state | handlers: cleaned_handlers}

    result = dispatch_to_handlers(new_state.handlers, event)
    {:reply, result, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:dispatch, event}, state) do
    cleaned_handlers = cleanup_dead_handlers(state.handlers)
    new_state = %{state | handlers: cleaned_handlers}

    dispatch_to_handlers(new_state.handlers, event)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_handlers =
      Enum.map(state.handlers, fn level ->
        Enum.reject(level, &(&1.owner_pid == pid))
      end)
      |> Enum.reject(&(&1 == []))

    new_monitors = Map.delete(state.monitors, pid)

    {:noreply, %{state | handlers: new_handlers, monitors: new_monitors}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp resolve, do: Context.fetch!(:event_handler)

  defp insert_after(handlers, target_pid, new_level) do
    Enum.flat_map(handlers, fn level ->
      if Enum.any?(level, &(&1.owner_pid == target_pid)) do
        [level, new_level]
      else
        [level]
      end
    end)
  end

  defp cleanup_dead_handlers(handlers) do
    Enum.map(handlers, fn level ->
      Enum.filter(level, fn h ->
        Process.alive?(h.owner_pid)
      end)
    end)
    |> Enum.reject(&(&1 == []))
  end

  defp dispatch_to_handlers(handlers, event) do
    Enum.reduce_while(handlers, :passthrough, fn level, _acc ->
      matched_handlers =
        Enum.filter(level, fn handler ->
          matches_event?(handler.event_pattern, event)
        end)

      level_results =
        Enum.map(matched_handlers, fn handler ->
          try do
            handler.handler_fn.(event)
          rescue
            e -> {:error, e}
          end
        end)

      has_passthrough = Enum.any?(matched_handlers, & &1.passthrough)
      has_non_passthrough = Enum.any?(matched_handlers, fn h -> not h.passthrough end)

      cond do
        has_non_passthrough and :handled in level_results ->
          {:halt, :handled}

        has_non_passthrough and :handled not in level_results and
            :passthrough not in level_results ->
          {:cont, :passthrough}

        has_passthrough ->
          {:cont, :passthrough}

        true ->
          {:cont, :passthrough}
      end
    end)
  end

  defp matches_event?(pattern, event) do
    case pattern do
      :any -> true
      {:type, type} -> match?({^type, _}, event)
      {type, sub_type} -> match?({^type, %{type: ^sub_type}}, event)
      _ -> false
    end
  end

  defp match_event_pattern?(pattern1, pattern2) do
    pattern1 == pattern2
  end
end
