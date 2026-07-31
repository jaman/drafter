defmodule Drafter.Runtime do
  @moduledoc """
  Behaviour for pluggable application runtime backends.

  The event loop, renderer, transport, and timer machinery are shared across every
  app. A *runtime backend* adapts a particular application style to that loop: how an
  app produces its initial state, and how it turns the loop's messages — input events,
  named callbacks, timers, lifecycle hooks — into new state and effects.

  `Drafter.Runtime.Callback` is the default LiveView-style backend
  (`mount`/`render`/`handle_event`). Alternative backends — e.g. an Elm-style reducer
  (`init`/`update`/`subscriptions`) — implement this same behaviour, so an app opts in
  with `use Drafter.App, runtime: MyBackend` without the loop needing to know the style.

  `render/1` is not part of this behaviour; the renderer calls the app's `render/1`
  directly.
  """

  @type app :: module()
  @type state :: term()
  @type result :: term()

  @doc "Produce the app's initial state from mount props (callback `mount`, reducer `init`)."
  @callback mount(app(), map()) :: state()

  @doc "Run the post-mount ready hook, returning possibly-updated state."
  @callback ready(app(), state()) :: state()

  @doc "Handle a raw input/framework event tuple, returning the app's event result."
  @callback handle_input(app(), term(), state()) :: result()

  @doc "Handle a named application message with its payload, returning the app's event result."
  @callback handle_message(app(), atom(), term(), state()) :: result()

  @doc "Handle a fired timer."
  @callback timer(app(), term(), state()) :: state()

  @doc "Handle an out-of-band process message delivered to the loop."
  @callback on_message(app(), term(), state()) :: state()

  @doc "Hook invoked while scrolling is active (for scroll-driven state)."
  @callback scroll_active(app(), state()) :: state()

  @doc "Hook invoked once scrolling settles."
  @callback scroll_idle(app(), state()) :: state()

  @doc "The app's preferred render interval in ms, or nil for the default."
  @callback refresh_rate(app()) :: pos_integer() | nil

  @doc """
  Resolve the runtime backend for an app module.

  A per-session override in the process dictionary (`:drafter_runtime_override`, set for
  e.g. shared sessions) wins; otherwise the app's declared `__runtime__/0`; otherwise the
  default callback backend.
  """
  @spec for_app(app()) :: module()
  def for_app(app_module) do
    normalize(Process.get(:drafter_runtime_override) || app_runtime(app_module))
  end

  defp app_runtime(app_module) do
    if function_exported?(app_module, :__runtime__, 0) do
      app_module.__runtime__()
    else
      Drafter.Runtime.Callback
    end
  end

  @doc """
  The mount props carried by `opts`, as a map.

  Every entry point that starts an app — `Drafter.run/2`, a pushed nested session, and
  `Drafter.run_session/3` behind the ssh and telnet transports — takes them under the
  single `:props` key, so an app's `mount/1` is handed the same map however it was
  started. Absent props are an empty map, never the surrounding options.
  """
  @spec mount_props(keyword() | map()) :: map()
  def mount_props(opts) when is_list(opts), do: opts |> Keyword.get(:props, %{}) |> Map.new()
  def mount_props(%{} = props), do: props

  @doc "Normalize a backend shorthand (`:callback`/`:reducer`) or module to a backend module."
  @spec normalize(atom()) :: module()
  def normalize(:callback), do: Drafter.Runtime.Callback
  def normalize(:reducer), do: Drafter.Runtime.Reducer
  def normalize(:shared), do: Drafter.Runtime.Shared
  def normalize(module) when is_atom(module), do: module
end
