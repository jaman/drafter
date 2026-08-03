defmodule Drafter.BuiltinActionHandler do
  @moduledoc false

  @behaviour Drafter.ActionHandler

  @doc """
  Handle the standard action tuples.

  `{:ok, state}` and `{:noreply, state}` replace the accumulated state.
  `{:show_modal, screen, props, opts}`, `{:show_toast, message, opts}`,
  `{:push, screen, props, opts}`, `{:pop, result}` and
  `{:replace, screen, props, opts}` drive the screen manager and leave the state
  alone. Everything else is `:unhandled`.
  """
  @impl true
  @spec handle_action(term(), term()) :: {:ok, term()} | :unhandled
  def handle_action({:ok, new_state}, _acc_state), do: {:ok, new_state}

  def handle_action({:noreply, new_state}, _acc_state), do: {:ok, new_state}

  def handle_action({:show_modal, screen_module, props, opts}, acc_state) do
    Drafter.ScreenManager.show_modal(screen_module, props, opts)
    {:ok, acc_state}
  end

  def handle_action({:show_toast, message, opts}, acc_state) do
    Drafter.ScreenManager.show_toast(message, opts)
    {:ok, acc_state}
  end

  def handle_action({:push, screen_module, props, opts}, acc_state) do
    Drafter.ScreenManager.push(screen_module, props, opts)
    {:ok, acc_state}
  end

  def handle_action({:pop, result}, acc_state) do
    Drafter.ScreenManager.pop(result)
    {:ok, acc_state}
  end

  def handle_action({:replace, screen_module, props, opts}, acc_state) do
    Drafter.ScreenManager.replace(screen_module, props, opts)
    {:ok, acc_state}
  end

  def handle_action(_action, _acc_state), do: :unhandled
end
