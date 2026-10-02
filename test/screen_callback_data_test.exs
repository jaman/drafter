defmodule Drafter.ScreenCallbackDataTest do
  @moduledoc """
  A screen that defines only `handle_event/2` is reached through the generated
  `handle_event/3` bridge, so dispatch keeps to one shape and never picks a lossy
  arity fallback.
  """

  use ExUnit.Case, async: true

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

  describe "a screen that defines only handle_event/2" do
    test "still gets the callback, through the generated bridge" do
      assert {:ok, %{fired: true}} =
               TakesNoData.handle_event(:chosen, "ignored", TakesNoData.mount(%{}))
    end
  end
end
