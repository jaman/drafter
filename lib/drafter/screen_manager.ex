defmodule Drafter.ScreenManager do
  @moduledoc false

  use GenServer

  alias Drafter.{EventHandler, Screen}

  defstruct [
    :app_pid,
    :screen_stack,
    :toasts,
    :screen_rect,
    :toast_stack_limit
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec push(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def push(screen_module, props \\ %{}, opts \\ []) do
    GenServer.call(resolve(), {:push, screen_module, props, opts})
  end

  @spec pop(term()) :: {:ok, term()} | {:error, term()}
  def pop(result \\ nil) do
    GenServer.call(resolve(), {:pop, result})
  end

  @spec replace(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def replace(screen_module, props \\ %{}, opts \\ []) do
    GenServer.call(resolve(), {:replace, screen_module, props, opts})
  end

  @spec show_modal(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def show_modal(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :modal)
    push(screen_module, props, opts)
  end

  @spec show_popover(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def show_popover(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :popover)
    push(screen_module, props, opts)
  end

  @spec show_panel(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def show_panel(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :panel)
    push(screen_module, props, opts)
  end

  @spec show_toast(String.t(), keyword()) :: :ok
  def show_toast(message, opts \\ []) do
    GenServer.cast(resolve(), {:show_toast, message, opts})
  end

  @spec dismiss_toast(term()) :: :ok
  def dismiss_toast(toast_id) do
    GenServer.cast(resolve(), {:dismiss_toast, toast_id})
  end

  @spec set_toast_stack_limit(pos_integer()) :: :ok
  def set_toast_stack_limit(limit) when is_integer(limit) and limit > 0 do
    GenServer.cast(resolve(), {:set_toast_stack_limit, limit})
  end

  @spec get_active_screen() :: Screen.t() | nil
  def get_active_screen do
    GenServer.call(resolve(), :get_active_screen)
  end

  @spec get_all_screens() :: [Screen.t()]
  def get_all_screens do
    GenServer.call(resolve(), :get_all_screens)
  end

  @spec get_toasts() :: [map()]
  def get_toasts do
    GenServer.call(resolve(), :get_toasts)
  end

  @spec update_screen_hierarchy(term(), term()) :: :ok
  def update_screen_hierarchy(screen_id, hierarchy) do
    GenServer.cast(resolve(), {:update_hierarchy, screen_id, hierarchy})
  end

  @spec update_screen(term(), Screen.t()) :: :ok
  def update_screen(screen_id, updated_screen) do
    GenServer.cast(resolve(), {:update_screen, screen_id, updated_screen})
  end

  @spec update_screen_rect(term(), map()) :: :ok
  def update_screen_rect(screen_id, rect) do
    GenServer.cast(resolve(), {:update_rect, screen_id, rect})
  end

  @spec set_screen_rect(map()) :: :ok
  def set_screen_rect(rect) do
    GenServer.cast(resolve(), {:set_screen_rect, rect})
  end

  @spec register_app(pid()) :: :ok
  def register_app(app_pid) do
    GenServer.cast(resolve(), {:register_app, app_pid})
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(resolve(), :reset)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      app_pid: nil,
      screen_stack: [],
      toasts: [],
      screen_rect: %{x: 0, y: 0, width: 80, height: 24},
      toast_stack_limit: 3
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, screen_module, props, opts}, _from, state) do
    parent_id = top_screen_id(state.screen_stack)
    screen = screen_module |> Screen.new(props, opts) |> Map.put(:parent_id, parent_id)
    mounted_screen = Screen.mount_screen(screen)
    new_state = %{state | screen_stack: [mounted_screen | state.screen_stack]}

    register_screen_event_handler(mounted_screen.id, self())
    notify_render_needed(state.app_pid)

    {:reply, {:ok, mounted_screen.id}, new_state}
  end

  @impl true
  def handle_call({:pop, result}, _from, state) do
    case state.screen_stack do
      [] ->
        {:reply, {:error, :no_screens}, state}

      [top | rest] ->
        Screen.unmount_screen(top)
        new_stack = resume_parent(rest, result)
        new_state = %{state | screen_stack: new_stack}
        notify_render_needed(state.app_pid)
        {:reply, {:ok, result}, new_state}
    end
  end

  @impl true
  def handle_call({:replace, screen_module, props, opts}, _from, state) do
    case state.screen_stack do
      [] ->
        mounted = screen_module |> Screen.new(props, opts) |> Screen.mount_screen()
        new_state = %{state | screen_stack: [mounted]}
        notify_render_needed(state.app_pid)
        {:reply, {:ok, mounted.id}, new_state}

      [top | rest] ->
        Screen.unmount_screen(top)
        mounted = screen_module |> Screen.new(props, opts) |> Map.put(:parent_id, top.parent_id) |> Screen.mount_screen()
        new_state = %{state | screen_stack: [mounted | rest]}
        notify_render_needed(state.app_pid)
        {:reply, {:ok, mounted.id}, new_state}
    end
  end

  @impl true
  def handle_call(:get_active_screen, _from, state) do
    active = case state.screen_stack do
      [top | _] -> top
      [] -> nil
    end

    {:reply, active, state}
  end

  @impl true
  def handle_call(:get_all_screens, _from, state) do
    {:reply, state.screen_stack, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_toasts, _from, state) do
    {:reply, state.toasts, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Enum.each(state.screen_stack, fn screen ->
      if screen.widget_hierarchy do
        Drafter.WidgetHierarchy.stop_all_servers(screen.widget_hierarchy)
      end
    end)

    {:reply, :ok, %{state | screen_stack: [], toasts: []}}
  end

  @impl true
  def handle_cast({:show_toast, message, opts}, state) do
    variant = Keyword.get(opts, :variant, :info)
    duration = Keyword.get(opts, :duration, 3000)
    position = Keyword.get(opts, :position, :bottom_right)

    toast = %{
      id: make_ref(),
      message: message,
      variant: variant,
      position: position,
      created_at: System.monotonic_time(:millisecond),
      stack_index: 0
    }

    new_toasts = add_toast_with_stack_limit(state.toasts, toast, state.toast_stack_limit)
    new_state = %{state | toasts: new_toasts}

    Process.send_after(self(), {:expire_toast, toast.id}, duration)
    notify_render_needed(state.app_pid)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:dismiss_toast, toast_id}, state) do
    new_state = %{state | toasts: remove_toast(state.toasts, toast_id)}
    notify_render_needed(state.app_pid)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_toast_stack_limit, limit}, state) do
    {:noreply, %{state | toast_stack_limit: limit}}
  end

  @impl true
  def handle_cast({:set_screen_rect, rect}, state) do
    {:noreply, %{state | screen_rect: rect}}
  end

  @impl true
  def handle_cast({:register_app, app_pid}, state) do
    {:noreply, %{state | app_pid: app_pid}}
  end

  @impl true
  def handle_cast({:update_hierarchy, screen_id, hierarchy}, state) do
    new_stack =
      Enum.map(state.screen_stack, fn
        %{id: ^screen_id} = screen -> %{screen | widget_hierarchy: hierarchy}
        screen -> screen
      end)

    {:noreply, %{state | screen_stack: new_stack}}
  end

  @impl true
  def handle_cast({:update_screen, screen_id, updated_screen}, state) do
    new_stack =
      Enum.map(state.screen_stack, fn
        %{id: ^screen_id} -> updated_screen
        screen -> screen
      end)

    {:noreply, %{state | screen_stack: new_stack}}
  end

  @impl true
  def handle_cast({:update_rect, screen_id, rect}, state) do
    new_stack =
      Enum.map(state.screen_stack, fn
        %{id: ^screen_id} = screen -> %{screen | rect: rect}
        screen -> screen
      end)

    {:noreply, %{state | screen_stack: new_stack}}
  end

  @impl true
  def handle_info({:expire_toast, toast_id}, state) do
    new_state = %{state | toasts: remove_toast(state.toasts, toast_id)}
    notify_render_needed(state.app_pid)
    {:noreply, new_state}
  end

  defp resolve, do: Process.get(:drafter_screen_manager, __MODULE__)

  defp top_screen_id([top | _]), do: top.id
  defp top_screen_id([]), do: nil

  defp resume_parent([parent | others], result) do
    [Screen.resume_screen(parent, result) | others]
  end

  defp resume_parent([], _result), do: []

  defp register_screen_event_handler(screen_id, sm) do
    {:ok, _} =
      EventHandler.register_handler(
        :any,
        fn event -> dispatch_screen_event(screen_id, sm, event) end,
        sm,
        level: :top
      )
  end

  defp dispatch_screen_event(screen_id, sm, event) do
    screen = find_screen(sm, screen_id)
    do_dispatch_screen_event(screen, sm, event)
  end

  defp find_screen(sm, screen_id) do
    case GenServer.call(sm, :get_all_screens) do
      screens when is_list(screens) -> Enum.find(screens, &(&1.id == screen_id))
      _ -> nil
    end
  end

  defp do_dispatch_screen_event(nil, _sm, _event), do: :passthrough

  defp do_dispatch_screen_event(screen, sm, event) do
    manager_state = GenServer.call(sm, :get_state)
    screen_rect = screen.rect || calculate_screen_rect(screen, manager_state.screen_rect)
    route_event(screen, screen_rect, event, sm, manager_state)
  end

  defp route_event(screen, screen_rect, event, sm, manager_state) do
    cond do
      should_dismiss_on_outside_click?(screen, screen_rect, event) ->
        GenServer.call(sm, {:pop, :dismissed})
        :handled

      screen.widget_hierarchy != nil and should_forward_to_widget_hierarchy?(screen, screen_rect, event) ->
        handle_widget_hierarchy_result(
          handle_widget_hierarchy_event_direct(screen, screen_rect, event),
          screen,
          sm,
          manager_state
        )

      should_capture_event?(screen, event) ->
        handle_screen_event_result(
          Screen.handle_screen_event(screen, event),
          screen,
          sm,
          manager_state,
          :handled_on_noreply
        )

      true ->
        :passthrough
    end
  end

  defp handle_widget_hierarchy_result({:ok, updated_screen}, _screen, sm, manager_state) do
    GenServer.cast(sm, {:update_screen, updated_screen.id, updated_screen})
    send(manager_state.app_pid, :screen_render_needed)
    :handled
  end

  defp handle_widget_hierarchy_result({:pop, result}, _screen, sm, _manager_state) do
    GenServer.call(sm, {:pop, result})
    :handled
  end

  defp handle_widget_hierarchy_result({:show_modal, mod, props, opts}, _screen, sm, _manager_state) do
    GenServer.call(sm, {:push, mod, props, Keyword.put(opts, :type, :modal)})
    :handled
  end

  defp handle_widget_hierarchy_result({:push, mod, props, opts}, _screen, sm, _manager_state) do
    GenServer.call(sm, {:push, mod, props, opts})
    :handled
  end

  defp handle_widget_hierarchy_result({:replace, mod, props, opts}, _screen, sm, _manager_state) do
    GenServer.call(sm, {:replace, mod, props, opts})
    :handled
  end

  defp handle_widget_hierarchy_result({:passthrough, updated_screen}, screen, sm, manager_state) do
    GenServer.cast(sm, {:update_screen, screen.id, updated_screen})
    handle_screen_event_result(
      Screen.handle_screen_event(updated_screen, :passthrough_event),
      updated_screen,
      sm,
      manager_state,
      :passthrough
    )
  end

  defp handle_widget_hierarchy_result(:passthrough, _screen, _sm, _manager_state), do: :passthrough

  defp handle_screen_event_result({:ok, updated_screen}, _screen, sm, manager_state, _noreply_val) do
    GenServer.cast(sm, {:update_screen, updated_screen.id, updated_screen})
    send(manager_state.app_pid, :screen_render_needed)
    :handled
  end

  defp handle_screen_event_result({:noreply, _updated_screen}, _screen, _sm, _manager_state, noreply_val) do
    noreply_val
  end

  defp handle_screen_event_result({:pop, result}, _screen, sm, _manager_state, _noreply_val) do
    GenServer.call(sm, {:pop, result})
    :handled
  end

  defp handle_screen_event_result({:show_modal, mod, props, opts}, _screen, sm, _manager_state, _noreply_val) do
    GenServer.call(sm, {:push, mod, props, Keyword.put(opts, :type, :modal)})
    :handled
  end

  defp handle_screen_event_result({:push, mod, props, opts}, _screen, sm, _manager_state, _noreply_val) do
    GenServer.call(sm, {:push, mod, props, opts})
    :handled
  end

  defp handle_screen_event_result({:replace, mod, props, opts}, _screen, sm, _manager_state, _noreply_val) do
    GenServer.call(sm, {:replace, mod, props, opts})
    :handled
  end

  defp handle_screen_event_result(_other, _screen, _sm, _manager_state, _noreply_val), do: :passthrough

  defp should_capture_event?(%Screen{type: :modal, options: opts}, {:key, :escape}) do
    opts.dismissable
  end

  defp should_capture_event?(%Screen{type: :modal}, _event) do
    true
  end

  defp should_capture_event?(%Screen{type: :popover, options: opts}, {:key, :escape}) do
    opts.dismissable
  end

  defp should_capture_event?(%Screen{type: :popover}, {:mouse, %{type: :mouse_up}}) do
    true
  end

  defp should_capture_event?(%Screen{type: :popover}, {:key, _}) do
    true
  end

  defp should_capture_event?(%Screen{type: :panel}, _event) do
    true
  end

  defp should_capture_event?(%Screen{type: :default}, _event) do
    true
  end

  defp should_capture_event?(_screen, {:app_callback, _callback, _data}) do
    true
  end

  defp should_capture_event?(_, _) do
    false
  end

  defp notify_render_needed(nil), do: :ok

  defp notify_render_needed(app_pid) do
    send(app_pid, :screen_render_needed)
  end

  defp should_dismiss_on_outside_click?(screen, screen_rect, {:mouse, %{type: type, x: x, y: y}}) do
    screen.type == :modal and
      Map.get(screen.options, :dismissable, true) and
      type in [:press, :release] and
      screen_rect != nil and
      not point_in_rect?(x, y, screen_rect)
  end

  defp should_dismiss_on_outside_click?(_screen, _screen_rect, _event), do: false

  defp point_in_rect?(x, y, rect) do
    x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height
  end

  defp calculate_screen_rect(screen, screen_rect) do
    Drafter.Screen.calculate_rect(screen, screen_rect)
  end

  defp handle_widget_hierarchy_event_direct(screen, screen_rect, {:mouse, mouse_data}) do
    if point_in_rect?(mouse_data.x, mouse_data.y, screen_rect) or
         screen.widget_hierarchy.drag_capture_widget != nil do
      mouse_data
      |> then(&Drafter.WidgetHierarchy.handle_event(screen.widget_hierarchy, {:mouse, &1}))
      |> process_hierarchy_result(screen, :passthrough)
    else
      :passthrough
    end
  rescue
    _ -> :passthrough
  end

  defp handle_widget_hierarchy_event_direct(screen, _screen_rect, {:key, _} = event) do
    if screen.widget_hierarchy == nil do
      :passthrough
    else
      screen.widget_hierarchy
      |> Drafter.WidgetHierarchy.handle_event(event)
      |> process_hierarchy_result(screen, :ok)
    end
  rescue
    _ -> :passthrough
  end

  defp process_hierarchy_result({updated_hierarchy, []}, screen, empty_tag) do
    if meaningful_hierarchy_change?(screen.widget_hierarchy, updated_hierarchy) do
      updated_screen = %{screen | widget_hierarchy: updated_hierarchy}
      {empty_tag, updated_screen}
    else
      :passthrough
    end
  end

  defp process_hierarchy_result({updated_hierarchy, actions}, screen, _empty_tag) do
    updated_screen = %{screen | widget_hierarchy: updated_hierarchy}
    dispatch_hierarchy_actions(actions, updated_screen)
  end

  defp dispatch_hierarchy_actions(actions, updated_screen) do
    pop_action = Enum.find(actions, &match?({:pop, _}, &1))
    app_callback_action = Enum.find(actions, &match?({:app_callback, _, _}, &1))

    cond do
      pop_action ->
        {:pop, r} = pop_action
        {:pop, r}

      app_callback_action ->
        {:app_callback, callback, data} = app_callback_action
        invoke_screen_callback(updated_screen, callback, data)

      true ->
        {:ok, updated_screen}
    end
  end

  defp invoke_screen_callback(screen, callback, data) do
    result =
      if function_exported?(screen.module, :handle_event, 3) do
        screen.module.handle_event(callback, data, screen.state)
      else
        screen.module.handle_event(callback, screen.state)
      end

    map_screen_callback_result(result, screen)
  end

  defp map_screen_callback_result({:ok, new_state}, screen) do
    {:ok, %{screen | state: new_state}}
  end

  defp map_screen_callback_result({:noreply, new_state}, screen) do
    {:ok, %{screen | state: new_state}}
  end

  defp map_screen_callback_result({:pop, result}, _screen), do: {:pop, result}

  defp map_screen_callback_result({:push, mod, props, opts}, _screen) do
    {:push, mod, props, opts}
  end

  defp map_screen_callback_result({:show_modal, mod, props, opts}, _screen) do
    {:show_modal, mod, props, opts}
  end

  defp map_screen_callback_result({:show_toast, message, opts}, _screen) do
    {:show_toast, message, opts}
  end

  defp map_screen_callback_result({:replace, mod, props, opts}, _screen) do
    {:replace, mod, props, opts}
  end

  defp map_screen_callback_result(_other, screen), do: {:ok, screen}

  defp should_forward_to_widget_hierarchy?(screen, screen_rect, event) do
    screen.widget_hierarchy != nil and
      screen_rect != nil and
      (match?({:mouse, _}, event) or match?({:key, _}, event)) and
      not match?({:app_callback, _, _}, event)
  end

  defp meaningful_hierarchy_change?(old_hierarchy, new_hierarchy) do
    old_hierarchy.focused_widget != new_hierarchy.focused_widget or
      old_hierarchy.hover_widget != new_hierarchy.hover_widget or
      map_size(old_hierarchy.widgets) != map_size(new_hierarchy.widgets) or
      :erlang.phash2(old_hierarchy.widgets) != :erlang.phash2(new_hierarchy.widgets)
  end

  defp remove_toast(toasts, toast_id) do
    case Enum.find(toasts, &(&1.id == toast_id)) do
      nil ->
        toasts

      removed ->
        toasts
        |> Enum.reject(&(&1.id == toast_id))
        |> Enum.map(&shift_stack_index(&1, removed))
    end
  end

  defp shift_stack_index(%{position: pos, stack_index: idx} = toast, %{position: pos, stack_index: removed_idx})
       when idx > removed_idx do
    %{toast | stack_index: idx - 1}
  end

  defp shift_stack_index(toast, _removed), do: toast

  defp add_toast_with_stack_limit(toasts, new_toast, limit) do
    position = new_toast.position

    toasts_at_position =
      toasts
      |> Enum.filter(&(&1.position == position))
      |> Enum.sort_by(& &1.created_at)

    if length(toasts_at_position) >= limit do
      oldest_toast = hd(toasts_at_position)
      updated_toasts = remove_and_shift(toasts, oldest_toast, position)
      updated_toasts ++ [%{new_toast | stack_index: limit - 1}]
    else
      toasts ++ [%{new_toast | stack_index: length(toasts_at_position)}]
    end
  end

  defp remove_and_shift(toasts, oldest_toast, position) do
    toasts
    |> Enum.reject(&(&1.id == oldest_toast.id))
    |> Enum.map(&shift_after_removal(&1, oldest_toast, position))
  end

  defp shift_after_removal(%{position: pos, created_at: created_at} = toast, oldest, pos)
       when created_at > oldest.created_at do
    %{toast | stack_index: toast.stack_index - 1}
  end

  defp shift_after_removal(toast, _oldest, _position), do: toast
end
