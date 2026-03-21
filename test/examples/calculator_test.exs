defmodule Drafter.Examples.CalculatorTest do
  use ExUnit.Case, async: false

  alias Drafter.Examples.Calculator

  setup do
    Drafter.AppRegistry.ensure_table()
    Drafter.AppRegistry.register()

    on_exit(fn ->
      Drafter.AppRegistry.unregister()
    end)

    :ok
  end

  test "keyboard digits delegate to button via activate_widget" do
    state = Calculator.mount(%{})

    assert {:noreply, ^state} = Calculator.handle_event({:key, :"1"}, state)
    assert_received {:activate_widget, :btn_1}
  end

  test "keyboard operators delegate to button via activate_widget" do
    state = %{value: 12, left: 0, op: nil, entering: true}

    assert {:noreply, ^state} = Calculator.handle_event({:key, :+}, state)
    assert_received {:activate_widget, :btn_plus}
  end
end
