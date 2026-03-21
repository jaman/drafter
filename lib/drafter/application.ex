defmodule Drafter.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Drafter.PubSub},
      Drafter.Style.StylesheetLoader,
      Drafter.Animation,
      Drafter.Event.CustomRegistry,
      Drafter.ActionRegistry,
      Drafter.EventHandler,
      Drafter.FocusRegistry,
      Drafter.ScreenManager,
      Drafter.ThemeManager,
      Drafter.SkinManager,
      {Registry, keys: :unique, name: Drafter.Session.Registry},
      Drafter.Session
    ]

    opts = [strategy: :one_for_one, name: Drafter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
