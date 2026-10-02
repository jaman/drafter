defmodule Drafter.Widget.TraitTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait

  describe "resolve_all/2" do
    test "auto-adds dependencies" do
      result = Trait.resolve_all([:selectable], [])

      assert Drafter.Widget.Trait.Focusable in result
      assert Drafter.Widget.Trait.Selectable in result
    end

    test "deduplicates traits" do
      result = Trait.resolve_all([:focusable, :selectable], [])
      focusable_count = Enum.count(result, &(&1 == Drafter.Widget.Trait.Focusable))
      assert focusable_count == 1
    end
  end

  describe "collect_handles/1" do
    test "collects handles from all traits" do
      modules = [Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Scrollable]
      handles = Trait.collect_handles(modules)

      assert :focus in handles
      assert :blur in handles
      assert :scroll in handles
      assert :keyboard in handles
    end

    test "deduplicates handles" do
      modules = [Drafter.Widget.Trait.Scrollable, Drafter.Widget.Trait.Selectable]
      handles = Trait.collect_handles(modules)
      keyboard_count = Enum.count(handles, &(&1 == :keyboard))
      assert keyboard_count == 1
    end
  end

  describe "merge_default_states/1" do
    test "merges state from multiple traits" do
      modules = [Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Scrollable]
      state = Trait.merge_default_states(modules)

      assert state.focused == false
      assert state._scroll_offset_y == 0
      assert state._viewport_height == 0
    end
  end

  describe "build_bitmap/1" do
    test "builds correct bitmap for multiple traits" do
      bitmap =
        Trait.build_bitmap([Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Scrollable])

      assert Trait.handles_event?(bitmap, :focus)
      assert Trait.handles_event?(bitmap, :scroll)
      assert Trait.handles_event?(bitmap, :keyboard)
    end
  end

  describe "collect_render_affecting_fields/1" do
    test "collects from multiple traits" do
      fields =
        Trait.collect_render_affecting_fields([
          Drafter.Widget.Trait.Focusable,
          Drafter.Widget.Trait.Scrollable
        ])

      assert :focused in fields
      assert :_scroll_offset_y in fields
    end
  end

  describe "all_layout_static?/1" do
    test "returns false when any trait is not static" do
      refute Trait.all_layout_static?([
               Drafter.Widget.Trait.Focusable,
               Drafter.Widget.Trait.Collapsible
             ])
    end
  end
end
