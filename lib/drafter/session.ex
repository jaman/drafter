defmodule Drafter.Session do
  @moduledoc false

  use DynamicSupervisor

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_isolated(module(), map(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_isolated(app_module, driver_config, opts \\ []) do
    spec =
      {Drafter.Session.Worker,
       [app_module: app_module, driver_config: driver_config, mode: :isolated] ++ opts}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl DynamicSupervisor
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
