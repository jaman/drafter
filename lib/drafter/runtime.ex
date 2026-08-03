defmodule Drafter.Runtime do
  @moduledoc """
  Behaviour for pluggable application runtime backends.

  A *runtime backend* adapts an application style to Drafter's event loop: how an
  app produces its initial state, and how it turns the loop's messages — input
  events, named callbacks, timers, lifecycle hooks — into new state and effects.
  The loop, renderer, transport and timer machinery are the same whichever backend
  is in use.

  An app selects one with `use Drafter.App, runtime: MyBackend`. Two ship with
  Drafter: `Drafter.Runtime.Callback`, the default, taking `mount/1` and
  `handle_event/2,3`; and `Drafter.Runtime.Reducer`, taking `init/1` and `update/2`.

  `render/1` is not part of this behaviour. The renderer calls the app's `render/1`
  directly, so every backend requires the app to define it.
  """

  @type app :: module()
  @type state :: term()

  @typedoc """
  What a backend returns from `c:handle_input/3` and `c:handle_message/4`.

  `Drafter.EventResult.parse/2` turns any of these into `{state, actions, control}`,
  so a backend may return a bare state, `{:ok, state}`, `{:ok, state, actions}`,
  `{:noreply, state}`, `:handled`, `:unhandled`, or `{:stop, reason}`.
  """
  @type result :: term()

  @typedoc """
  A frame-pacing specification, as accepted by `Drafter.Runtime.FrameClock.interval_for/1`.

  `nil` means "no preference"; the loop then falls back to its own default.
  """
  @type refresh_rate :: pos_integer() | String.t() | :unlimited | nil

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

  @doc """
  The app's preferred frame pacing, or `nil` to let the loop choose.

  The value is passed to `Drafter.Runtime.FrameClock.interval_for/1`, so it may be a
  millisecond integer, an fps string such as `"30fps"`, `"unlimited"`, or `:unlimited`.
  """
  @callback refresh_rate(app()) :: refresh_rate()

  @doc """
  Resolve the runtime backend module for an app module.

  The first of these that is set wins: the calling process's
  `:drafter_runtime_override` process-dictionary entry, which a shared session sets;
  the app's own `__runtime__/0`, defined by `use Drafter.App, runtime: ...`; then
  `Drafter.Runtime.Callback`. The result is passed through `normalize/1`, so
  shorthand atoms are accepted in either place.
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

  Every entry point that starts an app — `Drafter.run/2`, a pushed nested session,
  and `Drafter.run_session/3` behind the ssh and telnet transports — carries mount
  props under the single `:props` key. `opts` is that keyword list, or a map, which
  is returned as the props themselves.

  Returns `%{}` when `:props` is absent. The surrounding options are never treated
  as props.

  ## Examples

      iex> Drafter.Runtime.mount_props(props: %{user_id: 7})
      %{user_id: 7}

      iex> Drafter.Runtime.mount_props(refresh_rate: "60fps")
      %{}

      iex> Drafter.Runtime.mount_props(props: [a: 1, b: 2])
      %{a: 1, b: 2}

      iex> Drafter.Runtime.mount_props(%{already: :props})
      %{already: :props}

  """
  @spec mount_props(keyword() | map()) :: map()
  def mount_props(opts) when is_list(opts), do: opts |> Keyword.get(:props, %{}) |> Map.new()
  def mount_props(%{} = props), do: props

  @doc """
  Normalize a backend shorthand or module to a backend module.

  Recognised shorthands are `:callback`, `:reducer` and `:shared`. Any other atom is
  returned unchanged, so a backend module may be given directly.

  ## Examples

      iex> Drafter.Runtime.normalize(:callback)
      Drafter.Runtime.Callback

      iex> Drafter.Runtime.normalize(:reducer)
      Drafter.Runtime.Reducer

      iex> Drafter.Runtime.normalize(:shared)
      Drafter.Runtime.Shared

      iex> Drafter.Runtime.normalize(Drafter.Runtime.Callback)
      Drafter.Runtime.Callback

  """
  @spec normalize(atom()) :: module()
  def normalize(:callback), do: Drafter.Runtime.Callback
  def normalize(:reducer), do: Drafter.Runtime.Reducer
  def normalize(:shared), do: Drafter.Runtime.Shared
  def normalize(module) when is_atom(module), do: module
end
