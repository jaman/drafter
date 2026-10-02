defmodule Drafter.Session do
  @moduledoc false

  use DynamicSupervisor

  @doc """
  Start the session supervisor, registered under this module's name.

  `opts` are accepted and discarded; the supervisor always uses a `:one_for_one`
  strategy.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a `Drafter.Session.Worker` under the session supervisor in `:isolated` mode.

  `opts` are appended to the worker's options, so every key listed by
  `Drafter.Session.Worker.start_link/1` may be passed here. `:driver_pid` is required:
  the worker talks to a driver process, not to a configuration.
  """
  @spec start_isolated(module(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_isolated(app_module, opts \\ []) do
    spec = {Drafter.Session.Worker, [app_module: app_module, mode: :isolated] ++ opts}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl DynamicSupervisor
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
