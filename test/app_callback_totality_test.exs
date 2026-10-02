defmodule Drafter.AppCallbackTotalityTest do
  use ExUnit.Case, async: true

  defmodule OnlyKeybinding do
    @moduledoc false
    use Drafter.App

    keybinding {:q, [:ctrl]}, "quit" do
      {:stop, :normal}
    end

    def render(_state), do: []
  end

  defmodule OnlySpecificEvents do
    @moduledoc false
    use Drafter.App

    def render(_state), do: []
    def handle_event(:save, state), do: {:ok, Map.put(state, :saved, true)}
    def on_timer(:tick, state), do: Map.put(state, :ticked, true)
  end

  defmodule NoHandlersAtAll do
    @moduledoc false
    use Drafter.App
    def render(_state), do: []
  end

  describe "an app that only declares a keybinding" do
    test "still answers its keybinding" do
      assert OnlyKeybinding.handle_event({:key, :q, [:ctrl]}, %{}) == {:stop, :normal}
    end
  end

  describe "an app that handles some events" do
    test "still answers the events it declared" do
      assert {:ok, %{saved: true}} = OnlySpecificEvents.handle_event(:save, %{})
    end

    test "still answers the timer it declared" do
      assert %{ticked: true} = OnlySpecificEvents.on_timer(:tick, %{})
    end

    test "ignores other timers instead of crashing" do
      assert %{} == OnlySpecificEvents.on_timer(:other, %{})
    end
  end

  describe "an app that declares no handlers" do
    test "ignores events and timers" do
      assert {:noreply, %{}} = NoHandlersAtAll.handle_event({:key, :z}, %{})
      assert %{} == NoHandlersAtAll.on_timer(:tick, %{})
    end
  end
end
