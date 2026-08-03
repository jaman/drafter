defmodule Drafter.Session.Context do
  @moduledoc """
  Resolves the per-session services a process is operating on behalf of.

  A Drafter session owns a compositor, an event manager, a screen manager and so
  on. The association between a process and its session's instances is held in
  the process dictionary, so it must be copied explicitly whenever work moves to
  another process: use `capture/0` in the originating process and `adopt/1` in
  the new one.

  Resolution falls back to a globally registered process of the same name, so a
  widget can be rendered outside any session.

  A session also carries the environment of the terminal it is attached to, read
  with `terminal_env/0`. For a session served over ssh or telnet that is the
  connecting client's environment, which is not the environment of the host the
  program runs on; `terminal_env/0` falls back to the host's when no session set
  one.
  """

  @env_key :drafter_terminal_env
  @protocol_key :drafter_terminal_protocol

  @roles %{
    event_manager: {:drafter_event_manager, Drafter.Event.Manager},
    compositor: {:drafter_compositor, Drafter.Compositor},
    theme_manager: {:drafter_theme_manager, Drafter.ThemeManager},
    screen_manager: {:drafter_screen_manager, Drafter.ScreenManager},
    event_handler: {:drafter_event_handler, Drafter.EventHandler},
    skin_manager: {:drafter_skin_manager, Drafter.SkinManager}
  }

  @type role ::
          :event_manager
          | :compositor
          | :theme_manager
          | :screen_manager
          | :event_handler
          | :skin_manager

  @doc "Every role a session context carries."
  @spec roles() :: [role()]
  def roles, do: Map.keys(@roles)

  @doc "The process-dictionary keys a session context occupies."
  @spec keys() :: [atom()]
  def keys do
    [@env_key, @protocol_key | Enum.map(@roles, fn {_role, {key, _fallback}} -> key end)]
  end

  @doc """
  Record the graphics protocol the terminal answered a probe with.

  `protocol` is `:kitty`, `:iterm2` or `:sixel`, or `nil` for a terminal that
  named none. Recording `nil` is not the same as recording nothing: a terminal
  that was asked and answered with no graphics is settled, and
  `terminal_protocol/0` reports `{:ok, nil}` for it, where a terminal that was
  never asked reports `:unprobed`.
  """
  @spec put_terminal_protocol(atom() | nil) :: :ok
  def put_terminal_protocol(protocol) do
    Process.put(@protocol_key, {:ok, protocol})
    :ok
  end

  @doc """
  The probed graphics protocol, or `:unprobed` when the terminal was never asked.

  A caller that gets `:unprobed` should fall back to detecting from
  `terminal_env/0`.
  """
  @spec terminal_protocol() :: {:ok, atom() | nil} | :unprobed
  def terminal_protocol, do: Process.get(@protocol_key, :unprobed)

  @doc """
  Record the environment of the terminal this session is attached to.

  `env` is a map of environment variable name to string value, as
  `System.get_env/0` returns. Carried to other processes by `capture/0` and
  `adopt/1` like any other part of the context.
  """
  @spec put_terminal_env(%{String.t() => String.t()}) :: :ok
  def put_terminal_env(env) when is_map(env) do
    Process.put(@env_key, env)
    :ok
  end

  @doc """
  The environment of the terminal this session is attached to.

  The session's own environment when one was recorded with `put_terminal_env/1`,
  and the host process's environment otherwise. A session that recorded an empty
  map gets that empty map, not the host's environment.
  """
  @spec terminal_env() :: %{String.t() => String.t()}
  def terminal_env, do: Process.get(@env_key) || System.get_env()

  @doc "Snapshot the calling process's context, for handing to another process."
  @spec capture() :: %{atom() => pid()}
  def capture do
    for key <- keys(), value = Process.get(key), into: %{}, do: {key, value}
  end

  @doc "Adopt a context captured by `capture/0`."
  @spec adopt(%{atom() => pid()} | keyword()) :: :ok
  def adopt(context) do
    Enum.each(context, fn
      {_key, nil} -> :ok
      {key, value} -> Process.put(key, value)
    end)
  end

  @doc """
  The process serving `role` for the calling session.

  Prefers the session's own instance, then a globally registered process of the
  same name, and finally `nil`.
  """
  @spec get(role()) :: pid() | atom() | nil
  def get(role) do
    {key, fallback} = Map.fetch!(@roles, role)
    Process.get(key) || registered(fallback)
  end

  @doc "Like `get/1`, but raises with the role named rather than returning `nil`."
  @spec fetch!(role()) :: pid() | atom()
  def fetch!(role) do
    get(role) ||
      raise "No #{role} available. Start a Drafter session, or pass one explicitly."
  end

  defp registered(name) do
    if Process.whereis(name), do: name
  end
end
