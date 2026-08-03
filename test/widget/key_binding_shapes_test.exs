defmodule Drafter.Widget.KeyBindingShapesTest do
  @moduledoc """
  Bindings a widget declares must match the events the parser and router emit.

  The parser emits printable keys as an atom of the character itself, so space
  arrives as `:" "`. Modifiers arrive as a third element, `{:key, :left, [:alt]}`.
  A clause written in any other shape compiles, never matches, and the binding is
  silently absent.
  """

  use ExUnit.Case, async: true

  alias Drafter.Terminal.ANSI
  alias Drafter.Widget.{DataTable, DirectoryTree, EventRouter, SplitPaneDivider, Switch, Tree}

  describe "what the parser emits" do
    test "space is the character atom, not :space" do
      assert {[{:key, :" "}], ""} = ANSI.parse_sequence(" ")
    end

    test "enter is a named atom" do
      assert {[{:key, :enter}], ""} = ANSI.parse_sequence("\r")
    end

    test "a modified arrow is a three-element tuple" do
      assert {[{:key, :left, [:alt]}], ""} = ANSI.parse_sequence("\e[1;3D")
    end
  end

  describe "space activates" do
    test "a tree with selection enabled toggles it on space" do
      state = %{Tree.mount(%{data: [%{label: "a"}], selection_mode: :single}) | focused: true}

      assert {:ok, _} = Tree.handle_event({:key, :" "}, state)
    end

    test "a tree with selection off ignores space" do
      state = %{Tree.mount(%{data: [%{label: "a"}], selection_mode: :none}) | focused: true}

      assert {:noreply, _} = Tree.handle_event({:key, :" "}, state)
    end

    test "a directory tree responds to space" do
      state = DirectoryTree.mount(%{path: "."})

      assert {:ok, _} = DirectoryTree.handle_key(:" ", state)
    end

    test "a data table toggles selection on space" do
      state = DataTable.mount(%{columns: [%{key: :a, label: "A"}], rows: [%{a: 1}]})

      assert {:ok, _} = DataTable.handle_key(:" ", state)
    end
  end

  describe "hover" do
    test "a switch hovers on the event the router sends" do
      state = Switch.mount(%{})

      assert {:ok, %{hovered: true}} = Switch.handle_event(:hover, state)
      assert {:ok, %{hovered: false}} = Switch.handle_event(:unhover, %{state | hovered: true})
    end
  end

  describe "split pane divider" do
    defp divider(orientation) do
      SplitPaneDivider.mount(%{ratio: 0.5, total_size: 100, orientation: orientation})
    end

    defp position(state), do: SplitPaneDivider.effective_pos(state)

    defp send_key(state, event) do
      EventRouter.route_event(
        SplitPaneDivider,
        event,
        state,
        [:keyboard, :press, :mouse_up, :drag],
        true
      )
    end

    test "alt and arrow move a horizontal divider" do
      state = divider(:horizontal)
      start = position(state)

      assert {:ok, left} = send_key(state, {:key, :left, [:alt]})
      assert position(left) < start

      assert {:ok, right} = send_key(state, {:key, :right, [:alt]})
      assert position(right) > start
    end

    test "shift and arrow move it too" do
      state = divider(:horizontal)
      start = position(state)

      assert {:ok, moved} = send_key(state, {:key, :left, [:shift]})
      assert position(moved) < start
    end

    test "a vertical divider responds to up and down" do
      state = divider(:vertical)
      start = position(state)

      assert {:ok, up} = send_key(state, {:key, :up, [:alt]})
      assert position(up) < start

      assert {:ok, down} = send_key(state, {:key, :down, [:alt]})
      assert position(down) > start
    end

    test "an arrow with no modifier bubbles rather than resizing" do
      state = divider(:horizontal)

      assert {:bubble, _} = send_key(state, {:key, :left, []})
    end

    test "an axis the divider does not move along bubbles" do
      state = divider(:horizontal)

      assert {:bubble, _} = send_key(state, {:key, :up, [:alt]})
    end
  end
end
