defmodule Drafter.Runtime.Reducer do
  @moduledoc """
  Elm-style reducer runtime backend.

  An app using this backend defines `init/1` (initial state), `update/2`
  (`msg, state -> new_state`), and `render/1`. The loop's input events, named
  callbacks, timers, and out-of-band messages are all delivered to `update/2`:

    * raw input events arrive as their event tuple, e.g. `{:key, :q}`
    * named callbacks arrive as `{name, data}`
    * fired timers arrive as `{:timer, timer_id}`

  `update/2` returns the new state, or `{:stop, reason}` to quit. Render is skipped when it
  returns a state value-equal to the previous one.

  An app that does not define `update/2` falls back to the `Callback` backend.
  """

  @behaviour Drafter.Runtime

  alias Drafter.Runtime.Callback

  @impl true
  def mount(app, props) do
    if function_exported?(app, :init, 1), do: app.init(props), else: Callback.mount(app, props)
  end

  @impl true
  def ready(app, state), do: Callback.ready(app, state)

  @impl true
  def handle_input(app, event, state) do
    if reducer?(app),
      do: reduce(app, event, state),
      else: Callback.handle_input(app, event, state)
  end

  @impl true
  def handle_message(app, name, data, state) do
    if reducer?(app),
      do: reduce(app, {name, data}, state),
      else: Callback.handle_message(app, name, data, state)
  end

  @impl true
  def timer(app, timer_id, state) do
    if reducer?(app),
      do: app.update({:timer, timer_id}, state),
      else: Callback.timer(app, timer_id, state)
  end

  @impl true
  def on_message(app, msg, state) do
    if reducer?(app), do: app.update(msg, state), else: Callback.on_message(app, msg, state)
  end

  @impl true
  def scroll_active(app, state), do: Callback.scroll_active(app, state)

  @impl true
  def scroll_idle(app, state), do: Callback.scroll_idle(app, state)

  @impl true
  def refresh_rate(app), do: Callback.refresh_rate(app)

  defp reducer?(app), do: function_exported?(app, :update, 2)

  defp reduce(app, msg, state) do
    case app.update(msg, state) do
      {:stop, _reason} = stop -> stop
      ^state -> {:noreply, state}
      new_state -> {:ok, new_state}
    end
  end
end
