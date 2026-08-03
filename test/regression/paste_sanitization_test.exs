defmodule Drafter.Regression.PasteSanitizationTest do
  @moduledoc """
  Escape sequences in pasted text never reach a widget's buffer.

  Sanitizing runs where a paste is handed to the focused widget, the one point every
  widget goes through whether or not it is declarative. Sanitizing inside
  `Drafter.Widget.EventRouter` alone would reach only widgets declaring
  `handles: [:paste]`, and `TextInput`, `TextArea` and `FilePicker` each intercept
  `{:bracketed_paste, _}` in their own `handle_event/2` instead.

  Ordinary text and the newlines of a multi-line paste come through unchanged. The
  sanitizer strips the OSC 52 sequence that would rewrite the clipboard, and is
  idempotent, so sanitizing twice is harmless.
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

    test "still receives ordinary pasted text" do
      state = paste_into(Drafter.Widget.TextInput, %{text: "", focused: true}, "hello")

      assert state.text =~ "hello"
    end
  end

  describe "a text area" do
    test "receives pasted text with no escape sequences" do
      state = paste_into(Drafter.Widget.TextArea, %{text: "", focused: true}, @hostile)

      refute state.text =~ "\e"
      assert state.text =~ "safe"
    end

    test "keeps the newlines a multi-line paste carries" do
      state = paste_into(Drafter.Widget.TextArea, %{text: "", focused: true}, "one\ntwo")

      assert state.text =~ "one"
      assert state.text =~ "two"
      assert length(state.lines) == 2
    end
  end

  describe "the sanitizer itself" do
    test "is idempotent, so sanitizing twice is harmless" do
      once = Drafter.Clipboard.sanitize(@hostile)

      assert Drafter.Clipboard.sanitize(once) == once
    end

    test "strips the OSC 52 sequence that would rewrite the clipboard" do
      refute Drafter.Clipboard.sanitize(@hostile) =~ "\e]52"
    end
  end
end
