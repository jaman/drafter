defmodule Drafter.Regression.PasteSanitizationTest do
  @moduledoc """
  Escape sequences in pasted text never reach a widget's buffer.

  Sanitizing runs where a paste is handed to the focused widget, the one point every
  widget goes through whether or not it is declarative. Sanitizing inside
  `Drafter.Widget.EventRouter` alone would reach only widgets declaring
  `handles: [:paste]`, and `TextInput`, `TextArea` and `FilePicker` each intercept
  `{:bracketed_paste, _}` in their own `handle_event/2` instead.
  """

  use ExUnit.Case, async: false

  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetHierarchy.EventRouter

  @hostile "safe\e[31m\e]52;c;aGk=\aX"
  @rect %{x: 0, y: 0, width: 40, height: 3}

  defp hierarchy_with(module, props) do
    WidgetHierarchy.new()
    |> WidgetHierarchy.add_widget(:target, module, props, nil, @rect, [])
    |> WidgetHierarchy.focus_widget(:target)
  end

  defp paste_into(module, props, text) do
    {hierarchy, _actions} =
      module
      |> hierarchy_with(props)
      |> EventRouter.dispatch_to_focused_or_ignore({:bracketed_paste, text})

    live_state(hierarchy)
  end

  defp live_state(hierarchy) do
    case WidgetHierarchy.get_widget_info(hierarchy, :target) do
      %{pid: pid} when is_pid(pid) -> Drafter.WidgetServer.get_state(pid)
      _ -> WidgetHierarchy.get_widget_state(hierarchy, :target)
    end
  end

  describe "a text input" do
    test "receives pasted text with no escape sequences" do
      state = paste_into(Drafter.Widget.TextInput, %{text: "", focused: true}, @hostile)

      refute state.text =~ "\e"
      assert state.text =~ "safe"
    end
  end
end
