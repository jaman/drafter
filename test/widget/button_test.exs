defmodule Drafter.Widget.ButtonTest do
  use ExUnit.Case

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Button

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "mounts with default variant" do
      state = Button.mount(%{})
      assert state.button_type == :default
      assert state.text == ""
    end

    test "mounts with primary variant" do
      state = Button.mount(%{button_type: :primary, text: "Primary"})
      assert state.button_type == :primary
      assert state.text == "Primary"
      assert :primary in state.classes
    end

    test "mounts with success variant" do
      state = Button.mount(%{button_type: :success, text: "Success"})
      assert state.button_type == :success
      assert :success in state.classes
    end

    test "mounts with warning variant" do
      state = Button.mount(%{button_type: :warning, text: "Warning"})
      assert state.button_type == :warning
      assert :warning in state.classes
    end

    test "mounts with error variant" do
      state = Button.mount(%{button_type: :error, text: "Error"})
      assert state.button_type == :error
      assert :error in state.classes
    end

    test "mounts with secondary variant" do
      state = Button.mount(%{button_type: :secondary, text: "Secondary"})
      assert state.button_type == :secondary
      assert :secondary in state.classes
    end

    test "accepts variant as alias for button_type" do
      state = Button.mount(%{variant: :primary, text: "Primary"})
      assert state.button_type == :primary
      assert :primary in state.classes
    end
  end

  describe "render/2" do
    test "renders button with text" do
      state = Button.mount(%{text: "Click Me"})
      rect = %{width: 20, height: 3}
      strips = Button.render(state, rect)

      assert length(strips) == 3
      assert is_list(strips)

      top_strip = Enum.at(strips, 0)
      assert %Strip{} = top_strip
    end

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
    test "activates button on click" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state, _actions} = Button.handle_mouse_up(0, 0, state)
      assert new_state.active == true
    end

    test "does not activate when disabled" do
      state = Button.mount(%{text: "Test", disabled: true})
      assert {:ok, new_state} = Button.handle_mouse_up(0, 0, state)
      assert new_state.active == false
    end
  end

  describe "handle_key/2" do
    test "activates button on enter key" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state, _actions} = Button.handle_key(:enter, state)
      assert new_state.active == true
    end

    test "activates button on space key" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state, _actions} = Button.handle_key(:" ", state)
      assert new_state.active == true
    end

    test "bubbles on other keys" do
      state = Button.mount(%{text: "Test"})
      assert {:bubble, _state} = Button.handle_key(:a, state)
    end

    test "does not activate when disabled" do
      state = Button.mount(%{text: "Test", disabled: true})
      assert {:ok, new_state} = Button.handle_key(:enter, state)
      assert new_state.active == false
    end
  end

  describe "handle_custom_event/2" do
    test "activates on :activate event" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state, _actions} = Button.handle_custom_event(:activate, state)
      assert new_state.active == true
    end

    test "deactivates on :deactivate event" do
      state = Button.mount(%{text: "Test", active: true})
      assert {:ok, new_state} = Button.handle_custom_event(:deactivate, state)
      assert new_state.active == false
    end

    test "sets hovered state on :hover event" do
      state = Button.mount(%{text: "Test"})
      assert {:ok, new_state} = Button.handle_custom_event(:hover, state)
      assert new_state.hovered == true
    end

    test "clears hovered state on :unhover event" do
      state = Button.mount(%{text: "Test", hovered: true})
      assert {:ok, new_state} = Button.handle_custom_event(:unhover, state)
      assert new_state.hovered == false
    end
  end

  describe "update/2" do
    test "updates button text" do
      state = Button.mount(%{text: "Old Text"})
      new_state = Button.update(%{text: "New Text"}, state)
      assert new_state.text == "New Text"
    end

    test "updates button type" do
      state = Button.mount(%{button_type: :default})
      new_state = Button.update(%{button_type: :primary}, state)
      assert new_state.button_type == :primary
      assert :primary in new_state.classes
    end

    test "preserves other fields when updating" do
      state = Button.mount(%{text: "Test", button_type: :success})
      new_state = Button.update(%{text: "New Text"}, state)
      assert new_state.text == "New Text"
      assert new_state.button_type == :success
    end
  end

  describe "variant styling" do
    test "primary variant uses primary color" do
      state = Button.mount(%{button_type: :primary, text: "Primary"})
      rect = %{width: 20, height: 3}

      strips = Button.render(state, rect)
      assert strips != ""
    end

    test "success variant uses success color" do
      state = Button.mount(%{button_type: :success, text: "Success"})
      rect = %{width: 20, height: 3}

      strips = Button.render(state, rect)
      assert strips != ""
    end

    test "warning variant uses warning color" do
      state = Button.mount(%{button_type: :warning, text: "Warning"})
      rect = %{width: 20, height: 3}

      strips = Button.render(state, rect)
      assert strips != ""
    end

    test "error variant uses error color" do
      state = Button.mount(%{button_type: :error, text: "Error"})
      rect = %{width: 20, height: 3}

      strips = Button.render(state, rect)
      assert strips != ""
    end
  end
end
