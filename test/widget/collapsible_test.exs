defmodule Drafter.Widget.CollapsibleTest do
  use ExUnit.Case
  alias Drafter.Widget.Collapsible

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "render/2" do
    test "collapsed state pads to rect.height when taller than 1" do
      state = Collapsible.mount(%{title: "Section", content: "body text"})
      strips = Collapsible.render(state, %{width: 20, height: 4})
      assert length(strips) == 4
    end
  end

  describe "update/2" do
    test "content_height is preserved when neither :content nor :content_height in props" do
      state = Collapsible.mount(%{content: [%{}], content_height: 7})
      new_state = Collapsible.update(%{title: "New Title"}, state)
      assert new_state.content_height == 7
    end

    test "changing :content from list to string sets content_height to nil" do
      state = Collapsible.mount(%{content: [%{}]})
      assert state.content_height == 10
      new_state = Collapsible.update(%{content: "new text"}, state)
      assert new_state.content_height == nil
    end
  end

  describe "handle_event/2" do
    test "enter toggles expanded from true to false" do
      state = Collapsible.mount(%{title: "T", content: "body", expanded: true})
      assert {:ok, new_state, _actions} = Collapsible.handle_event({:key, :enter}, state)
      assert new_state.expanded == false
    end

    test "space toggles expanded" do
      state = Collapsible.mount(%{title: "T", content: "body"})
      assert {:ok, new_state, _actions} = Collapsible.handle_event({:key, :" "}, state)
      assert new_state.expanded == true
    end

    test "click on title row (y: 0) toggles expanded" do
      state = Collapsible.mount(%{title: "T", content: "body"})

      assert {:ok, new_state, _actions} =
               Collapsible.handle_event({:mouse, %{type: :mouse_up, y: 0}}, state)

      assert new_state.expanded == true
    end

    test "focus sets focused to true" do
      state = Collapsible.mount(%{})
      assert {:ok, new_state} = Collapsible.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "blur sets focused to false" do
      state = Collapsible.mount(%{})
      state = %{state | focused: true}
      assert {:ok, new_state} = Collapsible.handle_event({:blur}, state)
      assert new_state.focused == false
    end
  end
end
