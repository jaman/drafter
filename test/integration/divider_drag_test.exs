defmodule Drafter.Integration.DividerDragTest do
  @moduledoc """
  Dragging a split-pane divider tracks the pointer.

  The divider's rect must follow it during a drag. If it does not, each drag event
  measures the pointer against the divider's original column, so the offset grows
  without bound and the position clamps to one end of its range and then the other.
  """

  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule SplitApp do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{}

    def render(_state) do
      split_pane(
        [
          vertical([label("left")], flex: 1),
          vertical([label("right")], flex: 1)
        ],
        orientation: :horizontal,
        ratio: 0.5,
        id: :split,
        flex: 1
      )
    end

    def handle_event(_event, _data, state), do: {:noreply, state}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    ctx = DT.start_headless(SplitApp, %{}, size: {80, 20})
    on_exit(fn -> DT.stop(ctx) end)
    DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left" end, timeout: 3000)
    {:ok, ctx: ctx}
  end

  defp divider_column(ctx) do
    hierarchy = DT.get_widget_hierarchy(ctx)

    case Map.get(hierarchy.widget_rects, :split_divider) do
      %{x: x} -> x
      _ -> nil
    end
  end

  defp drag_to(ctx, x) do
    DT.send_mouse(ctx, %{type: :drag, x: x, y: 5, button: :left})
    Process.sleep(120)
  end

  test "the divider has a rect to start with", %{ctx: ctx} do
    assert is_integer(divider_column(ctx))
  end

  test "its rect follows the pointer instead of clamping to the ends", %{ctx: ctx} do
    start = divider_column(ctx)

    DT.send_mouse(ctx, %{type: :mouse_down, x: start, y: 5, button: :left})
    Process.sleep(120)

    drag_to(ctx, start + 6)
    after_right = divider_column(ctx)

    drag_to(ctx, start + 12)
    after_further = divider_column(ctx)

    DT.send_mouse(ctx, %{type: :mouse_up, x: start + 12, y: 5, button: :left})

    assert after_right > start,
           "the divider did not move right: #{start} -> #{after_right}"

    assert after_further > after_right,
           "the divider stopped tracking the pointer: #{after_right} -> #{after_further}"

    assert after_further - start < 40,
           "the divider jumped to an extreme rather than tracking: #{start} -> #{after_further}"
  end

  test "a drag does not slam between the two ends of the range", %{ctx: ctx} do
    start = divider_column(ctx)
    DT.send_mouse(ctx, %{type: :mouse_down, x: start, y: 5, button: :left})
    Process.sleep(120)

    columns =
      for step <- [2, 4, 6, 8] do
        drag_to(ctx, start + step)
        divider_column(ctx)
      end

    DT.send_mouse(ctx, %{type: :mouse_up, x: start + 8, y: 5, button: :left})

    assert columns == Enum.sort(columns),
           "the divider moved non-monotonically while the pointer moved one way: #{inspect(columns)}"

    assert length(Enum.uniq(columns)) > 1, "the divider never moved: #{inspect(columns)}"
  end
end
