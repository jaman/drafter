defmodule Drafter.Widget.Trait.MigrationTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Button
  alias Drafter.Widget.Checkbox
  alias Drafter.Widget.Switch

  describe "Button trait migration" do
    test "is focusable via traits" do
      caps = Button.__widget_capabilities__()
      assert caps.focusable == true
    end

    test "handles mouse_up and keyboard" do
      caps = Button.__widget_capabilities__()
      assert :mouse_up in caps.handles
      assert :keyboard in caps.handles
    end

    test "has focusable trait" do
      caps = Button.__widget_capabilities__()
      assert :focusable in caps.traits
    end

    test "focus/blur works" do
      state = Button.mount(%{text: "Click me"})
      assert state.focused == false

      {:ok, focused_state} = Button.handle_event({:focus}, state)
      assert focused_state.focused == true

      {:ok, blurred_state} = Button.handle_event({:blur}, focused_state)
      assert blurred_state.focused == false
    end

    test "keyboard enter still triggers click" do
      state = Button.mount(%{text: "Test", on_click: fn -> {:app_callback, :clicked, nil} end})
      {:ok, new_state, _actions} = Button.handle_event({:key, :enter}, state)
      assert new_state.active == true
    end

    test "mouse_up still triggers click" do
      state = Button.mount(%{text: "Test", on_click: fn -> {:app_callback, :clicked, nil} end})

      {:ok, new_state, _actions} =
        Button.handle_event({:mouse, %{type: :mouse_up, x: 5, y: 1}}, state)

      assert new_state.active == true
    end
  end

  describe "Checkbox trait migration" do
    test "is focusable via traits" do
      caps = Checkbox.__widget_capabilities__()
      assert caps.focusable == true
    end

    test "has focusable trait" do
      caps = Checkbox.__widget_capabilities__()
      assert :focusable in caps.traits
    end

    test "focus/blur works" do
      state = Checkbox.mount(%{label: "Test"})
      {:ok, focused} = Checkbox.handle_event({:focus}, state)
      assert focused.focused == true
    end
  end

  describe "Switch trait migration" do
    test "is focusable via traits" do
      caps = Switch.__widget_capabilities__()
      assert caps.focusable == true
    end

    test "has focusable trait" do
      caps = Switch.__widget_capabilities__()
      assert :focusable in caps.traits
    end

    test "focus/blur works" do
      state = Switch.mount(%{})
      {:ok, focused} = Switch.handle_event({:focus}, state)
      assert focused.focused == true
    end
  end
end
