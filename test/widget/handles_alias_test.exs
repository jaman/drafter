defmodule Drafter.Widget.HandlesAliasTest do
  @moduledoc """
  A widget declaring `handles: [:click]` receives mouse presses.

  `guides/writing_widgets.md` teaches `:click` alongside `handle_press/3` and five
  in-tree widgets declare it, while the router dispatches on `:press`. `:click` is
  therefore an alias resolved once, at declaration, by `normalize_handles/1`, so both
  spellings receive the press and a widget declaring neither receives nothing.
  `normalize_handles/1` leaves names it does not know alone and dedupes the result.
  """

  use ExUnit.Case, async: true

  alias Drafter.Widget
  alias Drafter.Widget.EventRouter

  defmodule ClicksByAlias do
    @moduledoc false
    use Drafter.Widget, handles: [:click], focusable: true

    defstruct presses: 0

    def component_tag, do: :clicks_by_alias
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_press(_x, _y, state), do: {:ok, %{state | presses: state.presses + 1}}
  end

  defmodule ClicksByPress do
    @moduledoc false
    use Drafter.Widget, handles: [:press], focusable: true

    defstruct presses: 0

    def component_tag, do: :clicks_by_press
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_press(_x, _y, state), do: {:ok, %{state | presses: state.presses + 1}}
  end

  defmodule NoMouse do
    @moduledoc false
    use Drafter.Widget, handles: [:keyboard], focusable: true

    defstruct presses: 0

    def component_tag, do: :no_mouse
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_press(_x, _y, state), do: {:ok, %{state | presses: state.presses + 1}}
  end

  defp press(module) do
    EventRouter.route_event(
      module,
      {:mouse, %{type: :mouse_down, x: 1, y: 1}},
      module.mount(%{}),
      module.__widget_capabilities__().handles,
      true
    )
  end

  test "a widget declaring :click receives the press" do
    assert {:ok, %{presses: 1}} = press(ClicksByAlias)
  end

  test "a widget declaring :press still receives it" do
    assert {:ok, %{presses: 1}} = press(ClicksByPress)
  end

  test "a widget declaring neither does not" do
    assert {:bubble, %{presses: 0}} = press(NoMouse)
  end

  test "the alias is resolved once, at declaration" do
    assert ClicksByAlias.__widget_capabilities__().handles == [:press]
  end

  test "normalize_handles/1 leaves unknown names alone and dedupes" do
    assert Widget.normalize_handles([:click, :press]) == [:press]
    assert Widget.normalize_handles([:keyboard, :scroll]) == [:keyboard, :scroll]
  end
end
