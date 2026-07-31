defmodule Drafter.Widget.Trait.CollapsibleTraitTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Collapsible

  describe "metadata" do
    test "name is :collapsible" do
      assert :collapsible = Collapsible.name()
    end

    test "depends on focusable" do
      assert [:focusable] = Collapsible.dependencies()
    end

    test "handles keyboard and click" do
      handles = Collapsible.handles()
      assert :keyboard in handles
      assert :click in handles
    end

    test "is not layout static" do
      refute Collapsible.layout_static?()
    end

    test "render affecting fields include _expanded" do
      assert [:_expanded] = Collapsible.render_affecting_fields()
    end
  end

  describe "default_state/0" do
    test "starts collapsed" do
      state = Collapsible.default_state()
      assert state._expanded == false
    end
  end

  describe "handle_event/3 toggle" do
    test "enter toggles expanded state" do
      state = %{Collapsible.default_state() | _expanded: false}
      {:ok, new_state} = Collapsible.handle_event({:key, :enter}, state, %{})
      assert new_state._expanded == true
    end

    test "space toggles expanded state" do
      state = %{Collapsible.default_state() | _expanded: true}
      {:ok, new_state} = Collapsible.handle_event({:key, :" "}, state, %{})
      assert new_state._expanded == false
    end

    test "click on header row toggles" do
      state = %{Collapsible.default_state() | _expanded: false}
      {:ok, new_state} = Collapsible.handle_event({:mouse, %{type: :mouse_up, y: 0}}, state, %{})
      assert new_state._expanded == true
    end

    test "unhandled events pass through" do
      state = Collapsible.default_state()
      {:pass, _} = Collapsible.handle_event({:key, :tab}, state, %{})
    end
  end

  describe "pre_render/3" do
    test "collapsed shows only 1 row" do
      state = %{Collapsible.default_state() | _expanded: false}
      rect = %{x: 0, y: 0, width: 80, height: 20}

      {_, adjusted_rect} = Collapsible.pre_render(state, %{}, rect)
      assert adjusted_rect.height == 1
    end

    test "expanded shows full rect" do
      state = %{Collapsible.default_state() | _expanded: true}
      rect = %{x: 0, y: 0, width: 80, height: 20}

      {_, adjusted_rect} = Collapsible.pre_render(state, %{}, rect)
      assert adjusted_rect.height == 20
    end
  end
end
