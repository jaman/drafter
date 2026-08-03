defmodule Drafter.ActionHandler do
  @moduledoc """
  Behaviour for handling application action return values.

  Implement this behaviour to intercept action tuples returned from `handle_event/3`
  and translate them into state changes. Handlers live in the registering process's
  dictionary and are checked most-recently-registered first, stopping at the first
  that returns `{:ok, new_state}`. See `Drafter.ActionRegistry` for registration and
  dispatch. An action no handler claims leaves the accumulated state unchanged.

  ## Example

      defmodule MyApp.DrawerHandler do
        @behaviour Drafter.ActionHandler

        @impl true
        def handle_action({:open_drawer, id}, acc_state) do
          {:ok, %{acc_state | open_drawer: id}}
        end

        def handle_action(_action, _acc_state), do: :unhandled
      end

  Register before calling `Drafter.run/2`:

      Drafter.ActionRegistry.register(MyApp.DrawerHandler)
      Drafter.run(MyApp)

  Return `{:add_event, message, :info}` from any `handle_event/3` clause and the
  registered handler will receive it automatically.
  """

  @typedoc "The action tuple an application or widget returned."
  @type action :: term()

  @typedoc "The state accumulated so far while folding this event's actions."
  @type app_state :: map()

  @typedoc """
  What a handler returns.

  `{:ok, new_state}` claims the action and stops dispatch; `:unhandled` passes it to
  the next handler. Any other return raises `CaseClauseError` in
  `Drafter.ActionRegistry.dispatch/2`.
  """
  @type result :: {:ok, app_state()} | :unhandled

  @doc "Handle one action, returning `{:ok, new_state}` to claim it or `:unhandled` to pass."
  @callback handle_action(action(), app_state()) :: result()
end
