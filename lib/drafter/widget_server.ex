defmodule Drafter.WidgetServer do
  @moduledoc false

  use GenServer

  alias Drafter.Widget.DataChannel
  alias Drafter.Widget.Trait.Pipeline
  alias Drafter.WidgetStripCache

  @default_image_throttle_ms 90

  defstruct [
    :id,
    :module,
    :state,
    :rect,
    :data_channel,
    auto_buffer: false,
    last_event_render_at: 0,
    image_task: nil,
    image_hash: nil,
    last_image_ms: nil,
    image_throttle_ms: @default_image_throttle_ms
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

  def push_data(pid, data) do
    GenServer.cast(pid, {:push_data, data})
  end

  def push_data_many(pid, items) do
    GenServer.cast(pid, {:push_data_many, items})
  end

  def pause_data(pid) do
    GenServer.cast(pid, :pause_data)
  end

  def resume_data(pid) do
    GenServer.cast(pid, :resume_data)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    props = Keyword.get(opts, :props, %{})
    rect = Keyword.get(opts, :rect, %{x: 0, y: 0, width: 10, height: 3})
    id = Keyword.get(opts, :id)
    session_ctx = Keyword.get(opts, :session_ctx, %{})

    Enum.each(session_ctx, fn {key, val} -> Process.put(key, val) end)

    WidgetStripCache.create()
    if id, do: Drafter.WidgetPidRegistry.register(id, self())

    widget_state = module.mount(props)
    data_channel = init_data_channel(opts)

    state = %__MODULE__{
      id: id,
      module: module,
      state: widget_state,
      rect: rect,
      data_channel: data_channel,
      auto_buffer: auto_buffer?(opts),
      image_throttle_ms: Keyword.get(opts, :image_throttle_ms, @default_image_throttle_ms)
    }

    strips = module.render(widget_state, rect)
    WidgetStripCache.put(id, rect, strips)
    request_image(module)

    {:ok, state}
  end

  defp init_data_channel(opts) do
    buffer_spec = Keyword.get(opts, :buffer)
    refresh = Keyword.get(opts, :refresh)

    case buffer_spec do
      nil -> nil
      :auto -> DataChannel.new(128, refresh || :on_demand)
      size when is_integer(size) and size > 0 -> DataChannel.new(size, refresh || :on_demand)
      _ -> nil
    end
  end

  defp auto_buffer?(opts), do: Keyword.get(opts, :buffer) == :auto

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
      render_and_push(new_state)
      {:noreply, new_state}
    end
  end

  def handle_cast({:push_data, item}, %{data_channel: ch} = state) when not is_nil(ch) do
    {:noreply, %{state | data_channel: DataChannel.push(ch, item)}}
  end

  def handle_cast({:push_data, _item}, state), do: {:noreply, state}

  def handle_cast({:push_data_many, items}, %{data_channel: ch} = state) when not is_nil(ch) do
    {:noreply, %{state | data_channel: DataChannel.push_many(ch, items)}}
  end

  def handle_cast({:push_data_many, _items}, state), do: {:noreply, state}

  def handle_cast(:pause_data, %{data_channel: ch} = state) when not is_nil(ch) do
    {:noreply, %{state | data_channel: DataChannel.pause(ch)}}
  end

  def handle_cast(:pause_data, state), do: {:noreply, state}

  def handle_cast(:resume_data, %{data_channel: ch} = state) when not is_nil(ch) do
    {:noreply, %{state | data_channel: DataChannel.resume(ch)}}
  end

  def handle_cast(:resume_data, state), do: {:noreply, state}

  def handle_cast(:maybe_generate_image, state) do
    {:noreply, schedule_image(state)}
  end

  @impl true
  def handle_call({:update_rect, rect}, _from, state) do
    new_widget_state =
      if function_exported?(state.module, :on_rect_change, 2) do
        state.module.on_rect_change(rect, state.state)
      else
        state.state
      end

    new_channel = maybe_resize_auto_buffer(state, rect)
    new_state = %{state | rect: rect, state: new_widget_state, data_channel: new_channel}
    render_and_push(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:get_render, _from, state) do
    Process.put(:widget_last_render_ms, System.monotonic_time(:millisecond))

    result =
      case WidgetStripCache.get(state.id) do
        nil ->
          render_state = maybe_apply_buffer(state)
          strips = state.module.render(render_state, state.rect)
          WidgetStripCache.put(state.id, state.rect, strips)
          request_image(state.module)
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
        request_image(new_state.module)
        {:reply, {:ok, new_widget_state}, new_state}

      {:ok, new_widget_state, actions} ->
        new_state = %{state | state: new_widget_state}
        strips = new_state.module.render(new_state.state, new_state.rect)
        WidgetStripCache.put(new_state.id, new_state.rect, strips)
        request_image(new_state.module)
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
    request_image(new_state.module)
    {:reply, :ok, new_state}
  end

  def handle_call({:capture_event, event}, _from, state) do
    if function_exported?(state.module, :handle_event_capture, 2) do
      result = state.module.handle_event_capture(event, state.state)

      case result do
        {:continue, updated_event, new_widget_state} ->
          {:reply, {:continue, updated_event, new_widget_state},
           %{state | state: new_widget_state}}

        {:stop, updated_event, new_widget_state, actions} ->
          handle_actions(state.id, actions)

          {:reply, {:stop, updated_event, new_widget_state, actions},
           %{state | state: new_widget_state}}

        {:prevent, updated_event, new_widget_state} ->
          {:reply, {:prevent, updated_event, new_widget_state},
           %{state | state: new_widget_state}}

        other ->
          {:reply, other, state}
      end
    else
      {:reply, {:continue, event, state.state}, state}
    end
  end

  @impl true
  def handle_info(:data_channel_tick, %{data_channel: ch, module: module} = state) when not is_nil(ch) do
    {new_ch, had_data} = DataChannel.flush(ch)

    if had_data and not recently_rendered?(state) do
      widget_state = apply_buffer_to_widget(module, state.state, DataChannel.buffer(new_ch), state.rect)
      new_state = %{state | state: widget_state, data_channel: new_ch}
      render_and_push(new_state)
      {:noreply, new_state}
    else
      {:noreply, %{state | data_channel: new_ch}}
    end
  end

  def handle_info(:data_channel_tick, state), do: {:noreply, state}

  def handle_info(:image_task_done, state) do
    done = %{state | image_task: nil, last_image_ms: System.monotonic_time(:millisecond)}
    {:noreply, schedule_image(done)}
  end

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

  @impl true
  def terminate(_reason, %{id: id}) when not is_nil(id) do
    clear_compositor_image(id)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp clear_compositor_image(id) do
    Drafter.Compositor.clear_image(id)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
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
    Process.put(:widget_last_render_ms, System.monotonic_time(:millisecond))
    trait_modules = get_trait_modules(server_state.module)

    render_state = maybe_apply_buffer(server_state)

    {adjusted_state, adjusted_rect} =
      Pipeline.apply_pre_render(trait_modules, render_state, server_state.rect)

    strips = server_state.module.render(adjusted_state, adjusted_rect)

    final_strips =
      Pipeline.apply_post_render(trait_modules, strips, adjusted_state, server_state.rect)

    WidgetStripCache.put(server_state.id, server_state.rect, final_strips)
    notify_render_needed(server_state.id)
    request_image(server_state.module)
  end

  defp request_image(module) do
    if function_exported?(module, :image, 3), do: GenServer.cast(self(), :maybe_generate_image)
  end

  defp schedule_image(%{module: module} = state) do
    cond do
      not function_exported?(module, :image, 3) -> state
      not WidgetStripCache.visible?(state.id) -> state
      state.image_task != nil -> state
      not image_due?(state) -> state
      true -> maybe_start_image(state)
    end
  end

  defp image_due?(%{last_image_ms: nil}), do: true

  defp image_due?(state) do
    System.monotonic_time(:millisecond) - state.last_image_ms >= state.image_throttle_ms
  end

  defp maybe_start_image(state) do
    hash = :erlang.phash2({state.state, state.rect})

    if hash == state.image_hash do
      state
    else
      %{state | image_task: spawn_image_task(state), image_hash: hash}
    end
  end

  defp spawn_image_task(%{module: module, state: widget_state, rect: rect, id: id}) do
    parent = self()
    ctx = session_context()

    spawn(fn ->
      Enum.each(ctx, fn {key, val} -> Process.put(key, val) end)
      store_image(id, safe_image(module, widget_state, rect, id))
      send(parent, :image_task_done)
    end)
  end

  defp store_image(id, {paint, clear, %{dx: dx, dy: dy, cols: cols, rows: rows}}) do
    Drafter.Compositor.put_image(id, paint, clear, dx, dy, cols, rows)
  end

  defp store_image(id, _other) do
    Drafter.Compositor.clear_image(id)
  end

  defp safe_image(module, widget_state, rect, id) do
    module.image(widget_state, rect, id)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp session_context do
    for key <- [
          :drafter_compositor,
          :drafter_event_manager,
          :drafter_theme_manager,
          :drafter_screen_manager,
          :drafter_event_handler
        ],
        value = Process.get(key),
        do: {key, value}
  end

  defp maybe_apply_buffer(%{data_channel: nil, state: widget_state}), do: widget_state

  defp maybe_apply_buffer(%{data_channel: ch, module: module, state: widget_state, rect: rect}) do
    apply_buffer_to_widget(module, widget_state, DataChannel.buffer(ch), rect)
  end

  defp apply_buffer_to_widget(module, widget_state, buffer, rect) do
    if function_exported?(module, :apply_data_buffer, 3) do
      module.apply_data_buffer(widget_state, buffer, rect)
    else
      widget_state
    end
  end

  defp get_trait_modules(module) do
    if function_exported?(module, :__widget_traits__, 0) do
      module.__widget_traits__()
    else
      []
    end
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

  defp recently_rendered?(_state) do
    interval = Drafter.AppRegistry.get_frame_interval() || 33
    last = Process.get(:widget_last_render_ms, 0)
    System.monotonic_time(:millisecond) - last < interval
  end

  defp maybe_resize_auto_buffer(%{auto_buffer: true, data_channel: ch}, rect) when not is_nil(ch) do
    new_size = max(8, rect.width)
    DataChannel.resize_buffer(ch, new_size)
  end

  defp maybe_resize_auto_buffer(%{data_channel: ch}, _rect), do: ch
end
