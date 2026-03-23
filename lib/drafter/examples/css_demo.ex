defmodule Drafter.Examples.CSSDemo do
  @moduledoc false
  use Drafter.App, css_path: "examples/styles.tcss"

  def mount(_props) do
    %{count: 0, text: "", theme: Drafter.ThemeManager.get_current_theme().name}
  end

  def render(state) do
    vertical([
      header("CSS Styling Demo", show_clock: true),
      vertical(
        [
          label("Using CSS classes for styling", class: "title"),
          rule(),
          horizontal(
            [
              button("Primary Button", on_click: :primary_click, class: "primary"),
              button("Success Button", on_click: :success_click, class: "success"),
              button("Warning Button", on_click: :warning_click, class: "warning"),
              button("Error Button", on_click: :error_click, class: "error")
            ],
            gap: 1
          ),
          rule(),
          label("Counter: #{state.count}",
            class: ["counter", if(state.count > 5, do: "highlight", else: "normal")]
          ),
          horizontal(
            [
              button("Decrement", on_click: :decrement, class: "secondary"),
              button("Increment", on_click: :increment, class: "primary"),
              button("Reset", on_click: :reset, class: "danger")
            ],
            gap: 1
          ),
          rule(),
          label("Text Input with CSS styling:"),
          text_input(placeholder: "Type something...", bind: :text, class: "styled-input"),
          label("You typed: #{state.text}", class: "muted"),
          rule(),
          label("Custom Hex Colors:", class: "subtitle"),
          horizontal(
            [
              label("Red", style: %{fg: "#ff4444"}),
              label("Green", style: %{fg: "#44ff44"}),
              label("Blue", style: %{fg: "#4444ff"}),
              label("Cyan", style: %{fg: "rgb(68, 255, 255)"})
            ],
            gap: 2
          )
        ],
        flex: 1
      ),
      footer(
        bindings: [
          {"q", "Quit"},
          {"r", "Reset"},
          {"t", "Toggle Theme"}
        ]
      )
    ])
  end

  def handle_event(:increment, _data, state) do
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_event(:decrement, _data, state) do
    {:noreply, %{state | count: state.count - 1}}
  end

  def handle_event(:reset, _data, state) do
    {:noreply, %{state | count: 0, text: ""}}
  end

  def handle_event(:primary_click, _data, state) do
    {:noreply, %{state | count: state.count + 10}}
  end

  def handle_event(:success_click, _data, state) do
    {:noreply, %{state | count: state.count + 5}}
  end

  def handle_event(:warning_click, _data, state) do
    {:noreply, %{state | count: state.count - 5}}
  end

  def handle_event(:error_click, _data, state) do
    {:noreply, %{state | count: 0}}
  end

  def handle_event({:key_press, "t"}, _data, state) do
    themes = Map.keys(Drafter.Theme.available_themes())
    current_index = Enum.find_index(themes, &(&1 == state.theme)) || 0
    next_index = rem(current_index + 1, length(themes))
    next_theme = Enum.at(themes, next_index)
    Drafter.ThemeManager.set_theme(next_theme)
    {:noreply, %{state | theme: next_theme}}
  end

  def handle_event({:key_press, "r"}, _data, state) do
    {:noreply, %{state | count: 0, text: ""}}
  end

  def handle_event(_event, _data, state) do
    {:noreply, state}
  end
end
