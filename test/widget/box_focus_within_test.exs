defmodule Drafter.Widget.BoxFocusWithinTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule TwoBoxes do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}

    def render(_state) do
      horizontal([
        box([button("One", id: :one)], id: :left, highlight_focus: true),
        box([button("Two", id: :two)], id: :right, highlight_focus: true)
      ])
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  defp focus_within(ctx, box_id), do: TUI.get_widget_state(ctx, box_id).focus_within

  test "the box holding the focused widget is marked, and the mark follows focus" do
    ctx = TUI.start_headless(TwoBoxes, %{}, size: {60, 10})

    assert :ok == TUI.wait_for(ctx, fn _ -> focus_within(ctx, :left) end, timeout: 1_000)
    refute focus_within(ctx, :right)

    TUI.send_key(ctx, :tab)

    assert :ok == TUI.wait_for(ctx, fn _ -> focus_within(ctx, :right) end, timeout: 1_000)
    refute focus_within(ctx, :left)

    TUI.stop(ctx)
  end
end
