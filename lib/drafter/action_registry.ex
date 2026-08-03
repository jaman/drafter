defmodule Drafter.ActionRegistry do
  @moduledoc """
  Per-session registry for `Drafter.ActionHandler` modules.

  Handlers are stored in the calling process dictionary and checked in
  reverse-registration order (last registered = highest priority).
  The built-in handler is always present and handles the standard return values
  (`{:ok, state}`, `{:noreply, state}`, `{:show_modal, ...}`, `{:show_toast, ...}`,
  `{:push, ...}`, `{:pop, ...}`, `{:replace, ...}`).

  ## Usage

      Drafter.ActionRegistry.register(MyApp.DrawerHandler)
      Drafter.run(MyApp)

  The `register/1` call stores the handler in the calling process's dictionary.
  `Drafter.run/2` collects them and passes them to the app loop process.
  """

  @pdict_key :drafter_action_handlers

  @doc """
  Reset the calling process's handler list to `extra_handlers` plus the built-in one.

  `extra_handlers` are checked before `Drafter.BuiltinActionHandler` and default to
  `[]`. Any handlers already registered in this process are discarded.
  """
  @spec init() :: :ok
  @spec init([module()]) :: :ok
  def init(extra_handlers \\ []) do
    base = [Drafter.BuiltinActionHandler]
    Process.put(@pdict_key, extra_handlers ++ base)
    :ok
  end

  @doc """
  Add `module` to the front of the calling process's handler list.

  The most recently registered handler is checked first. Registering the same module
  twice leaves two entries; the duplicate is harmless but never reached.
  """
  @spec register(module()) :: :ok
  def register(module) do
    handlers = Process.get(@pdict_key, [])
    Process.put(@pdict_key, [module | handlers])
    :ok
  end

  @doc """
  The calling process's handler list, highest priority first.

  Returns `[]` — not the built-in handler — when neither `init/1` nor `register/1`
  has run in this process. `Drafter.run/2` uses this to copy handlers into the app
  loop process.
  """
  @spec collect() :: [module()]
  def collect do
    Process.get(@pdict_key, [])
  end

  @doc """
  Offer `action` to each handler in turn and return the resulting state.

  Stops at the first handler returning `{:ok, new_state}` and returns that state.
  Returns `acc_state` unchanged when every handler returns `:unhandled`. In a process
  where nothing has been registered, only `Drafter.BuiltinActionHandler` is consulted.
  """
  @spec dispatch(term(), term()) :: term()
  def dispatch(action, acc_state) do
    handlers = Process.get(@pdict_key, [Drafter.BuiltinActionHandler])

    Enum.reduce_while(handlers, :unhandled, fn module, _ ->
      case module.handle_action(action, acc_state) do
        :unhandled -> {:cont, :unhandled}
        {:ok, new_state} -> {:halt, {:ok, new_state}}
      end
    end)
    |> case do
      {:ok, new_state} -> new_state
      :unhandled -> acc_state
    end
  end
end
