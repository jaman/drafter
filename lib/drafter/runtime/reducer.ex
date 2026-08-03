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

  @doc "Calls the app's `init/1`, falling back to `Callback.mount/2` when it defines none."
  @impl true
  @spec mount(module(), map()) :: term()
  def mount(app, props) do
    if function_exported?(app, :init, 1), do: app.init(props), else: Callback.mount(app, props)
  end

  @doc "Delegates to `Drafter.Runtime.Callback.ready/2`."
  @impl true
  @spec ready(module(), term()) :: term()
  def ready(app, state), do: Callback.ready(app, state)

  @doc """
  Passes the raw event tuple to the app's `update/2`.

  Returns `{:noreply, state}` when `update/2` returns a state equal to the one passed
  in, `{:stop, reason}` unchanged, and `{:ok, new_state}` otherwise. Apps without an
  `update/2` fall through to `Drafter.Runtime.Callback.handle_input/3`.
  """
  @impl true
  @spec handle_input(module(), term(), term()) ::
          {:ok, term()} | {:noreply, term()} | {:stop, term()} | term()
  def handle_input(app, event, state) do
    if reducer?(app),
      do: reduce(app, event, state),
      else: Callback.handle_input(app, event, state)
  end

  @doc """
  Passes a named callback to the app's `update/2` as `{name, data}`.

  Result shapes match `handle_input/3`. Apps without an `update/2` fall through to
  `Drafter.Runtime.Callback.handle_message/4`.
  """
  @impl true
  @spec handle_message(module(), atom(), term(), term()) ::
          {:ok, term()} | {:noreply, term()} | {:stop, term()} | term()
  def handle_message(app, name, data, state) do
    if reducer?(app),
      do: reduce(app, {name, data}, state),
      else: Callback.handle_message(app, name, data, state)
  end

  @doc """
  Passes a fired timer to the app's `update/2` as `{:timer, timer_id}`.

  Returns whatever `update/2` returns, without the equality check applied by
  `handle_input/3`.
  """
  @impl true
  @spec timer(module(), term(), term()) :: term()
  def timer(app, timer_id, state) do
    if reducer?(app),
      do: app.update({:timer, timer_id}, state),
      else: Callback.timer(app, timer_id, state)
  end

  @doc "Passes an out-of-band process message to the app's `update/2` verbatim."
  @impl true
  @spec on_message(module(), term(), term()) :: term()
  def on_message(app, msg, state) do
    if reducer?(app), do: app.update(msg, state), else: Callback.on_message(app, msg, state)
  end

  @doc "Delegates to `Drafter.Runtime.Callback.scroll_active/2`."
  @impl true
  @spec scroll_active(module(), term()) :: term()
  def scroll_active(app, state), do: Callback.scroll_active(app, state)

  @doc "Delegates to `Drafter.Runtime.Callback.scroll_idle/2`."
  @impl true
  @spec scroll_idle(module(), term()) :: term()
  def scroll_idle(app, state), do: Callback.scroll_idle(app, state)

  @doc "Delegates to `Drafter.Runtime.Callback.refresh_rate/1`."
  @impl true
  @spec refresh_rate(module()) :: Drafter.Runtime.refresh_rate()
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
