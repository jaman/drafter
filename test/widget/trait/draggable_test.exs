defmodule Drafter.Widget.Trait.DraggableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Draggable

  describe "metadata" do
    test "name is :draggable" do
      assert :draggable = Draggable.name()
    end

    test "depends on focusable" do
      assert [:focusable] = Draggable.dependencies()
    end

    test "handles press, drag, and mouse_up" do
      handles = Draggable.handles()
      assert :press in handles
      assert :drag in handles
      assert :mouse_up in handles
    end

    test "is not layout static" do
      refute Draggable.layout_static?()
    end
  end

  describe "default_state/0" do
    test "initializes drag state" do
      state = Draggable.default_state()
      assert state._drag_active == false
      assert state._drag_offset_x == 0
      assert state._drag_offset_y == 0
    end
  end
end
