defmodule Drafter.Widget.TraitTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait

  describe "resolve_module/1" do
    test "resolves built-in trait atoms to modules" do
      assert Trait.resolve_module(:focusable) == Drafter.Widget.Trait.Focusable
      assert Trait.resolve_module(:scrollable) == Drafter.Widget.Trait.Scrollable
      assert Trait.resolve_module(:selectable) == Drafter.Widget.Trait.Selectable
      assert Trait.resolve_module(:editable) == Drafter.Widget.Trait.Editable
      assert Trait.resolve_module(:resizable) == Drafter.Widget.Trait.Resizable
      assert Trait.resolve_module(:draggable) == Drafter.Widget.Trait.Draggable
      assert Trait.resolve_module(:animatable) == Drafter.Widget.Trait.Animatable
      assert Trait.resolve_module(:collapsible) == Drafter.Widget.Trait.Collapsible
    end

    test "passes through full module names unchanged" do
      assert Trait.resolve_module(MyCustomTrait) == MyCustomTrait
    end
  end

  describe "resolve_all/2" do
    test "resolves simple trait list" do
      result = Trait.resolve_all([:focusable], [])
      assert result == [Drafter.Widget.Trait.Focusable]
    end

    test "resolves multiple traits" do
      result = Trait.resolve_all([:focusable, :scrollable], [])

      assert Drafter.Widget.Trait.Focusable in result
      assert Drafter.Widget.Trait.Scrollable in result
    end

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

  describe "any_focusable?/1" do
    test "returns true when focusable trait is present" do
      assert Trait.any_focusable?([Drafter.Widget.Trait.Focusable])
    end

    test "returns false when no focusable trait" do
      refute Trait.any_focusable?([Drafter.Widget.Trait.Animatable])
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

    test "later traits override earlier ones for shared keys" do
      modules = [Drafter.Widget.Trait.Focusable]
      state = Trait.merge_default_states(modules)
      assert state == %{focused: false}
    end
  end

  describe "build_bitmap/1" do
    test "builds correct bitmap for focusable" do
      bitmap = Trait.build_bitmap([Drafter.Widget.Trait.Focusable])
      assert Trait.handles_event?(bitmap, :focus)
      assert Trait.handles_event?(bitmap, :blur)
      refute Trait.handles_event?(bitmap, :scroll)
    end

    test "builds correct bitmap for multiple traits" do
      bitmap = Trait.build_bitmap([Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Scrollable])
      assert Trait.handles_event?(bitmap, :focus)
      assert Trait.handles_event?(bitmap, :scroll)
      assert Trait.handles_event?(bitmap, :keyboard)
    end
  end

  describe "collect_render_affecting_fields/1" do
    test "collects from single trait" do
      fields = Trait.collect_render_affecting_fields([Drafter.Widget.Trait.Focusable])
      assert :focused in fields
    end

    test "collects from multiple traits" do
      fields = Trait.collect_render_affecting_fields([
        Drafter.Widget.Trait.Focusable,
        Drafter.Widget.Trait.Scrollable
      ])

      assert :focused in fields
      assert :_scroll_offset_y in fields
    end
  end

  describe "all_layout_static?/1" do
    test "returns true for all static traits" do
      assert Trait.all_layout_static?([Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Selectable])
    end

    test "returns false when any trait is not static" do
      refute Trait.all_layout_static?([Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Collapsible])
    end
  end

  describe "scroll_config/2" do
    test "returns config when scrollable is present" do
      modules = [Drafter.Widget.Trait.Scrollable]
      config = Trait.scroll_config(modules, [])

      assert config.direction == :vertical
      assert config.step == 1
    end

    test "returns nil when scrollable is not present" do
      modules = [Drafter.Widget.Trait.Focusable]
      assert Trait.scroll_config(modules, []) == nil
    end

    test "respects custom scroll options" do
      modules = [Drafter.Widget.Trait.Scrollable]
      config = Trait.scroll_config(modules, scroll: [direction: :both, step: 3])

      assert config.direction == :both
      assert config.step == 3
    end
  end
end
