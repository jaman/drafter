defmodule Drafter.Integration.OptionListColumnsTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule Columns do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props) do
      %{
        groups: [
          {:first, ~w(a1 a2 a3)},
          {:second, ~w(b1 b2 b3)},
          {:third, ~w(c1 c2 c3)}
        ],
        picked: nil
      }
    end

    def render(state) do
      horizontal(
        Enum.map(state.groups, fn {id, items} ->
          box(
            [
              option_list(items,
                id: id,
                on_select: :pick,
                trigger: :mouse_up,
                expand_height: :fill,
                flex: 1
              )
            ],
            title: to_string(id),
            flex: 1
          )
        end),
        flex: 1
      )
    end

    def handle_event(:pick, item, state), do: {:ok, %{state | picked: item}}
    def handle_event(_event, _data, state), do: {:noreply, state}
  end

  setup do
    ctx = TUI.start_headless(Columns, %{}, size: {90, 12})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp focused(ctx), do: TUI.get_widget_hierarchy(ctx).focused_widget

  defp move(ctx, key) do
    before = focused(ctx)
    TUI.send_key(ctx, key)
    TUI.wait_for(ctx, fn c -> focused(c) != before end, timeout: 500)
    focused(ctx)
  end

  test "the first column holds focus on mount", %{ctx: ctx} do
    assert focused(ctx) == :first
  end

  test "right and left walk across the columns", %{ctx: ctx} do
    assert move(ctx, :right) == :second
    assert move(ctx, :right) == :third
    assert move(ctx, :left) == :second
    assert move(ctx, :left) == :first
  end

  test "left at the first column keeps focus there", %{ctx: ctx} do
    TUI.send_key(ctx, :left)
    Process.sleep(100)
    assert focused(ctx) == :first
  end

  test "up and down stay inside the focused column", %{ctx: ctx} do
    TUI.send_key(ctx, :down)

    TUI.wait_for(ctx, fn c -> TUI.get_widget_state(c, :first).highlighted_index == 1 end,
      timeout: 500
    )

    assert focused(ctx) == :first
    assert TUI.get_widget_state(ctx, :second).highlighted_index == 0
  end

  test "each column keeps its own highlight", %{ctx: ctx} do
    TUI.send_key(ctx, :down)

    TUI.wait_for(ctx, fn c -> TUI.get_widget_state(c, :first).highlighted_index == 1 end,
      timeout: 500
    )

    assert move(ctx, :right) == :second
    TUI.send_key(ctx, :down)
    TUI.send_key(ctx, :down)

    TUI.wait_for(ctx, fn c -> TUI.get_widget_state(c, :second).highlighted_index == 2 end,
      timeout: 500
    )

    assert TUI.get_widget_state(ctx, :first).highlighted_index == 1
  end

  test "only the focused column draws its marker", %{ctx: ctx} do
    TUI.await_render(ctx)
    text = TUI.screen_text(ctx)

    assert String.contains?(text, "▶ a1")
    refute String.contains?(text, "▶ b1")
    refute String.contains?(text, "▶ c1")
  end

  test "clicking an option in another column selects it and moves focus", %{ctx: ctx} do
    TUI.send_click(ctx, :third)
    TUI.wait_for(ctx, fn c -> focused(c) == :third end, timeout: 500)

    assert focused(ctx) == :third
  end
end
