defmodule Drafter.Integration.SliderTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule Panel do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{cutoff: 0.0, reported: []}

    def render(_state) do
      vertical([
        slider(id: :cutoff, bind: :cutoff, show_value: false),
        slider(id: :voices, min: 0, max: 10, step: 1, value: 5, on_change: :voices_changed),
        button("Set", id: :setter, on_click: :set_voices)
      ])
    end

    def handle_event(:voices_changed, value, state),
      do: {:ok, %{state | reported: state.reported ++ [value]}}

    def handle_event(:set_voices, _data, state) do
      Drafter.set_widget_value(:voices, 9)
      {:ok, state}
    end
  end

  setup do
    ctx = TUI.start_headless(Panel, %{}, size: {40, 8})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp rect(ctx, id), do: TUI.get_widget_hierarchy(ctx).widget_rects[id]

  test "a click on the track sets the value and writes it back to the bound key", %{ctx: ctx} do
    track = rect(ctx, :cutoff)
    TUI.send_click(ctx, track.x + track.width - 1, track.y)

    TUI.wait_for(ctx, fn c -> TUI.get_state(c).cutoff == 1.0 end, timeout: 1000)

    assert TUI.get_state(ctx).cutoff == 1.0
    assert TUI.get_widget_value(ctx, :cutoff) == 1.0
  end

  test "a focused slider moves on the arrow keys and reports each new value", %{ctx: ctx} do
    TUI.send_click(ctx, :voices)
    clicked = TUI.get_widget_value(ctx, :voices)

    TUI.send_key(ctx, :right)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_value(c, :voices) == clicked + 1 end, timeout: 1000)

    assert TUI.get_widget_value(ctx, :voices) == clicked + 1
    assert List.last(TUI.get_state(ctx).reported) == clicked + 1
  end

  test "the widget value can be set from an app callback", %{ctx: ctx} do
    TUI.send_click(ctx, :setter)

    TUI.wait_for(ctx, fn c -> TUI.get_widget_value(c, :voices) == 9 end, timeout: 1000)

    assert TUI.get_widget_value(ctx, :voices) == 9
  end
end
