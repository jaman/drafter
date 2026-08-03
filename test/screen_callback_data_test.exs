defmodule Drafter.ScreenCallbackDataTest do
  @moduledoc """
  A screen callback's payload survives dispatch.

  A widget's `{:app_callback, name, data}` carries the thing the user chose or typed,
  and the `data` reaches the screen alongside the name. A `nil` payload arrives as a
  `nil` argument, distinguishable from a callback that carried nothing.

  `handle_event/3` is a declared callback, so a screen can discover and annotate it,
  and dispatch always calls it. A screen defining only `handle_event/2` is reached
  through a generated bridge rather than through a lossy arity fallback, which keeps
  dispatch to one shape on both the screen and app paths.
  """

  use ExUnit.Case, async: true

  defmodule TakesData do
    @moduledoc false
    use Drafter.Screen

    @impl true
    def mount(_props), do: %{got: :none}

    @impl true
    def render(state), do: vertical([label(inspect(state.got))])

    @impl true
    def handle_event(:chosen, data, state), do: {:ok, %{state | got: data}}
    def handle_event(_event, _data, state), do: {:noreply, state}
  end

  defmodule TakesNoData do
    @moduledoc false
    use Drafter.Screen

    @impl true
    def mount(_props), do: %{fired: false}

    @impl true
    def render(state), do: vertical([label(inspect(state.fired))])

    @impl true
    def handle_event(:chosen, state), do: {:ok, %{state | fired: true}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  describe "a screen that defines handle_event/3" do
    test "receives the payload" do
      assert {:ok, %{got: "the value"}} =
               TakesData.handle_event(:chosen, "the value", TakesData.mount(%{}))
    end

    test "receives a nil payload as nil rather than as no argument" do
      assert {:ok, %{got: nil}} = TakesData.handle_event(:chosen, nil, TakesData.mount(%{}))
    end
  end

  describe "a screen that defines only handle_event/2" do
    test "still gets the callback, through the generated bridge" do
      assert {:ok, %{fired: true}} =
               TakesNoData.handle_event(:chosen, "ignored", TakesNoData.mount(%{}))
    end

    test "the bridge exists so dispatch has one shape and never picks a lossy path" do
      assert function_exported?(TakesNoData, :handle_event, 3)
      assert function_exported?(TakesData, :handle_event, 3)
    end
  end

  describe "handle_event/3 is a declared callback" do
    test "so a screen can discover it and annotate it" do
      assert {:handle_event, 3} in Drafter.Screen.behaviour_info(:callbacks)
      assert {:handle_event, 3} in Drafter.Screen.behaviour_info(:optional_callbacks)
    end
  end
end
