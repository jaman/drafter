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

  @unhandled [
    {:mouse, %{type: :move, x: 3, y: 4, modifiers: []}},
    {:mouse, %{type: :mouse_down, x: 1, y: 1, modifiers: []}},
    {:key, :z},
    {:key, :a, [:alt]},
    {:char, 233},
    {:bracketed_paste, "text"},
    :some_bare_atom
  ]

  describe "an app that only declares a keybinding" do
    test "still answers its keybinding" do
      assert OnlyKeybinding.handle_event({:key, :q, [:ctrl]}, %{}) == {:stop, :normal}
    end

    test "ignores every other event instead of crashing" do
      for event <- @unhandled do
        assert {:noreply, %{}} = OnlyKeybinding.handle_event(event, %{})
      end
    end
  end

  describe "an app that handles some events" do
    test "still answers the events it declared" do
      assert {:ok, %{saved: true}} = OnlySpecificEvents.handle_event(:save, %{})
    end

    test "ignores every other event instead of crashing" do
      for event <- @unhandled do
        assert {:noreply, %{}} = OnlySpecificEvents.handle_event(event, %{})
      end
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
