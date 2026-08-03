defmodule Drafter.Widget.EventRouterModifierTest do
  @moduledoc """
  A widget is never told a modified key was an unmodified one.

  `handle_key/2` takes no modifier list, so routing `ctrl+c` to it can only deliver
  a bare `:c` — indistinguishable from the user pressing `c`. A terminal widget then
  types the letter into the program instead of raising `SIGINT`, and nothing can be
  interrupted. Bubbling instead lets whatever does understand the modifier see it.
  """

  use ExUnit.Case, async: true

  alias Drafter.Widget.EventRouter

  defmodule TwoArity do
    @moduledoc false
    use Drafter.Widget, handles: [:keyboard], focusable: true

    defstruct seen: []

    def component_tag, do: :two_arity
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_key(key, state), do: {:ok, %{state | seen: [key | state.seen]}}
  end

  defmodule ThreeArity do
    @moduledoc false
    use Drafter.Widget, handles: [:keyboard], focusable: true

    defstruct seen: []

    def component_tag, do: :three_arity
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_key(key, mods, state), do: {:ok, %{state | seen: [{key, mods} | state.seen]}}

    @impl true
    def handle_key(key, state), do: {:ok, %{state | seen: [key | state.seen]}}
  end

  defp route(module, event) do
    EventRouter.route_event(module, event, module.mount(%{}), [:keyboard], true)
  end

  describe "a widget offering only handle_key/2" do
    test "still handles a key with no modifiers" do
      assert {:ok, %{seen: [?c]}} = route(TwoArity, {:key, ?c})
      assert {:ok, %{seen: [?c]}} = route(TwoArity, {:key, ?c, []})
    end

    for {key, name} <- [{?c, "ctrl+c"}, {?d, "ctrl+d"}, {?z, "ctrl+z"}] do
      test "bubbles #{name} rather than delivering it as a bare letter" do
        assert {:bubble, %{seen: []}} = route(TwoArity, {:key, unquote(key), [:ctrl]})
      end
    end

    test "bubbles a modified arrow rather than delivering a plain arrow" do
      assert {:bubble, %{seen: []}} = route(TwoArity, {:key, :left, [:alt]})
      assert {:bubble, %{seen: []}} = route(TwoArity, {:key, :left, [:shift]})
      assert {:bubble, %{seen: []}} = route(TwoArity, {:key, :left, [:ctrl, :shift]})
    end
  end

  describe "a widget offering handle_key/3" do
    test "receives the modifiers" do
      assert {:ok, %{seen: [{?c, [:ctrl]}]}} = route(ThreeArity, {:key, ?c, [:ctrl]})
      assert {:ok, %{seen: [{:left, [:alt]}]}} = route(ThreeArity, {:key, :left, [:alt]})
    end

    test "receives an empty modifier list for an unmodified key event" do
      assert {:ok, %{seen: [{?c, []}]}} = route(ThreeArity, {:key, ?c, []})
    end

    test "falls to handle_key/2 for a key event that carries no modifier list at all" do
      assert {:ok, %{seen: [?c]}} = route(ThreeArity, {:key, ?c})
    end
  end

  describe "handle_key/3 is a declared callback" do
    test "so an out-of-tree widget can discover it and annotate it" do
      assert {:handle_key, 3} in Drafter.Widget.behaviour_info(:callbacks)
      assert {:handle_key, 3} in Drafter.Widget.behaviour_info(:optional_callbacks)
    end
  end
end
