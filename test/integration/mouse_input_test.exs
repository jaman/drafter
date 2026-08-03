defmodule Drafter.Integration.MouseInputTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule Board do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{hits: [], hovered: nil}

    def render(_state) do
      vertical([
        button("Alpha", id: :alpha, on_click: :alpha_hit),
        button("Beta", id: :beta, on_click: :beta_hit)
      ])
    end

    def handle_event(:alpha_hit, _data, state), do: {:ok, %{state | hits: state.hits ++ [:alpha]}}
    def handle_event(:beta_hit, _data, state), do: {:ok, %{state | hits: state.hits ++ [:beta]}}
  end

  setup do
    ctx = TUI.start_headless(Board, %{}, size: {30, 6})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp rect(ctx, id), do: TUI.get_widget_hierarchy(ctx).widget_rects[id]
  defp hits(ctx), do: TUI.get_state(ctx).hits

  defp click_centre(ctx, id) do
    r = rect(ctx, id)
    TUI.send_click(ctx, r.x + div(r.width, 2), r.y + div(r.height, 2))
  end

  test "a coordinate click reaches the widget under it", %{ctx: ctx} do
    click_centre(ctx, :alpha)
    TUI.wait_for(ctx, fn c -> hits(c) == [:alpha] end, timeout: 1000)

    assert hits(ctx) == [:alpha]
  end

  test "coordinates select between widgets", %{ctx: ctx} do
    click_centre(ctx, :beta)
    TUI.wait_for(ctx, fn c -> hits(c) == [:beta] end, timeout: 1000)

    assert hits(ctx) == [:beta]
  end

  test "clicks accumulate in the order they arrive", %{ctx: ctx} do
    click_centre(ctx, :alpha)
    TUI.wait_for(ctx, fn c -> length(hits(c)) == 1 end, timeout: 1000)
    click_centre(ctx, :beta)
    TUI.wait_for(ctx, fn c -> length(hits(c)) == 2 end, timeout: 1000)

    assert hits(ctx) == [:alpha, :beta]
  end

  test "a click outside every widget hits nothing", %{ctx: ctx} do
    rects = TUI.get_widget_hierarchy(ctx).widget_rects |> Map.values()
    outside_y = rects |> Enum.map(&(&1.y + &1.height)) |> Enum.max()

    TUI.send_click(ctx, 1, outside_y + 5)
    Process.sleep(150)

    assert hits(ctx) == []
  end

  test "send_mouse delivers an arbitrary event", %{ctx: ctx} do
    r = rect(ctx, :alpha)

    TUI.send_mouse(ctx, %{
      type: :mouse_up,
      x: r.x + div(r.width, 2),
      y: r.y + div(r.height, 2),
      button: :left,
      mods: []
    })

    TUI.wait_for(ctx, fn c -> hits(c) == [:alpha] end, timeout: 1000)
    assert hits(ctx) == [:alpha]
  end
end
