defmodule Drafter.Widget.ButtonTest do
  use ExUnit.Case

  alias Drafter.Widget.Button

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "render/2" do
    test "renders different button heights" do
      state = Button.mount(%{text: "Test"})
      rect_3 = %{width: 20, height: 3}
      rect_5 = %{width: 20, height: 5}

      strips_3 = Button.render(state, rect_3)
      strips_5 = Button.render(state, rect_5)

      assert length(strips_3) == 3
      assert length(strips_5) == 5
    end
  end

  describe "handle_mouse_up/3" do
    test "does not activate when disabled" do
      state = Button.mount(%{text: "Test", disabled: true})
      assert {:ok, new_state} = Button.handle_mouse_up(0, 0, state)
      assert new_state.active == false
    end
  end

  describe "handle_key/2" do
    test "activates button on space key" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state, _actions} = Button.handle_key(:" ", state)
      assert new_state.active == true
    end
  end

  describe "update/2" do
    test "preserves other fields when updating" do
      state = Button.mount(%{text: "Test", button_type: :success})
      new_state = Button.update(%{text: "New Text"}, state)
      assert new_state.text == "New Text"
      assert new_state.button_type == :success
    end
  end
end
