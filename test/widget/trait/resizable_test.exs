defmodule Drafter.Widget.Trait.ResizableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Resizable

  describe "metadata" do
    test "name is :resizable" do
      assert :resizable = Resizable.name()
    end

    test "depends on focusable" do
      assert [:focusable] = Resizable.dependencies()
    end

    test "handles drag, press, mouse_up, and hover" do
      handles = Resizable.handles()
      assert :drag in handles
      assert :press in handles
      assert :mouse_up in handles
      assert :hover in handles
    end

    test "is not layout static" do
      refute Resizable.layout_static?()
    end
  end

  describe "default_state/0" do
    test "initializes resize state" do
      state = Resizable.default_state()
      assert state._resizable == true
      assert state._min_width == 1
      assert state._min_height == 1
      assert state._max_width == nil
      assert state._resize_dragging == false
    end
  end
end
