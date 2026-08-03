defmodule Drafter.Integration.CalculatorTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI
  alias Drafter.TestApps.Calculator

  setup do
    ctx = TUI.start_headless(Calculator)
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp value(ctx), do: TUI.get_state(ctx).value

  defp assert_value(ctx, expected) do
    TUI.wait_for(ctx, fn c -> value(c) == expected end, timeout: 1000)
    assert value(ctx) == expected
  end

  test "clicking a digit enters it", %{ctx: ctx} do
    TUI.send_click(ctx, :btn_9)
    assert_value(ctx, 9)
  end

  test "clicking the same digit twice enters it exactly twice", %{ctx: ctx} do
    TUI.send_click(ctx, :btn_9)
    TUI.send_click(ctx, :btn_9)
    assert_value(ctx, 99)
  end

  test "clicking three times enters it exactly three times", %{ctx: ctx} do
    for _ <- 1..3, do: TUI.send_click(ctx, :btn_9)
    assert_value(ctx, 999)
  end

  test "clicking different digits enters each once", %{ctx: ctx} do
    TUI.send_click(ctx, :btn_1)
    TUI.send_click(ctx, :btn_2)
    TUI.send_click(ctx, :btn_3)
    assert_value(ctx, 123)
  end

  test "keyboard digits enter the same way clicks do", %{ctx: ctx} do
    TUI.send_key(ctx, :"4")
    TUI.send_key(ctx, :"2")
    assert_value(ctx, 42)
  end

  test "arithmetic through the widget tree", %{ctx: ctx} do
    TUI.send_click(ctx, :btn_7)
    TUI.send_click(ctx, :btn_plus)
    TUI.send_click(ctx, :btn_5)
    TUI.send_click(ctx, :btn_equals)
    assert_value(ctx, 12)
  end
end
