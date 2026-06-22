Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

# Elm-style toggles. Each switch's `on_change:` sends a message carrying the new boolean;
# `update/2` folds it into the model, and `render/1` reflects the model back into the widgets.
defmodule Settings do
  use Drafter, runtime: :reducer

  state %{dark_mode: true, notifications: false, autosave: true}

  def render(state) do
    vertical([
      header("Settings — Elm/reducer style"),
      label(""),
      switch(label: "Dark mode", enabled: state.dark_mode, on_change: :set_dark),
      switch(label: "Notifications", enabled: state.notifications, on_change: :set_notifications),
      switch(label: "Auto-save", enabled: state.autosave, on_change: :set_autosave),
      label(""),
      label("dark_mode=#{state.dark_mode}  notifications=#{state.notifications}  autosave=#{state.autosave}",
        style: %{fg: :bright_black}
      ),
      footer(bindings: [{"Tab", "focus"}, {"Space", "toggle"}, {"q", "quit"}])
    ])
  end

  def update({:set_dark, value}, state), do: %{state | dark_mode: value}
  def update({:set_notifications, value}, state), do: %{state | notifications: value}
  def update({:set_autosave, value}, state), do: %{state | autosave: value}
  def update({:key, :q}, _state), do: {:stop, :normal}
  def update(_msg, state), do: state
end

Drafter.run(Settings)
