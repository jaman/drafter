defmodule Drafter.Widget.PasteRoutingTest do
  @moduledoc """
  Pasted text reaches widgets that asked for it, sanitized, and no others.
  """

  use ExUnit.Case, async: true

  alias Drafter.Widget.EventRouter

  defmodule Accepts do
    @moduledoc false
    use Drafter.Widget, handles: [:keyboard, :paste], focusable: true

    defstruct value: ""

    def component_tag, do: :accepts_paste
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_paste(text, state), do: {:ok, %{state | value: state.value <> text}}

    @impl true
    def handle_key(_key, state), do: {:bubble, state}
  end

  defmodule Declines do
    @moduledoc false
    use Drafter.Widget, handles: [:keyboard], focusable: true

    defstruct value: ""

    def component_tag, do: :declines_paste
    def from_component_opts(_args, _opts), do: %{}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(_state, _rect), do: []

    @impl true
    def handle_key(_key, state), do: {:bubble, state}
  end

  defp route(module, handles, text) do
    EventRouter.route_event(module, {:bracketed_paste, text}, module.mount(%{}), handles, true)
  end

  test "a widget that declares :paste receives the text" do
    assert {:ok, %{value: "hello"}} = route(Accepts, [:keyboard, :paste], "hello")
  end

  test "a widget that does not declare :paste bubbles instead" do
    assert {:bubble, %{value: ""}} = route(Declines, [:keyboard], "hello")
  end

  test "the text is sanitized before the widget sees it" do
    assert {:ok, %{value: value}} = route(Accepts, [:keyboard, :paste], "safe\e[31m red")

    refute value =~ "\e"
    assert value == "safe[31m red"
  end

  test "newlines survive so a multi-line paste stays multi-line" do
    assert {:ok, %{value: "one\ntwo"}} = route(Accepts, [:keyboard, :paste], "one\r\ntwo")
  end

  test "handle_paste/2 is a declared callback" do
    assert {:handle_paste, 2} in Drafter.Widget.behaviour_info(:callbacks)
    assert {:handle_paste, 2} in Drafter.Widget.behaviour_info(:optional_callbacks)
  end
end
