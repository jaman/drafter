defmodule Drafter.Widget.CollapsibleTest do
  use ExUnit.Case
  alias Drafter.Draw.Strip
  alias Drafter.Widget.Collapsible

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "string content defaults content_height to nil" do
      state = Collapsible.mount(%{content: "some text"})
      assert state.content_height == nil
    end

    test "list content defaults content_height to 10" do
      state = Collapsible.mount(%{content: [%{type: :checkbox}]})
      assert state.content_height == 10
    end

    test "expanded defaults to false" do
      state = Collapsible.mount(%{})
      assert state.expanded == false
    end

    test "expanded can be set to true" do
      state = Collapsible.mount(%{expanded: true})
      assert state.expanded == true
    end

    test "focused defaults to false" do
      state = Collapsible.mount(%{})
      assert state.focused == false
    end

    test "title defaults to Collapsible" do
      state = Collapsible.mount(%{})
      assert state.title == "Collapsible"
    end
  end

  describe "render/2" do
    test "collapsed state renders exactly 1 strip when rect.height is 1" do
      state = Collapsible.mount(%{title: "Section", content: "body text"})
      strips = Collapsible.render(state, %{width: 20, height: 1})
      assert length(strips) == 1
    end

    test "collapsed state pads to rect.height when taller than 1" do
      state = Collapsible.mount(%{title: "Section", content: "body text"})
      strips = Collapsible.render(state, %{width: 20, height: 4})
      assert length(strips) == 4
    end

    test "expanded with string content renders title plus wrapped text strips" do
      state = Collapsible.mount(%{title: "Section", content: "hello world", expanded: true})
      strips = Collapsible.render(state, %{width: 20, height: 10})
      assert length(strips) <= 10
      assert Enum.all?(strips, fn s -> match?(%Strip{}, s) end)
      assert length(strips) >= 2
    end

    test "expanded with list content renders title plus blank placeholder strips" do
      state = Collapsible.mount(%{
        title: "Section",
        content: [%{type: :checkbox}],
        content_height: 3,
        expanded: true
      })
      strips = Collapsible.render(state, %{width: 20, height: 10})
      assert length(strips) >= 4
    end

    test "render returns strips equal to rect.height" do
      state = Collapsible.mount(%{title: "T", content: "text", expanded: false})
      strips = Collapsible.render(state, %{width: 30, height: 5})
      assert length(strips) == 5
    end
  end

  describe "update/2" do
    test "content_height is preserved when neither :content nor :content_height in props" do
      state = Collapsible.mount(%{content: [%{}], content_height: 7})
      new_state = Collapsible.update(%{title: "New Title"}, state)
      assert new_state.content_height == 7
    end

    test "explicit :content_height in props wins" do
      state = Collapsible.mount(%{content: "text"})
      new_state = Collapsible.update(%{content_height: 5}, state)
      assert new_state.content_height == 5
    end

    test "changing :content from string to list recalculates default content_height" do
      state = Collapsible.mount(%{content: "original string"})
      assert state.content_height == nil
      new_state = Collapsible.update(%{content: [%{type: :button}]}, state)
      assert new_state.content_height == 10
    end

    test "changing :content from list to string sets content_height to nil" do
      state = Collapsible.mount(%{content: [%{}]})
      assert state.content_height == 10
      new_state = Collapsible.update(%{content: "new text"}, state)
      assert new_state.content_height == nil
    end
  end

  describe "handle_event/2" do
    test "enter toggles expanded from false to true" do
      state = Collapsible.mount(%{title: "T", content: "body"})
      assert {:ok, new_state, _actions} = Collapsible.handle_event({:key, :enter}, state)
      assert new_state.expanded == true
    end

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

    test "toggle action includes :widget_layout_needed" do
      state = Collapsible.mount(%{title: "T", content: "body"})
      assert {:ok, _new_state, actions} = Collapsible.handle_event({:key, :enter}, state)
      assert :widget_layout_needed in actions
    end

    test "click on title row (y: 0) toggles expanded" do
      state = Collapsible.mount(%{title: "T", content: "body"})
      assert {:ok, new_state, _actions} = Collapsible.handle_event({:mouse, %{type: :mouse_up, y: 0}}, state)
      assert new_state.expanded == true
    end

    test "click on body row (y: 1) does not toggle" do
      state = Collapsible.mount(%{title: "T", content: "body"})
      assert {:noreply, new_state} = Collapsible.handle_event({:mouse, %{type: :click, y: 1}}, state)
      assert new_state.expanded == false
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

    test "unhandled event returns noreply" do
      state = Collapsible.mount(%{})
      assert {:noreply, ^state} = Collapsible.handle_event({:key, :tab}, state)
    end
  end
end
