defmodule Drafter.TextAreaRenderTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Segment
  alias Drafter.Widget.TextArea
  alias Drafter.Widget.TextArea.{Cursor, Render}

  defp seg(text), do: Segment.new(text, %{fg: {200, 200, 200}, bg: {40, 40, 40}})

  defp text_of(segments), do: Enum.map_join(segments, & &1.text)

  describe "slice_segments" do
    test "windows a segment list by display column" do
      sliced = Render.slice_segments([seg("hello"), seg("world")], 3, 4)
      assert text_of(sliced) == "lowo"
    end

    test "empty when start is past the end" do
      assert Render.slice_segments([seg("hi")], 10, 5) == []
    end
  end

  describe "overlay_cursor" do
    test "splits the segment under the cursor and recolors one cell" do
      result = Render.overlay_cursor([seg("hello")], 2, 10, %{fg: {1, 1, 1}, bg: {2, 2, 2}})
      assert text_of(result) == "hello"
      cursor = Enum.find(result, &(&1.style.bg == {255, 255, 255}))
      assert cursor.text == "l"
    end

    test "places a cursor cell past end of content" do
      result = Render.overlay_cursor([seg("hi")], 4, 10, %{fg: {1, 1, 1}, bg: {2, 2, 2}})
      cursor = Enum.find(result, &(&1.style.bg == {255, 255, 255}))
      assert cursor.text == " "
      assert text_of(result) == "hi   "
    end

    test "negative column leaves segments untouched" do
      assert Render.overlay_cursor([seg("hi")], -1, 10, %{}) == [seg("hi")]
    end
  end

  describe "horizontal scroll keeps the cursor visible" do
    defp scroll_state(cursor_col, h_scroll) do
      %{
        cursor_line: 0,
        scroll_offset: 0,
        height: 6,
        width: 10,
        gutter_width: 0,
        cursor_col: cursor_col,
        h_scroll: h_scroll
      }
    end

    test "scrolls right when the cursor moves past the right edge" do
      state = Cursor.adjust_scroll(scroll_state(20, 0))
      assert state.h_scroll == 20 - 8 + 1
    end

    test "scrolls left when the cursor moves before the window" do
      state = Cursor.adjust_scroll(scroll_state(5, 13))
      assert state.h_scroll == 5
    end

    test "stays put when the cursor is already in view" do
      state = Cursor.adjust_scroll(scroll_state(4, 2))
      assert state.h_scroll == 2
    end
  end

  describe "cursor line is highlighted" do
    test "the focused cursor line keeps syntax colors and gets a cursor cell" do
      state =
        TextArea.mount(%{
          text: "def value, do: 42",
          language: :elixir,
          focused: true,
          width: 40,
          height: 4
        })

      style = %{fg: {200, 200, 200}, bg: {40, 40, 40}}
      [{_, segments} | _] = Render.render_content(state, 36, 2, style)

      colors = segments |> Enum.map(& &1.style[:fg]) |> Enum.uniq()
      assert length(colors) > 1

      assert Enum.any?(segments, &(&1.style.bg == {255, 255, 255}))
    end
  end

  describe "update/2 reclamps the cursor when text is swapped" do
    test "clamps cursor_col to the new shorter line length" do
      state = TextArea.mount(%{text: "select from some_long_table_name", width: 40, height: 6})
      state = %{state | cursor_col: 30}

      updated = TextArea.update(%{text: "select from bbo"}, state)

      assert updated.cursor_line == 0
      assert updated.cursor_col == String.length("select from bbo")
    end

    test "clamps cursor_line when the new text has fewer lines" do
      state = TextArea.mount(%{text: "a\nb\nc\nd\ne", width: 40, height: 6})
      state = %{state | cursor_line: 4, cursor_col: 1}

      updated = TextArea.update(%{text: "x\ny"}, state)

      assert updated.cursor_line == 1
      assert updated.cursor_col <= 1
    end

    test "clears a stale selection on text swap" do
      state = TextArea.mount(%{text: "hello world", width: 40, height: 6})
      state = %{state | selection: {0, 0, 0, 5}}

      assert TextArea.update(%{text: "hi"}, state).selection == nil
    end

    test "leaves the cursor untouched when text is unchanged" do
      state = TextArea.mount(%{text: "abc", width: 40, height: 6})
      state = %{state | cursor_col: 2}

      assert TextArea.update(%{focused: true}, state).cursor_col == 2
    end
  end

  describe "editing follows the horizontal scroll" do
    test "typing past the visible width advances h_scroll" do
      state = TextArea.mount(%{text: "", language: nil, focused: true, width: 12, height: 4})

      typed =
        Enum.reduce(1..30, state, fn _i, acc ->
          {:ok, next} = TextArea.Editing.handle_char_input(acc, "x")
          next
        end)

      assert typed.cursor_col == 30
      assert typed.h_scroll > 0
      assert typed.cursor_col >= typed.h_scroll
      assert typed.cursor_col < typed.h_scroll + (12 - 2)
    end
  end
end
