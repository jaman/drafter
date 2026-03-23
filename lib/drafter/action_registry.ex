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

  @spec init() :: :ok
  @spec init([module()]) :: :ok
  def init(extra_handlers \\ []) do
    base = [Drafter.BuiltinActionHandler]
    Process.put(@pdict_key, extra_handlers ++ base)
    :ok
  end

  @spec register(module()) :: :ok
  def register(module) do
    handlers = Process.get(@pdict_key, [])
    Process.put(@pdict_key, [module | handlers])
    :ok
  end

  @spec collect() :: [module()]
  def collect do
    Process.get(@pdict_key, [])
  end

  @spec dispatch(term(), map()) :: map()
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
