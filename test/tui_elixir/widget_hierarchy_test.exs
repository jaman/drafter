defmodule Drafter.WidgetHierarchyTest do
  use ExUnit.Case
  alias Drafter.WidgetHierarchy

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "widget hierarchy creation" do
    test "creates empty hierarchy" do
      hierarchy = WidgetHierarchy.new()
      assert hierarchy.widgets == %{}
      assert hierarchy.focused_widget == nil
      assert hierarchy.hover_widget == nil
    end
  end

  describe "widget registration" do
    test "add_widget registers a widget" do
      hierarchy = WidgetHierarchy.new()
      widget_id = :test_widget

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        widget_id,
        Drafter.Widget.Label,
        %{text: "Test"}
      )

      assert Map.has_key?(hierarchy.widgets, widget_id)
      assert hierarchy.widgets[widget_id].module == Drafter.Widget.Label
    end

    test "add_widget sets parent when specified" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :parent,
        Drafter.Widget.Container,
        %{}
      )

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :child,
        Drafter.Widget.Label,
        %{text: "Child"},
        :parent
      )

      assert hierarchy.widgets[:child].parent == :parent
    end
  end

  describe "focus management" do
    test "focus_widget sets the focused widget" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Button,
        %{}
      )

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget2,
        Drafter.Widget.Button,
        %{}
      )

      hierarchy = WidgetHierarchy.focus_widget(hierarchy, :widget1)
      assert hierarchy.focused_widget == :widget1

      hierarchy = WidgetHierarchy.focus_widget(hierarchy, :widget2)
      assert hierarchy.focused_widget == :widget2
    end

    test "cycle_focus moves to next focusable widget" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Button,
        %{}
      )

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget2,
        Drafter.Widget.Button,
        %{}
      )

      hierarchy = WidgetHierarchy.focus_widget(hierarchy, :widget1)
      assert hierarchy.focused_widget == :widget1

      hierarchy = WidgetHierarchy.cycle_focus(hierarchy)
      assert hierarchy.focused_widget == :widget2

      hierarchy = WidgetHierarchy.cycle_focus(hierarchy)
      assert hierarchy.focused_widget == :widget1
    end
  end

  describe "event handling" do
    test "handle_event returns actions for button clicks" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :button1,
        Drafter.Widget.Button,
        %{text: "Click Me", on_click: fn -> {:app_callback, :button_clicked, nil} end},
        nil,
        %{x: 0, y: 0, width: 10, height: 3}
      )

      hierarchy = WidgetHierarchy.focus_widget(hierarchy, :button1)

      {_hierarchy, actions} = WidgetHierarchy.handle_event(hierarchy, {:key, :" "})
      assert actions == [{:app_callback, :button_clicked, nil}]
    end

    test "handle_event with tab key cycles focus" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :button1,
        Drafter.Widget.Button,
        %{text: "Button 1"},
        nil,
        %{x: 0, y: 0, width: 10, height: 3}
      )

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :button2,
        Drafter.Widget.Button,
        %{text: "Button 2"},
        nil,
        %{x: 0, y: 4, width: 10, height: 3}
      )

      hierarchy = WidgetHierarchy.focus_widget(hierarchy, :button1)

      {hierarchy, actions} = WidgetHierarchy.handle_event(hierarchy, {:key, :tab})
      assert hierarchy.focused_widget == :button2
      assert actions == []
    end
  end

  describe "widget state management" do
    test "get_widget_state returns widget state" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Label,
        %{text: "Test Label"}
      )

      state = WidgetHierarchy.get_widget_state(hierarchy, :widget1)
      assert state.text == "Test Label"
    end

    test "update_widget modifies widget state" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Label,
        %{text: "Original"}
      )

      hierarchy = WidgetHierarchy.update_widget(hierarchy, :widget1, %{text: "Updated"})

      state = WidgetHierarchy.get_widget_state(hierarchy, :widget1)
      assert state.text == "Updated"
    end
  end

  describe "widget rect management" do
    test "update_widget_rect sets widget rect" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Label,
        %{}
      )

      rect = %{x: 5, y: 10, width: 20, height: 3}
      hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, :widget1, rect)

      widget_rect = hierarchy.widget_rects[:widget1]
      assert widget_rect == rect
    end
  end

  describe "hover state" do
    test "mouse events update hover widget" do
      hierarchy = WidgetHierarchy.new()

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget1,
        Drafter.Widget.Button,
        %{},
        nil,
        %{x: 0, y: 0, width: 10, height: 3}
      )

      hierarchy = WidgetHierarchy.add_widget(
        hierarchy,
        :widget2,
        Drafter.Widget.Button,
        %{},
        nil,
        %{x: 0, y: 5, width: 10, height: 3}
      )

      # Mouse move event should update hover state
      {hierarchy, _actions} = WidgetHierarchy.handle_event(hierarchy, {:mouse, %{type: :move, x: 5, y: 1}})
      assert hierarchy.hover_widget == :widget1

      {hierarchy, _actions} = WidgetHierarchy.handle_event(hierarchy, {:mouse, %{type: :move, x: 5, y: 6}})
      assert hierarchy.hover_widget == :widget2
    end
  end
end
