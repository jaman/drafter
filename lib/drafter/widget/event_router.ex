defmodule Drafter.Widget.EventRouter do
  @moduledoc """
  Turns an event tuple into the right callback on a widget module.

  A widget declares which kinds of event it wants as a list of atoms, and this
  module calls the matching callback only when that atom is present and the module
  actually exports the function. Everything else returns `{:bubble, state}`, leaving
  the event to the parent.

  | event | declared kind | callback |
  | ----- | ------------- | -------- |
  | `{:key, key}` | `:keyboard` | `handle_key(key, state)` |
  | `{:key, key, mods}` | `:keyboard` | `handle_key(key, mods, state)`, or `handle_key(key, state)` when `mods` is empty |
  | `{:char, _} = event` | `:char` | `handle_char(event, state)` |
  | `{:bracketed_paste, text}` | `:paste` | `handle_paste(sanitized_text, state)` |
  | `{:mouse, %{type: :mouse_down}}` | `:press` | `handle_press(x, y, state)` |
  | `{:mouse, %{type: :mouse_up}}` | `:mouse_up` | `handle_mouse_up(x, y, state)` |
  | `{:mouse, %{type: :drag}}` | `:drag` | `handle_drag(x, y, state)` |
  | `{:mouse, %{type: :move}}` | `:hover` | `handle_hover(x, y, state)` |
  | `{:mouse, %{type: :scroll}}` | `:scroll` | `handle_scroll(direction, state)` |
  | `{:focus}` / `{:blur}` | — | sets `:focused` on the state when the widget is focusable |
  | anything else | — | `handle_custom_event(event, state)` |

  Paste text is passed through `Drafter.Clipboard.sanitize/1` before the callback
  sees it. `{:char, _}` falls through to `handle_custom_event/2` when `:char` is not
  declared, rather than bubbling.

  ## Default scrolling

  When `:scroll` is declared but the module exports no `handle_scroll/2`, and when
  left and right arrow keys arrive at a widget with a scroll config, the offset in
  the state key `:_scroll_offset` is moved by the config's `:step` (default `5`) and
  clamped at zero. A `nil` scroll config bubbles instead.
  """

  @doc """
  Route `event` to the callback `module` declares for it.

  Arguments:

    * `module` — the widget module
    * `event` — an event tuple as listed in `Drafter.Event`
    * `state` — the widget's current state, returned unchanged when nothing handles
      the event
    * `handles` — the event kinds the widget declared, as atoms
    * `focusable` — whether `{:focus}` and `{:blur}` set `:focused` on the state
    * `scroll_config` — map with an optional `:step` key enabling default scrolling,
      or `nil`

  `scroll_config` defaults to `nil`, which disables both the default wheel scrolling
  and the left/right arrow scrolling.

  Returns whatever the callback returned, in the shapes `Drafter.EventResult.parse/2`
  accepts, or `{:bubble, state}` when no callback applies.

      iex> state = %{focused: false}
      iex> Drafter.Widget.EventRouter.route_event(Drafter.Widget.Label, {:key, :enter}, state, [], false)
      {:bubble, %{focused: false}}

      iex> state = %{focused: false}
      iex> Drafter.Widget.EventRouter.route_event(Drafter.Widget.Label, {:focus}, state, [], true)
      {:ok, %{focused: true}}

      iex> state = %{focused: true}
      iex> Drafter.Widget.EventRouter.route_event(Drafter.Widget.Label, {:blur}, state, [], false)
      {:bubble, %{focused: true}}

      iex> state = %{}
      iex> event = {:mouse, %{type: :scroll, direction: :down}}
      iex> Drafter.Widget.EventRouter.route_event(Drafter.Widget.Label, event, state, [:scroll], false, %{step: 3})
      {:ok, %{_scroll_offset: 3}}

      iex> state = %{_scroll_offset: 2}
      iex> event = {:mouse, %{type: :scroll, direction: :up}}
      iex> Drafter.Widget.EventRouter.route_event(Drafter.Widget.Label, event, state, [:scroll], false, %{})
      {:ok, %{_scroll_offset: 0}}
  """
  @spec route_event(module(), tuple(), term(), [atom()], boolean(), map() | nil) :: term()
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
