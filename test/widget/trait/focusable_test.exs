defmodule Drafter.Widget.Trait.FocusableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Focusable

  describe "default_state/0" do
    test "returns focused: false" do
      assert %{focused: false} = Focusable.default_state()
    end
  end

  describe "handle_event/3" do
    test "focus event sets focused to true" do
      state = Focusable.default_state()
      assert {:ok, %{focused: true}} = Focusable.handle_event({:focus}, state, %{})
    end

    test "blur event sets focused to false" do
      state = %{focused: true}
      assert {:ok, %{focused: false}} = Focusable.handle_event({:blur}, state, %{})
    end

    test "unhandled events pass through" do
      state = Focusable.default_state()
      assert {:pass, ^state} = Focusable.handle_event({:click, 0, 0}, state, %{})
    end
  end

  describe "metadata" do
    test "name is :focusable" do
      assert :focusable = Focusable.name()
    end

    test "no dependencies" do
      assert [] = Focusable.dependencies()
    end

    test "handles focus and blur" do
      assert [:focus, :blur] = Focusable.handles()
    end

    test "render affecting fields include focused" do
      assert [:focused] = Focusable.render_affecting_fields()
    end

    test "is layout static" do
      assert Focusable.layout_static?()
    end
  end
end
