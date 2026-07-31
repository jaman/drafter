defmodule Drafter.Application do
  @moduledoc false

  use Application

  @impl true
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
      Drafter.Session
    ]

    opts = [strategy: :one_for_one, name: Drafter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
