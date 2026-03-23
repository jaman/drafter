defmodule Drafter.EventHandler do
  @moduledoc false

  use GenServer

  defstruct [:handlers, :monitors]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

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

  @spec unregister_handler(pid(), term()) :: :ok
  def unregister_handler(owner_pid, event_pattern \\ nil) do
    GenServer.call(resolve(), {:unregister, owner_pid, event_pattern})
  end

  @spec dispatch_event(term()) :: :ok
  def dispatch_event(event) do
    GenServer.cast(resolve(), {:dispatch, event})
  end

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
  def handle_call({:register, event_pattern, handler_fn, owner_pid, passthrough, :top}, _from, state) do
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

  def handle_call({:register, event_pattern, handler_fn, owner_pid, passthrough, :bottom}, _from, state) do
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

  def handle_call({:register, event_pattern, handler_fn, owner_pid, passthrough, {:after, target_pid}}, _from, state) do
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

  defp resolve do
    Process.get(:drafter_event_handler) ||
      raise "No EventHandler in process dictionary. Ensure a Drafter session is running."
  end

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
      matched_handlers = Enum.filter(level, fn handler ->
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

        has_non_passthrough and :handled not in level_results and :passthrough not in level_results ->
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
