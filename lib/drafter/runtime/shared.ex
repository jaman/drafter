defmodule Drafter.Runtime.Shared do
  @moduledoc """
  Runtime backend for shared multi-user sessions (e.g. an SSH chat served to many clients).

  Wraps the `Callback` backend but routes app state changes through a
  the shared-state server: when the app produces new state, it is pushed to
  the shared server, which broadcasts `{:shared_state_updated, state}` to every connected
  session. Each session merges its per-session `mount_props` over the shared state and
  re-renders, so all clients stay in sync while keeping their own view-local props.

  Selected per shared session at runtime, via the session's process dictionary, rather
  than by the app module. The same app can run standalone or shared.
  """

  @behaviour Drafter.Runtime

  alias Drafter.Runtime.Callback
  alias Drafter.Session.SharedState

  @doc """
  The current shared state merged with this session's props.

  With no shared-state server in the process dictionary, falls back to
  `Drafter.Runtime.Callback.mount/2`. Where both carry a key, `props` wins.
  """
  @impl true
  @spec mount(module(), map()) :: term()
  def mount(app, props) do
    case shared_pid() do
      nil -> Callback.mount(app, props)
      pid -> Map.merge(SharedState.get_state(pid), props)
    end
  end

  @doc "Delegates to `Drafter.Runtime.Callback.ready/2`."
  @impl true
  @spec ready(module(), term()) :: term()
  def ready(app, state), do: Callback.ready(app, state)

  @doc """
  Runs the app's `handle_event/2` and pushes any new state to the shared server.

  The result is returned unchanged; only `{:ok, state}` and `{:ok, state, actions}`
  trigger a broadcast.
  """
  @impl true
  @spec handle_input(module(), term(), term()) :: term()
  def handle_input(app, event, state), do: push(Callback.handle_input(app, event, state))

  @doc """
  Runs the app's `handle_event/3` and pushes any new state to the shared server.

  Broadcasts under the same conditions as `handle_input/3`.
  """
  @impl true
  @spec handle_message(module(), atom(), term(), term()) :: term()
  def handle_message(app, name, data, state),
    do: push(Callback.handle_message(app, name, data, state))

  @doc """
  Delegates to `Drafter.Runtime.Callback.timer/3`.

  Timer results are not broadcast to other sessions.
  """
  @impl true
  @spec timer(module(), term(), term()) :: term()
  def timer(app, timer_id, state), do: Callback.timer(app, timer_id, state)

  @doc """
  Adopts a broadcast `{:shared_state_updated, new_state}` as this session's state.

  This session's `:drafter_mount_props` are merged over the incoming state, so
  view-local props survive a broadcast. Any other message delegates to
  `Drafter.Runtime.Callback.on_message/3`.
  """
  @impl true
  @spec on_message(module(), term(), term()) :: term()
  def on_message(_app, {:shared_state_updated, new_state}, _state) do
    Map.merge(new_state, Process.get(:drafter_mount_props, %{}))
  end

  def on_message(app, msg, state), do: Callback.on_message(app, msg, state)

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

  defp push({:ok, new_state} = result), do: broadcast(new_state) && result
  defp push({:ok, new_state, _actions} = result), do: broadcast(new_state) && result
  defp push(other), do: other

  defp broadcast(new_state) do
    case shared_pid() do
      nil -> true
      pid -> SharedState.update_state(pid, new_state) == :ok
    end
  end

  defp shared_pid, do: Process.get(:drafter_shared_state)
end
