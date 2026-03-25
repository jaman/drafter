defmodule Drafter.Widget.Trait.WidgetMacroTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait

  defmodule TraitWidget do
    use Drafter.Widget, traits: [:focusable]

    defstruct [:label, :focused]

    def mount(props) do
      %__MODULE__{label: Map.get(props, :label, ""), focused: false}
    end

    def render(_state, _rect), do: []
  end

  defmodule MultiTraitWidget do
    use Drafter.Widget, traits: [:focusable, :scrollable]

    defstruct [
      :items,
      :focused,
      :_scroll_offset_y,
      :_scroll_offset_x,
      :_content_height,
      :_content_width,
      :_viewport_height,
      :_viewport_width,
      :_show_scrollbar
    ]

    def mount(props) do
      defaults = Trait.merge_default_states(__widget_traits__())

      struct(__MODULE__, Map.merge(defaults, %{items: Map.get(props, :items, [])}))
    end

    def render(_state, _rect), do: []
  end

  defmodule HandleWidget do
    use Drafter.Widget, handles: [:keyboard], focusable: true

    defstruct [:focused]

    def mount(_props), do: %__MODULE__{focused: false}
    def render(_state, _rect), do: []

    def handle_key(:enter, state), do: {:ok, state}
    def handle_key(_key, state), do: {:bubble, state}
  end

  describe "trait-based widget capabilities" do
    test "reports focusable when focusable trait is used" do
      caps = TraitWidget.__widget_capabilities__()
      assert caps.focusable == true
    end

    test "includes trait handles in capabilities" do
      caps = TraitWidget.__widget_capabilities__()
      assert :focus in caps.handles
      assert :blur in caps.handles
    end

    test "reports trait names" do
      caps = TraitWidget.__widget_capabilities__()
      assert :focusable in caps.traits
    end

    test "exposes trait modules" do
      traits = TraitWidget.__widget_traits__()
      assert Drafter.Widget.Trait.Focusable in traits
    end

    test "exposes capabilities bitmap" do
      bitmap = TraitWidget.__widget_capabilities_bitmap__()
      assert is_integer(bitmap)
      assert Trait.handles_event?(bitmap, :focus)
    end

    test "exposes render affecting fields" do
      fields = TraitWidget.__render_affecting_fields__()
      assert :focused in fields
    end

    test "exposes layout static flag" do
      assert TraitWidget.__layout_static__()
    end

    test "exposes trait default state" do
      defaults = TraitWidget.__trait_default_state__()
      assert defaults.focused == false
    end
  end

  describe "multi-trait widget capabilities" do
    test "combines handles from all traits" do
      caps = MultiTraitWidget.__widget_capabilities__()
      assert :focus in caps.handles
      assert :scroll in caps.handles
      assert :keyboard in caps.handles
    end

    test "includes all trait names" do
      caps = MultiTraitWidget.__widget_capabilities__()
      assert :focusable in caps.traits
      assert :scrollable in caps.traits
    end

    test "has scroll config" do
      caps = MultiTraitWidget.__widget_capabilities__()
      assert caps.scroll != nil
      assert caps.scroll.direction == :vertical
    end
  end

  describe "trait-based focus handling" do
    test "handles focus event" do
      state = TraitWidget.mount(%{label: "test"})
      {:ok, new_state} = TraitWidget.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "handles blur event" do
      state = %TraitWidget{label: "test", focused: true}
      {:ok, new_state} = TraitWidget.handle_event({:blur}, state)
      assert new_state.focused == false
    end
  end

  describe "backward compatibility" do
    test "handles-based widget still works" do
      caps = HandleWidget.__widget_capabilities__()
      assert caps.focusable == true
      assert :keyboard in caps.handles
    end

    test "handles-based widget does not expose traits" do
      refute function_exported?(HandleWidget, :__widget_traits__, 0)
    end

    test "handles-based focus works" do
      state = HandleWidget.mount(%{})
      {:ok, new_state} = HandleWidget.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "handles-based key routing works" do
      state = %HandleWidget{focused: true}
      {:ok, _} = HandleWidget.handle_event({:key, :enter}, state)
    end
  end
end
