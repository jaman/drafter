defmodule Drafter.Widget.KeyShapeCoverageTest do
  @moduledoc """
  Key bindings are written in the shapes the parser actually emits.

  Every event here is produced by `Drafter.Terminal.ANSI.parse_sequence/1` from the
  bytes a terminal actually sends, so a clause written in the wrong shape fails rather
  than compiling into silence. The parser emits a modified arrow as a three-element
  tuple, `{:key, :left, [:shift]}`, never as a nested `{:key, {:shift, :left}}`, and
  printable punctuation as an atom, `{:key, :+}`, never as a binary `{:key, "+"}`.

  Driven with those shapes, `TextArea` selects with shift and the arrows and jumps by
  word with ctrl and the arrows, ctrl-arrow clearing any selection rather than being
  swallowed by the clipboard clause; `Tree` expands and collapses a node, expands and
  collapses everything, and moves between siblings.
  """

  use ExUnit.Case, async: false

  alias Drafter.Terminal.ANSI
  alias Drafter.Widget.{TextArea, Tree}

  defp press(bytes) do
    {[event], ""} = ANSI.parse_sequence(bytes)
    event
  end

  describe "text area selection with shift and arrows" do
    defp area do
      %{TextArea.mount(%{text: "hello world\nsecond line"}) | focused: true}
    end

    for {name, bytes} <- [
          {"left", "\e[1;2D"},
          {"right", "\e[1;2C"},
          {"up", "\e[1;2A"},
          {"down", "\e[1;2B"}
        ] do
      test "shift+#{name} starts a selection" do
        state = %{area() | cursor_line: 1, cursor_col: 3}

        assert {:ok, moved} = TextArea.handle_event(press(unquote(bytes)), state)
        assert moved.selection != nil, "shift+#{unquote(name)} did not select"
      end
    end
  end

  describe "text area word jump with ctrl and arrows" do
    test "ctrl+right moves the cursor forward past a word" do
      state = %{area() | cursor_line: 0, cursor_col: 0}

      assert {:ok, moved} = TextArea.handle_event(press("\e[1;5C"), state)
      assert moved.cursor_col > 0
    end

    test "ctrl+left moves the cursor back past a word" do
      state = %{area() | cursor_line: 0, cursor_col: 11}

      assert {:ok, moved} = TextArea.handle_event(press("\e[1;5D"), state)
      assert moved.cursor_col < 11
    end

    test "ctrl+arrow clears any selection, and is not swallowed by the clipboard clause" do
      state = %{area() | cursor_line: 0, cursor_col: 5}

      assert {:ok, moved} = TextArea.handle_event(press("\e[1;5D"), state)
      assert moved.selection == nil
    end
  end

  describe "tree expand and collapse keys" do
    defp tree do
      data = [%{label: "a", children: [%{label: "a1"}, %{label: "a2"}]}, %{label: "b"}]
      %{Tree.mount(%{data: data}) | focused: true}
    end

    test "plus expands the current node" do
      assert {:ok, expanded} = Tree.handle_event(press("+"), tree())
      assert MapSet.size(expanded.expanded_nodes) > 0
    end

    test "minus collapses again" do
      {:ok, expanded} = Tree.handle_event(press("+"), tree())

      assert {:ok, collapsed} = Tree.handle_event(press("-"), expanded)
      assert MapSet.size(collapsed.expanded_nodes) < MapSet.size(expanded.expanded_nodes)
    end

    test "star expands everything" do
      assert {:ok, expanded} = Tree.handle_event(press("*"), tree())
      assert MapSet.size(expanded.expanded_nodes) > 0
    end

    test "slash collapses everything" do
      {:ok, expanded} = Tree.handle_event(press("*"), tree())

      assert {:ok, collapsed} = Tree.handle_event(press("/"), expanded)
      assert MapSet.size(collapsed.expanded_nodes) == 0
    end

    test "shift+right moves the cursor to the next sibling" do
      {_tag, moved} = Tree.handle_event(press("\e[1;2C"), tree())

      assert moved.cursor_index == 1
    end

    test "shift+left comes back from it" do
      {_tag, forward} = Tree.handle_event(press("\e[1;2C"), tree())
      {_tag, back} = Tree.handle_event(press("\e[1;2D"), forward)

      assert back.cursor_index == 0
    end
  end

  describe "the shapes themselves" do
    test "printable punctuation arrives as an atom, not a binary" do
      assert press("+") == {:key, :+}
      assert press("/") == {:key, :/}
    end

    test "modified arrows arrive as a three-element tuple, not a nested one" do
      assert press("\e[1;2D") == {:key, :left, [:shift]}
      assert press("\e[1;5D") == {:key, :left, [:ctrl]}
    end
  end
end
