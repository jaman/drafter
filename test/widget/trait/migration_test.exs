defmodule Drafter.Widget.Trait.MigrationTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Button

  describe "Button trait migration" do
    test "handles mouse_up and keyboard" do
      caps = Button.__widget_capabilities__()
      assert :mouse_up in caps.handles
      assert :keyboard in caps.handles
    end

    test "keyboard enter still triggers click" do
      state = Button.mount(%{text: "Test", on_click: fn -> {:app_callback, :clicked, nil} end})
      {:ok, new_state, _actions} = Button.handle_event({:key, :enter}, state)
      assert new_state.active == true
    end
  end
end
