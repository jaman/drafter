defmodule Drafter.Application do
  @moduledoc false

  use Application

  alias Drafter.Transport.SSH.Sessions

  @doc """
  Start the Drafter supervision tree.

  Supervises, one-for-one: `Drafter.TableOwner`, `Drafter.ThemeManager`,
  `Drafter.SkinManager`, the `Drafter.Widget.Supervisor` dynamic supervisor, a
  `Phoenix.PubSub` named `Drafter.PubSub`, `Drafter.Style.StylesheetLoader`,
  `Drafter.Animation`, the unique `Drafter.Session.Registry`, the ssh sessions'
  registry (`Drafter.Transport.SSH.Sessions`), and `Drafter.Session`. As it stops,
  every ssh session is ended with its client's terminal restored.
  """
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      Drafter.TableOwner,
      Drafter.ThemeManager,
      Drafter.SkinManager,
      {DynamicSupervisor, strategy: :one_for_one, name: Drafter.Widget.Supervisor},
      {Phoenix.PubSub, name: Drafter.PubSub},
      Drafter.Style.StylesheetLoader,
      Drafter.Animation,
      {Registry, keys: :unique, name: Drafter.Session.Registry},
      Sessions,
      Drafter.Session
    ]

    opts = [strategy: :one_for_one, name: Drafter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def prep_stop(state) do
    Sessions.close_all("The server stopped.")
    state
  end
end
