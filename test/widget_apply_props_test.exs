defmodule Drafter.WidgetApplyPropsTest do
  @moduledoc """
  A widget answers re-render props the same way in or out of a process.

  `WidgetHierarchy` and `WidgetServer` agree on the same rule, so where a prop lands
  does not depend on whether the widget happens to run in its own process. A widget
  defining `update/2` gets whatever that returns. A widget defining none keeps its
  state as it stands: the fallback neither guesses at the merge nor invents keys on a
  struct, and interaction state the widget owns survives a re-render.
  """

  use ExUnit.Case, async: true

  alias Drafter.Widget

  defmodule DefinesUpdate do
    @moduledoc false
    defstruct label: "a", scroll: 0
    def mount(props), do: %__MODULE__{label: Map.get(props, :label, "a")}
    def update(props, state), do: %{state | label: Map.get(props, :label, state.label)}
  end

  defmodule NoUpdate do
    @moduledoc false
    defstruct label: "a", scroll: 0
    def mount(props), do: %__MODULE__{label: Map.get(props, :label, "a")}
  end

  test "a widget with update/2 gets its own answer" do
    state = %DefinesUpdate{label: "a", scroll: 7}

    assert Widget.apply_props(DefinesUpdate, %{label: "b"}, state) == %DefinesUpdate{
             label: "b",
             scroll: 7
           }
  end

  test "a widget without update/2 keeps its state rather than being guessed at" do
    state = %NoUpdate{label: "a", scroll: 7}

    assert Widget.apply_props(NoUpdate, %{label: "b"}, state) == state
  end
end
