defmodule Drafter.Examples.SimpleDemo do
  @moduledoc """
  A demonstration of the declarative TUI API.
  """

  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      name: "",
      feature_enabled: false,
      click_count: 0
    }
  end

  def render(state) do
    horizontal([
      theme_selector(),
      vertical([
        label("TUI Demo Application"),
        horizontal([
          button("Primary", type: :primary, on_click: :primary_clicked),
          button("Success", type: :success, on_click: :success_clicked),
          button("Warning", type: :warning, on_click: :warning_clicked)
        ]),
        horizontal([
          checkbox("Enable Feature", checked: state.feature_enabled, on_change: :feature_toggled),
          label("Clicked #{state.click_count} times")
        ]),
        text_input(
          value: state.name,
          placeholder: "Enter your name...",
          on_change: :name_changed,
          on_submit: :name_submitted
        )
      ])
    ])
  end

  def handle_event(:primary_clicked, _, state) do
    {:ok, %{state | click_count: state.click_count + 1}}
  end

  def handle_event(:success_clicked, _, state) do
    {:ok, %{state | click_count: state.click_count + 1}}
  end

  def handle_event(:warning_clicked, _, state) do
    {:ok, %{state | click_count: state.click_count + 1}}
  end

  def handle_event(:feature_toggled, enabled, state) do
    {:ok, %{state | feature_enabled: enabled}}
  end

  def handle_event(:name_changed, new_name, state) do
    {:ok, %{state | name: new_name}}
  end

  def handle_event(:name_submitted, _name, state) do
    {:ok, state}
  end

  def handle_event(_, _, state) do
    {:noreply, state}
  end

  def handle_event({:key, :d, [:ctrl]}, _state) do
    {:stop, :normal}
  end
end
