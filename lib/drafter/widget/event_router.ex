defmodule Drafter.Widget.EventRouter do
  @moduledoc false

  def route_event(module, event, state, handles, focusable, scroll_config \\ nil) do
    case event do
      {:mouse, %{type: :scroll, direction: direction}} ->
        if :scroll in handles do
          if function_exported?(module, :handle_scroll, 2) do
            module.handle_scroll(direction, state)
          else
            default_scroll(direction, state, scroll_config)
          end
        else
          {:bubble, state}
        end

      {:key, key} ->
        cond do
          :keyboard in handles and function_exported?(module, :handle_key, 2) ->
            module.handle_key(key, state)

          scroll_config != nil and key in [:left, :"ArrowLeft"] ->
            default_scroll(:up, state, scroll_config)

          scroll_config != nil and key in [:right, :"ArrowRight"] ->
            default_scroll(:down, state, scroll_config)

          true ->
            {:bubble, state}
        end

      {:mouse, %{type: :mouse_down, x: x, y: y}} ->
        if :press in handles and function_exported?(module, :handle_press, 3) do
          module.handle_press(x, y, state)
        else
          {:bubble, state}
        end

      {:mouse, %{type: :mouse_up, x: x, y: y}} ->
        if :mouse_up in handles and function_exported?(module, :handle_mouse_up, 3) do
          module.handle_mouse_up(x, y, state)
        else
          {:bubble, state}
        end

      {:mouse, %{type: :drag, x: x, y: y}} ->
        if :drag in handles and function_exported?(module, :handle_drag, 3) do
          module.handle_drag(x, y, state)
        else
          {:bubble, state}
        end

      {:mouse, %{type: :move, x: x, y: y}} ->
        if :hover in handles and function_exported?(module, :handle_hover, 3) do
          module.handle_hover(x, y, state)
        else
          {:bubble, state}
        end

      {:focus} ->
        if focusable do
          if function_exported?(module, :keybindings, 0) do
            Drafter.FocusRegistry.set(module.keybindings())
          else
            Drafter.FocusRegistry.clear()
          end
          handle_focus(state, true)
        else
          {:bubble, state}
        end

      {:blur} ->
        if focusable do
          Drafter.FocusRegistry.clear()
          handle_focus(state, false)
        else
          {:bubble, state}
        end

      {:key, key, mods} ->
        cond do
          :keyboard in handles and function_exported?(module, :handle_key, 3) ->
            module.handle_key(key, mods, state)

          :keyboard in handles and function_exported?(module, :handle_key, 2) ->
            module.handle_key(key, state)

          true ->
            {:bubble, state}
        end

      _ ->
        if function_exported?(module, :handle_custom_event, 2) do
          module.handle_custom_event(event, state)
        else
          {:bubble, state}
        end
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
