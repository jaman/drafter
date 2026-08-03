defmodule Drafter.Integration.ScreenTextTest do
  use ExUnit.Case, async: false

  alias Drafter.Examples.Counter
  alias Drafter.Test, as: TUI

  setup do
    ctx = TUI.start_headless(Counter, %{}, size: {44, 8})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  test "reads the text the user would see", %{ctx: ctx} do
    assert TUI.screen_text(ctx) =~ "Counter: 0"
  end

  test "reflects input", %{ctx: ctx} do
    TUI.send_key(ctx, :+)
    TUI.wait_for(ctx, fn c -> TUI.screen_text(c) =~ "Counter: 1" end, timeout: 1000)

    assert TUI.screen_text(ctx) =~ "Counter: 1"
    refute TUI.screen_text(ctx) =~ "Counter: 0"
  end

  test "carries no escape sequences", %{ctx: ctx} do
    refute TUI.screen_text(ctx) =~ "\e"
  end

  test "reports one entry per screen row", %{ctx: ctx} do
    assert length(TUI.screen_lines(ctx)) == 8
  end

  test "no row exceeds the screen width", %{ctx: ctx} do
    for line <- TUI.screen_lines(ctx) do
      assert String.length(line) <= 44
    end
  end

  test "blank rows read as empty rather than as spaces", %{ctx: ctx} do
    assert Enum.any?(TUI.screen_lines(ctx), &(&1 == ""))
  end
end
