defmodule Drafter.Widget.Trait.FocusableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Focusable

  describe "handle_event/3" do
    test "focus event sets focused to true" do
      state = Focusable.default_state()
      assert {:ok, %{focused: true}} = Focusable.handle_event({:focus}, state, %{})
    end

    test "blur event sets focused to false" do
      state = %{focused: true}
      assert {:ok, %{focused: false}} = Focusable.handle_event({:blur}, state, %{})
    end
  end
end
