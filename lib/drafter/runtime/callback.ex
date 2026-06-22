defmodule Drafter.Runtime.Callback do
  @moduledoc """
  Default LiveView-style runtime backend.

  Adapts the loop to an app's `mount/1`, `handle_event/2` (raw input events),
  `handle_event/3` (named callbacks), and the optional lifecycle hooks. Optional
  hooks that an app does not define fall through to returning the state unchanged.
  """

  @behaviour Drafter.Runtime

  @impl true
  def mount(app, props), do: app.mount(props)

  @impl true
  def ready(app, state), do: maybe(app, :on_ready, [state], state)

  @impl true
  def handle_input(app, event, state), do: app.handle_event(event, state)

  @impl true
  def handle_message(app, name, data, state), do: app.handle_event(name, data, state)

  @impl true
  def timer(app, timer_id, state), do: maybe(app, :on_timer, [timer_id, state], state)

  @impl true
  def on_message(app, msg, state), do: maybe(app, :on_message, [msg, state], state)

  @impl true
  def scroll_active(app, state), do: maybe(app, :on_scroll_active, [state], state)

  @impl true
  def scroll_idle(app, state), do: maybe(app, :on_scroll_idle, [state], state)

  @impl true
  def refresh_rate(app) do
    if function_exported?(app, :refresh_rate, 0), do: app.refresh_rate(), else: nil
  end

  defp maybe(app, fun, args, default) do
    if function_exported?(app, fun, length(args)), do: apply(app, fun, args), else: default
  end
end
