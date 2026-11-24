defmodule Drafter.TextAreaWrapTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.TextArea

  @sentence "the quick brown fox jumps over the lazy dog"

  defp editor(opts),
    do: TextArea.mount(Map.merge(%{width: 14, height: 4, border: :none, focused: true}, opts))

  defp drawn(state) do
    state
    |> TextArea.render(%{x: 0, y: 0, width: state.width, height: state.height})
    |> Enum.map(fn strip ->
      strip.segments |> Enum.map_join(& &1.text) |> String.trim_trailing()
    end)
  end

  defp key(state, key) do
    {_tag, state} = TextArea.handle_event({:key, key}, state)
    state
  end

  test "a long line is drawn on rows broken at spaces" do
    assert drawn(editor(%{text: @sentence, wrap: :word})) ==
             ["the quick", "brown fox", "jumps over", "the lazy dog"]
  end

  test "without wrap the line runs past the edge" do
    assert hd(drawn(editor(%{text: @sentence}))) == "the quick brow"
  end

  test "down moves to the next row of the same line and keeps the column" do
    state = %{editor(%{text: @sentence, wrap: :word}) | cursor_col: 2}
    moved = key(state, :down)
    assert {moved.cursor_line, moved.cursor_col} == {0, 12}
    assert {key(moved, :up).cursor_line, key(moved, :up).cursor_col} == {0, 2}
  end

  test "rows scroll so the cursor's row stays in view" do
    state = editor(%{text: @sentence <> " and runs away", wrap: :word, height: 2})
    state = Enum.reduce(1..4, state, fn _step, acc -> key(acc, :down) end)
    assert state.scroll_offset == 3
  end

  test "on_edge is called with up on the first row and down on the last" do
    test_pid = self()
    on_edge = fn direction -> send(test_pid, {:edge, direction}) end
    state = editor(%{text: @sentence, wrap: :word, on_edge: on_edge})

    key(state, :up)
    assert_received {:edge, :up}

    moved = key(state, :down)
    refute_received {:edge, :down}
    assert moved.cursor_col > 0

    last = Enum.reduce(1..3, state, fn _step, acc -> key(acc, :down) end)
    key(last, :down)
    assert_received {:edge, :down}
  end
end
