defmodule Drafter.Regression.RestoreRuntimeBackendsTest do
  use ExUnit.Case, async: true

  alias Drafter.Runtime

  defmodule CallbackApp do
    use Drafter.App

    def mount(_props), do: %{n: 0}
    def render(_state), do: []
    def handle_event(:inc, _data, state), do: {:ok, %{state | n: state.n + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule FlatReducerApp do
    use Drafter, runtime: :reducer

    state(%{n: 0})

    def render(_state), do: []
    def update(:inc, state), do: %{state | n: state.n + 1}
    def update(_msg, state), do: state
  end

  defmodule FlatCallbackApp do
    use Drafter

    state(%{n: 7})

    def render(_state), do: []
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "default backend is Callback and routing preserves callback behavior" do
    assert Runtime.for_app(CallbackApp) == Runtime.Callback
    assert Runtime.for_app(CallbackApp).mount(CallbackApp, %{}) == %{n: 0}

    assert Runtime.for_app(CallbackApp).handle_message(CallbackApp, :inc, nil, %{n: 0}) ==
             {:ok, %{n: 1}}
  end

  test "flat DSL state/1 defines mount" do
    assert FlatCallbackApp.mount(%{}) == %{n: 7}
    assert Runtime.for_app(FlatCallbackApp) == Runtime.Callback
  end

  test "reducer app: flat DSL + runtime selection + update reduction" do
    assert FlatReducerApp.__runtime__() == :reducer
    assert Runtime.for_app(FlatReducerApp) == Runtime.Reducer
    assert Runtime.for_app(FlatReducerApp).mount(FlatReducerApp, %{}) == %{n: 0}

    assert Runtime.for_app(FlatReducerApp).handle_input(FlatReducerApp, :inc, %{n: 0}) ==
             {:ok, %{n: 1}}

    assert Runtime.for_app(FlatReducerApp).handle_input(FlatReducerApp, :noop, %{n: 5}) ==
             {:noreply, %{n: 5}}
  end

  test "a callback-style app declared with runtime: :reducer falls back to callback" do
    refute function_exported?(CallbackApp, :update, 2)
    assert Runtime.Reducer.handle_message(CallbackApp, :inc, nil, %{n: 0}) == {:ok, %{n: 1}}
  end
end
