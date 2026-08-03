defmodule Drafter.Runtime.Callback do
  @moduledoc """
  Default LiveView-style runtime backend.

  Adapts the loop to an app's `mount/1`, `handle_event/2` (raw input events),
  `handle_event/3` (named callbacks), and the optional lifecycle hooks. Optional
  hooks that an app does not define fall through to returning the state unchanged.
  """

  @behaviour Drafter.Runtime

  @doc "Calls the app's `mount/1` with the mount props."
  @impl true
  @spec mount(module(), map()) :: term()
  def mount(app, props), do: app.mount(props)

  @doc "Calls the app's `on_ready/1` if it defines one, otherwise returns `state` unchanged."
  @impl true
  @spec ready(module(), term()) :: term()
  def ready(app, state), do: maybe(app, :on_ready, [state], state)

  @doc "Calls the app's `handle_event/2` with the raw event tuple."
  @impl true
  @spec handle_input(module(), term(), term()) :: term()
  def handle_input(app, event, state), do: app.handle_event(event, state)

  @doc "Calls the app's `handle_event/3` with the callback name and its payload."
  @impl true
  @spec handle_message(module(), atom(), term(), term()) :: term()
  def handle_message(app, name, data, state), do: app.handle_event(name, data, state)

  @doc "Calls the app's `on_timer/2` if it defines one, otherwise returns `state` unchanged."
  @impl true
  @spec timer(module(), term(), term()) :: term()
  def timer(app, timer_id, state), do: maybe(app, :on_timer, [timer_id, state], state)

  @doc "Calls the app's `on_message/2` if it defines one, otherwise returns `state` unchanged."
  @impl true
  @spec on_message(module(), term(), term()) :: term()
  def on_message(app, msg, state), do: maybe(app, :on_message, [msg, state], state)

  @doc "Calls the app's `on_scroll_active/1` if it defines one, otherwise returns `state` unchanged."
  @impl true
  @spec scroll_active(module(), term()) :: term()
  def scroll_active(app, state), do: maybe(app, :on_scroll_active, [state], state)

  @doc "Calls the app's `on_scroll_idle/1` if it defines one, otherwise returns `state` unchanged."
  @impl true
  @spec scroll_idle(module(), term()) :: term()
  def scroll_idle(app, state), do: maybe(app, :on_scroll_idle, [state], state)

  @doc "The app's `refresh_rate/0` if it defines one, otherwise `nil`."
  @impl true
  @spec refresh_rate(module()) :: Drafter.Runtime.refresh_rate()
  def refresh_rate(app) do
    if function_exported?(app, :refresh_rate, 0), do: app.refresh_rate(), else: nil
  end

  defp maybe(app, fun, args, default) do
    if function_exported?(app, fun, length(args)), do: apply(app, fun, args), else: default
  end
end
