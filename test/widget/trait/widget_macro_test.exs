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

  describe "multi-trait widget capabilities" do
    test "combines handles from all traits" do
      caps = MultiTraitWidget.__widget_capabilities__()
      assert :focus in caps.handles
      assert :scroll in caps.handles
      assert :keyboard in caps.handles
    end
  end

  describe "trait-based focus handling" do
    test "handles focus event" do
      state = TraitWidget.mount(%{label: "test"})
      {:ok, new_state} = TraitWidget.handle_event({:focus}, state)
      assert new_state.focused == true
    end
  end

  describe "backward compatibility" do
    test "handles-based key routing works" do
      state = %HandleWidget{focused: true}
      {:ok, _} = HandleWidget.handle_event({:key, :enter}, state)
    end
  end
end
