defmodule Drafter.Examples.SwitchDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    themes = Drafter.Theme.available_themes() |> Map.keys()

    %{
      current_theme: "textual-dark",
      available_themes: themes
    }
  end

  def render(state) do
    vertical([
      header("Switch Demo"),
      scrollable(
        [
          label(""),
          label("Theme Switcher", style: %{fg: {100, 150, 255}, bold: true}),
          label("Select a theme to apply:", style: %{fg: {150, 150, 150}}),
          label(""),
          render_theme_switches(state.available_themes, state.current_theme)
        ],
        flex: 1
      ),
      footer(
        bindings: [
          {"q", "Quit"},
          {"Tab", "Next"},
          {"Shift+Tab", "Prev"},
          {"Enter", "Select"}
        ]
      )
    ])
  end

  def handle_event({:theme_changed, theme_name}, enabled, state) do
    if enabled and state.current_theme != theme_name do
      Drafter.ThemeManager.set_theme(theme_name)
      {:ok, %{state | current_theme: theme_name}}
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :q}, state) do
    {:stop, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_theme_switches(themes, current_theme) do
    {left_col, right_col} = Enum.split(themes, div(length(themes) + 1, 2))

    horizontal(
      [
        vertical(
          Enum.map(left_col, fn theme_name ->
            switch(
              label: theme_name,
              enabled: current_theme == theme_name,
              on_change: {:theme_changed, theme_name},
              size: :compact
            )
          end),
          width: 30
        ),
        vertical(
          Enum.map(right_col, fn theme_name ->
            switch(
              label: theme_name,
              enabled: current_theme == theme_name,
              on_change: {:theme_changed, theme_name},
              size: :compact
            )
          end),
          width: 30
        )
      ],
      gap: 2
    )
  end
end
