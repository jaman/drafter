Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule Themes do
  use Drafter

  def mount(_props) do
    themes = Drafter.Theme.available_themes() |> Map.keys()
    %{current_theme: "textual-dark", available_themes: themes}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def render(state) do
    vertical([
      header("Theme Switcher"),
      scrollable(
        [
          label(""),
          label("Select a theme:", style: %{fg: {100, 150, 255}, bold: true}),
          label(""),
          radio_set(
            state.available_themes,
            id: :theme_picker,
            selected: state.current_theme,
            on_change: :theme_selected,
            cols: 2
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:theme_selected, theme_name, state) do
    Drafter.ThemeManager.set_theme(theme_name)
    {:ok, %{state | current_theme: theme_name}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(Themes)
