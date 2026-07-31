defmodule Drafter.Widget.EventRouter do
  @moduledoc false

  def route_event(module, event, state, handles, focusable, scroll_config \\ nil) do
    ctx = %{
      module: module,
      state: state,
      handles: handles,
      focusable: focusable,
      scroll_config: scroll_config
    }

    do_route(event, ctx)
  end

  defp do_route({:mouse, %{type: :scroll, direction: dir}}, ctx),
    do: route_scroll(ctx.module, dir, ctx.state, ctx.handles, ctx.scroll_config)

  defp do_route({:key, key}, ctx),
    do: route_key_simple(ctx.module, key, ctx.state, ctx.handles, ctx.scroll_config)

  defp do_route({:char, _} = event, ctx),
    do: route_char(ctx.module, event, ctx.state, ctx.handles)

  defp do_route({:bracketed_paste, text}, ctx),
    do: route_paste(ctx.module, text, ctx.state, ctx.handles)

  defp do_route({:key, key, mods}, ctx),
    do: route_key_with_mods(ctx.module, key, mods, ctx.state, ctx.handles)

  defp do_route({:mouse, %{type: :mouse_down, x: x, y: y}}, ctx),
    do:
      route_guarded(ctx.module, :handle_press, [x, y, ctx.state], :press, ctx.handles, ctx.state)

  defp do_route({:mouse, %{type: :mouse_up, x: x, y: y}}, ctx),
    do:
      route_guarded(
        ctx.module,
        :handle_mouse_up,
        [x, y, ctx.state],
        :mouse_up,
        ctx.handles,
        ctx.state
      )

  defp do_route({:mouse, %{type: :drag, x: x, y: y}}, ctx),
    do: route_guarded(ctx.module, :handle_drag, [x, y, ctx.state], :drag, ctx.handles, ctx.state)

  defp do_route({:mouse, %{type: :move, x: x, y: y}}, ctx),
    do:
      route_guarded(ctx.module, :handle_hover, [x, y, ctx.state], :hover, ctx.handles, ctx.state)

  defp do_route({:focus}, ctx), do: route_focus(ctx.module, ctx.state, ctx.focusable)
  defp do_route({:blur}, ctx), do: route_blur(ctx.state, ctx.focusable)
  defp do_route(event, ctx), do: route_custom(ctx.module, event, ctx.state)

  defp route_scroll(module, direction, state, handles, scroll_config) do
    cond do
      :scroll in handles and function_exported?(module, :handle_scroll, 2) ->
        module.handle_scroll(direction, state)

      :scroll in handles ->
        default_scroll(direction, state, scroll_config)

      true ->
        {:bubble, state}
    end
  end

  defp route_key_simple(module, key, state, handles, scroll_config) do
    cond do
      :keyboard in handles and function_exported?(module, :handle_key, 2) ->
        module.handle_key(key, state)

      scroll_config != nil and key in [:left, :ArrowLeft] ->
        default_scroll(:up, state, scroll_config)

      scroll_config != nil and key in [:right, :ArrowRight] ->
        default_scroll(:down, state, scroll_config)

      true ->
        {:bubble, state}
    end
  end

  defp route_char(module, event, state, handles) do
    if :char in handles and function_exported?(module, :handle_char, 2) do
      module.handle_char(event, state)
    else
      route_custom(module, event, state)
    end
  end

  defp route_paste(module, text, state, handles) do
    if :paste in handles and function_exported?(module, :handle_paste, 2) do
      module.handle_paste(Drafter.Clipboard.sanitize(text), state)
    else
      {:bubble, state}
    end
  end

  defp route_key_with_mods(module, key, mods, state, handles) do
    cond do
      :keyboard in handles and function_exported?(module, :handle_key, 3) ->
        module.handle_key(key, mods, state)

      :keyboard in handles and mods == [] and function_exported?(module, :handle_key, 2) ->
        module.handle_key(key, state)

      true ->
        {:bubble, state}
    end
  end

  defp route_guarded(module, callback, args, event_type, handles, state) do
    if event_type in handles and function_exported?(module, callback, length(args)) do
      apply(module, callback, args)
    else
      {:bubble, state}
    end
  end

  defp route_focus(_module, state, true), do: handle_focus(state, true)
  defp route_focus(_module, state, false), do: {:bubble, state}

  defp route_blur(state, true), do: handle_focus(state, false)

  defp route_blur(state, false), do: {:bubble, state}

  defp route_custom(module, event, state) do
    if function_exported?(module, :handle_custom_event, 2) do
      module.handle_custom_event(event, state)
    else
      {:bubble, state}
    end
  end

  defp handle_focus(state, focused?) when is_map(state) do
    {:ok, Map.put(state, :focused, focused?)}
  end

  defp handle_focus(state, _focused?) do
    {:ok, state}
  end

  defp default_scroll(_direction, state, nil), do: {:bubble, state}

  defp default_scroll(direction, state, config) when is_map(state) do
    step = Map.get(config, :step, 5)
    current_offset = Map.get(state, :_scroll_offset, 0)

    new_offset =
      case direction do
        :up -> max(0, current_offset - step)
        :down -> current_offset + step
      end

    {:ok, Map.put(state, :_scroll_offset, new_offset)}
  end

  defp default_scroll(_direction, state, _config), do: {:bubble, state}
end
