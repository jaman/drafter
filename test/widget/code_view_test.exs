defmodule Drafter.Widget.CodeViewTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.CodeView

  defp mounted(line_count, viewport_height) do
    source = Enum.map_join(1..line_count, "\n", fn n -> "line #{n}" end)
    state = CodeView.mount(%{source: source, language: :text})
    CodeView.on_rect_change(%{x: 0, y: 0, width: 40, height: viewport_height}, state)
  end

  defp scroll_to_bottom(state) do
    Enum.reduce(1..200, state, fn _step, acc ->
      {:ok, next} = CodeView.handle_key(:down, acc)
      next
    end)
  end

  test "scrolling stops when the last line reaches the bottom of the viewport" do
    state = scroll_to_bottom(mounted(40, 10))
    assert state.scroll_offset == 30
  end

  test "page_down clamps the same way" do
    {:ok, state} = CodeView.handle_key(:page_down, mounted(40, 10))
    {:ok, state} = CodeView.handle_key(:page_down, state)
    {:ok, state} = CodeView.handle_key(:page_down, state)
    {:ok, state} = CodeView.handle_key(:page_down, state)
    assert state.scroll_offset == 30
  end

  test "mouse wheel scrolling clamps the same way" do
    state =
      Enum.reduce(1..50, mounted(40, 10), fn _step, acc ->
        {:ok, next} = CodeView.handle_scroll(:down, acc)
        next
      end)

    assert state.scroll_offset == 30
  end

  test "content shorter than the viewport never scrolls" do
    state = scroll_to_bottom(mounted(5, 10))
    assert state.scroll_offset == 0
  end

  test "shrinking the viewport re-clamps an existing offset" do
    state = scroll_to_bottom(mounted(40, 10))
    grown = CodeView.on_rect_change(%{x: 0, y: 0, width: 40, height: 35}, state)
    assert grown.scroll_offset == 5
  end

  test "render at the bottom fills the viewport with the tail window" do
    Drafter.Test.SessionSetup.setup_session_pdict()
    state = scroll_to_bottom(mounted(40, 10))
    strips = CodeView.render(state, %{x: 0, y: 0, width: 40, height: 10})

    texts = Enum.map(strips, fn strip -> Enum.map_join(strip.segments, "", & &1.text) end)
    assert length(strips) == 10
    assert hd(texts) =~ "line 31"
    assert List.last(texts) =~ "line 40"
  end
end
