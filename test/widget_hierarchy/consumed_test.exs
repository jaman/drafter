defmodule Drafter.WidgetHierarchy.ConsumedTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetHierarchy

  defmodule Handler do
    @moduledoc false
    def mount(props),
      do: %{count: 0, focusable: true, focused: false, bulk: Map.get(props, :bulk, [])}

    def render(_state, _rect), do: [Strip.from_text("h")]
    def handle_event({:key, :x}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event({:key, :y}, state), do: {:ok, state}
    def handle_event({:key, :z}, state), do: {:ok, state, [{:app_callback, :zapped, nil}]}
    def handle_event({:key, :bubble_me}, state), do: {:bubble, state}
    def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
    def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp hierarchy_with(props \\ %{}) do
    Drafter.WidgetStripCache.create()

    WidgetHierarchy.new()
    |> WidgetHierarchy.add_widget(:h1, Handler, props, nil, %{x: 0, y: 0, width: 4, height: 1})
    |> Map.put(:focused_widget, :h1)
  end

  test "an event that changes widget state is reported consumed" do
    {_h, _actions, consumed} =
      WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :x})

    assert consumed
  end

  test "an event a widget ignores is not reported consumed" do
    {_h, _actions, consumed} =
      WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :q})

    refute consumed
  end

  test "a handled event that leaves state identical is still reported consumed" do
    {_h, _actions, consumed} =
      WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :y})

    assert consumed
  end

  test "an event a widget explicitly bubbles is not reported consumed" do
    {_h, _actions, consumed} =
      WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :bubble_me})

    refute consumed
  end

  test "an event producing actions is reported consumed" do
    {_h, actions, consumed} =
      WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :z})

    assert actions == [{:app_callback, :zapped, nil}]
    assert consumed
  end

  test "consumption is independent of how much state each widget carries" do
    small = hierarchy_with(%{bulk: []})
    large = hierarchy_with(%{bulk: Enum.to_list(1..50_000)})

    assert {_, _, true} = WidgetHierarchy.handle_event_consumed(small, {:key, :x})
    assert {_, _, true} = WidgetHierarchy.handle_event_consumed(large, {:key, :x})
    assert {_, _, false} = WidgetHierarchy.handle_event_consumed(large, {:key, :q})
  end

  test "dispatch returns a verdict only, never the widget's state" do
    Drafter.WidgetStripCache.create()
    hierarchy = hierarchy_with(%{bulk: Enum.to_list(1..1_000)})
    %{pid: pid} = hierarchy.widgets[:h1]

    assert {:stop, []} = Drafter.WidgetServer.dispatch_event(pid, {:key, :x})
    assert {:not_handled, []} = Drafter.WidgetServer.dispatch_event(pid, {:key, :q})
    assert {:bubble, []} = Drafter.WidgetServer.dispatch_event(pid, {:key, :bubble_me})

    assert {:stop, [{:app_callback, :zapped, nil}]} =
             Drafter.WidgetServer.dispatch_event(pid, {:key, :z})
  end

  test "the consumed flag does not leak into the returned hierarchy" do
    {h, _actions, true} = WidgetHierarchy.handle_event_consumed(hierarchy_with(), {:key, :x})
    {_h2, _actions2, consumed} = WidgetHierarchy.handle_event_consumed(h, {:key, :q})
    refute consumed
  end
end
