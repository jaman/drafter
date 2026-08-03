defmodule Drafter.TableOwner do
  @moduledoc """
  Owns the framework's shared ETS tables.

  The tables listed by `owned/0` are created when this process starts and live for
  the lifetime of the application. A module's own `create/0` is a no-op once its
  table exists, so calling it is safe but unnecessary.
  """

  use GenServer

  @owned [
    Drafter.WidgetStripCache,
    Drafter.WidgetPidRegistry,
    Drafter.AppRegistry
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The modules whose tables this process owns."
  @spec owned() :: [module()]
  def owned, do: @owned

  @impl GenServer
  def init(_opts) do
    Enum.each(@owned, &create_tables/1)
    {:ok, %{}}
  end

  defp create_tables(Drafter.AppRegistry), do: Drafter.AppRegistry.ensure_table()
  defp create_tables(module), do: module.create()
end
