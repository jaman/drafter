defmodule Drafter.Integration.ArrowNavigationTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule Gallery do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{items: Enum.map(1..20, &"Item #{&1}"), picked: nil}

    def render(state) do
      vertical([
        option_list(state.items, id: :list, on_select: :pick, trigger: :mouse_up, flex: 1)
      ])
    end

    def handle_event(:pick, item, state), do: {:ok, %{state | picked: item}}
  end

  setup do
    ctx = TUI.start_headless(Gallery, %{}, size: {40, 12})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp index(ctx), do: TUI.get_widget_state(ctx, :list).highlighted_index

  defp press(ctx, key, times) do
    for _ <- 1..times do
      before = index(ctx)
      TUI.send_key(ctx, key)
      TUI.wait_for(ctx, fn c -> index(c) != before end, timeout: 500)
    end
  end

  test "one Down press moves exactly one row", %{ctx: ctx} do
    assert index(ctx) == 0
    press(ctx, :down, 1)
    assert index(ctx) == 1
  end

  test "each Down press advances by one, never skipping", %{ctx: ctx} do
    for expected <- 1..8 do
      press(ctx, :down, 1)

      assert index(ctx) == expected,
             "after #{expected} presses the cursor should be at #{expected}"
    end
  end

  test "Up reverses Down exactly", %{ctx: ctx} do
    press(ctx, :down, 5)
    assert index(ctx) == 5

    press(ctx, :up, 3)
    assert index(ctx) == 2
  end

  test "Up at the top does not wrap or move", %{ctx: ctx} do
    TUI.send_key(ctx, :up)
    Process.sleep(100)
    assert index(ctx) == 0
  end

  test "Down at the bottom stops there", %{ctx: ctx} do
    for _ <- 1..25 do
      TUI.send_key(ctx, :down)
      Process.sleep(15)
    end

    assert index(ctx) == 19
  end
end
