defmodule Drafter.WidgetServer do
  @moduledoc false

  use GenServer

  alias Drafter.WidgetStripCache

  defstruct [
    :id,
    :module,
    :state,
    :rect,
    last_event_render_at: 0
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_event(pid, event) do
    GenServer.cast(pid, {:event, event})
  end

  def send_event_sync(pid, event) do
    GenServer.call(pid, {:event_sync, event})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def get_render(pid) do
    GenServer.call(pid, :get_render)
  end

  def update_rect(pid, rect) do
    GenServer.call(pid, {:update_rect, rect})
  end

  def update_props(pid, props) do
    GenServer.cast(pid, {:update_props, props})
  end

  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  def call_capture_handler(pid, event) do
    GenServer.call(pid, {:capture_event, event})
  end

  def set_state(pid, new_widget_state) do
    GenServer.call(pid, {:set_state, new_widget_state})
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    props = Keyword.get(opts, :props, %{})
    rect = Keyword.get(opts, :rect, %{x: 0, y: 0, width: 10, height: 3})
    id = Keyword.get(opts, :id)

    WidgetStripCache.create()

    widget_state = module.mount(props)

    state = %__MODULE__{
      id: id,
      module: module,
      state: widget_state,
      rect: rect
    }

    strips = module.render(widget_state, rect)
    WidgetStripCache.put(id, rect, strips)

    {:ok, state}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    priority = event_priority(event)

    if should_render_event?(priority, state.last_event_render_at) do
      case state.module.handle_event(event, state.state) do
        {:ok, new_widget_state} ->
          now = System.monotonic_time(:millisecond)
          new_state = %{state | state: new_widget_state, last_event_render_at: now}
          render_and_push(new_state)
          {:noreply, new_state}

        {:ok, new_widget_state, actions} ->
          handle_actions(state.id, actions)
          now = System.monotonic_time(:millisecond)
          new_state = %{state | state: new_widget_state, last_event_render_at: now}
          render_and_push(new_state)
          {:noreply, new_state}

        {:noreply, _} ->
          {:noreply, state}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:update_props, props}, state) do
    new_widget_state =
      if function_exported?(state.module, :update, 2) do
        state.module.update(props, state.state)
      else
        state.state
      end

    if new_widget_state === state.state do
      {:noreply, state}
    else
      new_state = %{state | state: new_widget_state}
      strips = new_state.module.render(new_state.state, new_state.rect)
      WidgetStripCache.put(new_state.id, new_state.rect, strips)
      notify_render_needed(new_state.id)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:update_rect, rect}, _from, state) do
    new_widget_state =
      if function_exported?(state.module, :on_rect_change, 2) do
        state.module.on_rect_change(rect, state.state)
      else
        state.state
      end

    new_state = %{state | rect: rect, state: new_widget_state}
    render_and_push(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:get_render, _from, state) do
    result =
      case WidgetStripCache.get(state.id) do
        nil ->
          strips = state.module.render(state.state, state.rect)
          WidgetStripCache.put(state.id, state.rect, strips)
          {state.rect, strips}

        cached ->
          cached
      end

    {:reply, result, state}
  end

  def handle_call({:event_sync, event}, _from, state) do
    result = state.module.handle_event(event, state.state)

    case result do
      {:ok, new_widget_state} ->
        new_state = %{state | state: new_widget_state}
        strips = new_state.module.render(new_state.state, new_state.rect)
        WidgetStripCache.put(new_state.id, new_state.rect, strips)
        {:reply, {:ok, new_widget_state}, new_state}

      {:ok, new_widget_state, actions} ->
        new_state = %{state | state: new_widget_state}
        strips = new_state.module.render(new_state.state, new_state.rect)
        WidgetStripCache.put(new_state.id, new_state.rect, strips)
        {:reply, {:ok, new_widget_state, actions}, new_state}

      {:noreply, new_state} ->
        {:reply, {:noreply, new_state}, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call({:set_state, new_widget_state}, _from, state) do
    new_state = %{state | state: new_widget_state}
    strips = new_state.module.render(new_state.state, new_state.rect)
    WidgetStripCache.put(new_state.id, new_state.rect, strips)
    notify_render_needed(new_state.id)
    {:reply, :ok, new_state}
  end

  def handle_call({:capture_event, event}, _from, state) do
    if function_exported?(state.module, :handle_event_capture, 2) do
      result = state.module.handle_event_capture(event, state.state)

      case result do
        {:continue, updated_event, new_widget_state} ->
          {:reply, {:continue, updated_event, new_widget_state}, %{state | state: new_widget_state}}

        {:stop, updated_event, new_widget_state, actions} ->
          handle_actions(state.id, actions)
          {:reply, {:stop, updated_event, new_widget_state, actions}, %{state | state: new_widget_state}}

        {:prevent, updated_event, new_widget_state} ->
          {:reply, {:prevent, updated_event, new_widget_state}, %{state | state: new_widget_state}}

        other ->
          {:reply, other, state}
      end
    else
      {:reply, {:continue, event, state.state}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    result =
      if function_exported?(state.module, :handle_info, 2) do
        state.module.handle_info(msg, state.state)
      else
        state.module.handle_event(msg, state.state)
      end

    case result do
      {:ok, new_widget_state} ->
        new_state = %{state | state: new_widget_state}
        render_and_push(new_state)
        {:noreply, new_state}

      {:ok, new_widget_state, _actions} ->
        new_state = %{state | state: new_widget_state}
        render_and_push(new_state)
        {:noreply, new_state}

      {:noreply, _} ->
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp event_priority({:key, _}), do: :high
  defp event_priority({:key, _, _}), do: :high
  defp event_priority({:char, _}), do: :high
  defp event_priority({:mouse, _}), do: :high
  defp event_priority({:resize, _}), do: :critical
  defp event_priority({:focus}), do: :high
  defp event_priority({:blur}), do: :normal
  defp event_priority({:timer, _}), do: :low
  defp event_priority(_), do: :normal

  defp should_render_event?(priority, _last_at) when priority in [:critical, :high], do: true

  defp should_render_event?(priority, last_at) do
    interval = Drafter.AppRegistry.get_frame_interval() || 33
    multiplier = if priority == :low, do: 3, else: 1
    System.monotonic_time(:millisecond) - last_at >= interval * multiplier
  end

  defp render_and_push(server_state) do
    strips = server_state.module.render(server_state.state, server_state.rect)
    WidgetStripCache.put(server_state.id, server_state.rect, strips)
    notify_render_needed(server_state.id)
  end

  defp notify_render_needed(widget_id) do
    if Drafter.AppRegistry.whereis() do
      Drafter.AppRegistry.send_to_loop({:widget_render_needed, widget_id})
    end
  end

  defp handle_actions(widget_id, actions) do
    if Drafter.AppRegistry.whereis() do
      Enum.each(actions, fn action ->
        Drafter.AppRegistry.send_to_loop({:widget_action, widget_id, action})
      end)
    end
  end
end
