defmodule Drafter.Examples.CollapsibleDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      notifications: true,
      auto_save: false,
      dark_mode: true,
      selected_theme: "ocean",
      debug_mode: false,
      verbose_logs: false,
      crash_reports: true,
      last_action: "None"
    }
  end

  def render(state) do
    vertical([
      label("Collapsible Widget Demo — Tab to navigate, Enter/Space to expand"),
      label(""),
      collapsible(
        "About",
        "Collapsible sections can contain either text or interactive widgets. " <>
          "Use the content_height option to control the height of widget content. " <>
          "Tab between sections and press Enter or Space to expand or collapse.",
        expanded: true
      ),
      collapsible(
        "Notification Preferences",
        [
          checkbox("Enable notifications",
            id: :notifications,
            checked: state.notifications,
            on_change: :notifications_changed
          ),
          checkbox("Auto-save changes",
            id: :auto_save,
            checked: state.auto_save,
            on_change: :auto_save_changed
          ),
          checkbox("Dark mode",
            id: :dark_mode,
            checked: state.dark_mode,
            on_change: :dark_mode_changed
          )
        ],
        content_height: 3
      ),
      collapsible(
        "Theme Selection",
        [
          radio_set(
            [
              {"Ocean Blue", "ocean"},
              {"Forest Green", "forest"},
              {"Sunset Red", "sunset"},
              {"Midnight Dark", "midnight"}
            ],
            id: :theme_radio,
            selected: state.selected_theme,
            on_change: :theme_changed
          )
        ],
        content_height: 4
      ),
      collapsible(
        "Advanced / Debug",
        [
          checkbox("Debug mode",
            id: :debug_mode,
            checked: state.debug_mode,
            on_change: :debug_mode_changed
          ),
          checkbox("Verbose logging",
            id: :verbose_logs,
            checked: state.verbose_logs,
            on_change: :verbose_logs_changed
          ),
          checkbox("Send crash reports",
            id: :crash_reports,
            checked: state.crash_reports,
            on_change: :crash_reports_changed
          )
        ],
        content_height: 3
      ),
      label(""),
      label("Last action: #{state.last_action}")
    ])
  end

  def handle_event(:notifications_changed, value, state) do
    {:ok, %{state | notifications: value, last_action: "Notifications: #{value}"}}
  end

  def handle_event(:auto_save_changed, value, state) do
    {:ok, %{state | auto_save: value, last_action: "Auto-save: #{value}"}}
  end

  def handle_event(:dark_mode_changed, value, state) do
    {:ok, %{state | dark_mode: value, last_action: "Dark mode: #{value}"}}
  end

  def handle_event(:theme_changed, value, state) do
    {:ok, %{state | selected_theme: value, last_action: "Theme: #{value}"}}
  end

  def handle_event(:debug_mode_changed, value, state) do
    {:ok, %{state | debug_mode: value, last_action: "Debug mode: #{value}"}}
  end

  def handle_event(:verbose_logs_changed, value, state) do
    {:ok, %{state | verbose_logs: value, last_action: "Verbose logs: #{value}"}}
  end

  def handle_event(:crash_reports_changed, value, state) do
    {:ok, %{state | crash_reports: value, last_action: "Crash reports: #{value}"}}
  end

  def handle_event(_, _, state) do
    {:noreply, state}
  end
end
