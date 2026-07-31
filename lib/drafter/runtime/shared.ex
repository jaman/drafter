defmodule Drafter.Runtime.Shared do
  @moduledoc """
  Runtime backend for shared multi-user sessions (e.g. an SSH chat served to many clients).

  Wraps the `Callback` backend but routes app state changes through a
  `Drafter.Session.SharedState` server: when the app produces new state, it is pushed to
  the shared server, which broadcasts `{:shared_state_updated, state}` to every connected
  session. Each session merges its per-session `mount_props` over the shared state and
  re-renders, so all clients stay in sync while keeping their own view-local props.

  Selected per shared session at runtime, via the session's process dictionary, rather
  than by the app module. The same app can run standalone or shared.
  """

  @behaviour Drafter.Runtime

  alias Drafter.Runtime.Callback
  alias Drafter.Session.SharedState

  @impl true
  def mount(app, props) do
    case shared_pid() do
      nil -> Callback.mount(app, props)
      pid -> Map.merge(SharedState.get_state(pid), props)
    end
  end

  @impl true
  def ready(app, state), do: Callback.ready(app, state)

  @impl true
  def handle_input(app, event, state), do: push(Callback.handle_input(app, event, state))

  @impl true
  def handle_message(app, name, data, state),
    do: push(Callback.handle_message(app, name, data, state))

  @impl true
  def timer(app, timer_id, state), do: Callback.timer(app, timer_id, state)

  @impl true
  def on_message(_app, {:shared_state_updated, new_state}, _state) do
    Map.merge(new_state, Process.get(:drafter_mount_props, %{}))
  end

  def on_message(app, msg, state), do: Callback.on_message(app, msg, state)

  @impl true
  def scroll_active(app, state), do: Callback.scroll_active(app, state)

  @impl true
  def scroll_idle(app, state), do: Callback.scroll_idle(app, state)

  @impl true
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
