defmodule Drafter.Examples.CalculatorTest do
  use ExUnit.Case, async: true

  alias Drafter.Examples.Calculator

  setup do
    if pid = Process.whereis(:tui_app_loop) do
      Process.unregister(:tui_app_loop)
      on_exit(fn -> Process.register(pid, :tui_app_loop) end)
    end

    Process.register(self(), :tui_app_loop)

    on_exit(fn ->
      if Process.whereis(:tui_app_loop) == self() do
        Process.unregister(:tui_app_loop)
      end
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
