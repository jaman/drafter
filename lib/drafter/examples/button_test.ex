defmodule Drafter.Examples.ButtonTest do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      click_count: 0,
      last_clicked: nil
    }
  end

  def render(state) do
    vertical([
      label("Button Styling Test - Press Ctrl+D to quit"),
      label(""),
      label("Click count: #{state.click_count}  Last: #{state.last_clicked || "none"}"),
      label(""),
      horizontal([
        button("Default", on_click: :default_clicked),
        button("Primary", type: :primary, on_click: :primary_clicked),
        button("Success", type: :success, on_click: :success_clicked),
        button("Warning", type: :warning, on_click: :warning_clicked),
        button("Error", type: :error, on_click: :error_clicked)
      ])
    ])
  end

  def handle_event(event, state) do
    case event do
      {:widget_action, :default_clicked} ->
        {:ok, %{state | click_count: state.click_count + 1, last_clicked: "Default"}}

      {:widget_action, :primary_clicked} ->
        {:ok, %{state | click_count: state.click_count + 1, last_clicked: "Primary"}}

      {:widget_action, :success_clicked} ->
        {:ok, %{state | click_count: state.click_count + 1, last_clicked: "Success"}}

      {:widget_action, :warning_clicked} ->
        {:ok, %{state | click_count: state.click_count + 1, last_clicked: "Warning"}}

      {:widget_action, :error_clicked} ->
        {:ok, %{state | click_count: state.click_count + 1, last_clicked: "Error"}}

      {:key, :d, [:ctrl]} ->
        {:stop, :normal}

      {:key, :q, [:ctrl]} ->
        {:stop, :normal}

      _ ->
        {:noreply, state}
    end
  end
end
