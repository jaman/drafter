defmodule Drafter.Widget.Trait.Pipeline do
  @moduledoc """
  Runs the trait event pipeline for a widget.

  Events pass through each trait in declaration order. Each trait
  can pass, handle, or consume the event. After traits process,
  the event reaches the widget's own handler (unless consumed).
  """

  alias Drafter.Widget.EventRouter

  @spec run(module(), [module()], term(), map(), [atom()], boolean()) ::
          {:ok, map()} | {:ok, map(), list()} | {:bubble, map()} | {:noreply, map()}
  def run(widget_module, trait_modules, event, state, handles, focusable) do
    {final_state, consumed?} = run_traits(trait_modules, event, state)

    if consumed? do
      {:ok, final_state}
    else
      scroll_config =
        if function_exported?(widget_module, :__widget_capabilities__, 0) do
          widget_module.__widget_capabilities__()[:scroll]
        else
          nil
        end

      EventRouter.route_event(
        widget_module,
        event,
        final_state,
        handles,
        focusable,
        scroll_config
      )
    end
  end

  @spec run_traits([module()], term(), map()) :: {map(), boolean()}
  def run_traits(trait_modules, event, state) do
    Enum.reduce_while(trait_modules, {state, false}, fn trait_mod, {acc_state, _} ->
      dispatch_trait_event(trait_mod, event, acc_state)
    end)
  end

  defp dispatch_trait_event(trait_mod, event, acc_state) do
    if function_exported?(trait_mod, :handle_event, 3) do
      trait_state = extract_trait_state(acc_state, trait_mod)

      apply_trait_result(
        trait_mod,
        trait_mod.handle_event(event, trait_state, acc_state),
        acc_state
      )
    else
      {:cont, {acc_state, false}}
    end
  end

  defp apply_trait_result(_trait_mod, {:pass, _}, acc_state) do
    {:cont, {acc_state, false}}
  end

  defp apply_trait_result(trait_mod, {:ok, new_trait_state}, acc_state) do
    {:cont, {merge_trait_state(acc_state, trait_mod, new_trait_state), false}}
  end

  defp apply_trait_result(trait_mod, {:consume, new_trait_state}, acc_state) do
    {:halt, {merge_trait_state(acc_state, trait_mod, new_trait_state), true}}
  end

  @spec extract_trait_state(map(), module()) :: map()
  def extract_trait_state(widget_state, trait_mod) do
    keys = Map.keys(trait_mod.default_state())
    Map.take(widget_state, keys)
  end

  @spec merge_trait_state(map(), module(), map()) :: map()
  def merge_trait_state(widget_state, trait_mod, trait_state) do
    keys = Map.keys(trait_mod.default_state())

    Enum.reduce(keys, widget_state, fn key, acc ->
      Map.put(acc, key, Map.get(trait_state, key))
    end)
  end

  @spec apply_pre_render([module()], map(), map()) :: {map(), map()}
  def apply_pre_render([], state, rect), do: {state, rect}

  def apply_pre_render(trait_modules, state, rect) do
    Enum.reduce(trait_modules, {state, rect}, fn trait_mod, {acc_state, acc_rect} ->
      if function_exported?(trait_mod, :pre_render, 3) do
        trait_state = extract_trait_state(acc_state, trait_mod)
        {new_trait_state, new_rect} = trait_mod.pre_render(trait_state, acc_state, acc_rect)
        {merge_trait_state(acc_state, trait_mod, new_trait_state), new_rect}
      else
        {acc_state, acc_rect}
      end
    end)
  end

  @spec apply_post_render([module()], [term()], map(), map()) :: [term()]
  def apply_post_render([], strips, _state, _rect), do: strips

  def apply_post_render(trait_modules, strips, state, rect) do
    trait_modules
    |> Enum.reverse()
    |> Enum.reduce(strips, fn trait_mod, acc_strips ->
      if function_exported?(trait_mod, :post_render, 4) do
        trait_state = extract_trait_state(state, trait_mod)
        trait_mod.post_render(acc_strips, trait_state, state, rect)
      else
        acc_strips
      end
    end)
  end
end
