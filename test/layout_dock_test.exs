defmodule Drafter.LayoutDockTest do
  use ExUnit.Case, async: true

  alias Drafter.Layout

  defp input(opts), do: {:text_input, opts}

  describe "dock_edge" do
    test "a footer is docked to the bottom without saying so" do
      assert Layout.dock_edge({:footer, []}) == :bottom
    end

    test "any component may declare an edge" do
      assert Layout.dock_edge(input(dock: :top)) == :top
      assert Layout.dock_edge(input(dock: :left)) == :left
      assert Layout.dock_edge(input(dock: :right)) == :right
      assert Layout.dock_edge(input(dock: :bottom)) == :bottom
    end

    test "an undocked component reports no edge" do
      assert Layout.dock_edge(input([])) == nil
    end

    test "a meaningless edge is ignored rather than honoured" do
      assert Layout.dock_edge(input(dock: :sideways)) == nil
    end
  end

  describe "partition_docked" do
    test "separates docked components from the flow, keeping order" do
      children = [input(dock: :top), input([]), {:footer, []}, input([])]
      {docked, flowing} = Layout.partition_docked(children)

      assert Enum.map(docked, &elem(&1, 1)) == [:top, :bottom]
      assert length(flowing) == 2
    end

    test "no docked components leaves the flow untouched" do
      children = [input([]), input([])]
      assert {[], ^children} = Layout.partition_docked(children)
    end
  end

  describe "visibility" do
    test "a hidden component is still laid out" do
      assert Layout.component_visible?(input(visibility: :hidden))
    end

    test "a hidden component is reported as not painting" do
      assert Layout.component_hidden?(input(visibility: :hidden))
      refute Layout.component_hidden?(input([]))
    end

    test "an invisible component is removed from layout entirely" do
      refute Layout.component_visible?(input(visible: false))
      refute Layout.component_hidden?(input(visible: false))
    end
  end
end
