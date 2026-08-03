defmodule Drafter.WidgetHierarchy.BubblePhaseTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetHierarchy

  defmodule Recorder do
    @moduledoc false
    def mount(props), do: %{name: Map.get(props, :name), mode: Map.get(props, :mode, :bubble)}
    def render(_state, _rect), do: [Strip.from_text("r")]

    def handle_event({:key, :probe}, %{mode: :bubble} = state) do
      send_seen(state)
      {:bubble, state}
    end

    def handle_event({:key, :probe}, %{mode: :stop} = state) do
      send_seen(state)
      {:ok, state, [{:app_callback, state.name, nil}]}
    end

    def handle_event({:key, :probe}, %{mode: :ignore} = state) do
      send_seen(state)
      {:noreply, state}
    end

    def handle_event({:key, :emit}, state) do
      {:bubble, state, [{:app_callback, state.name, nil}]}
    end

    def handle_event(_event, state), do: {:noreply, state}

    defp send_seen(state) do
      case :persistent_term.get({__MODULE__, :owner}, nil) do
        nil -> :ok
        owner -> send(owner, {:seen, state.name})
      end
    end
  end

  setup do
    Drafter.WidgetStripCache.create()
    :persistent_term.put({Recorder, :owner}, self())
    on_exit(fn -> :persistent_term.erase({Recorder, :owner}) end)
    :ok
  end

  defp chain(modes) do
    rect = %{x: 0, y: 0, width: 4, height: 1}

    {hierarchy, _} =
      Enum.reduce(modes, {WidgetHierarchy.new(), nil}, fn {id, mode}, {h, parent} ->
        h = WidgetHierarchy.add_widget(h, id, Recorder, %{name: id, mode: mode}, parent, rect)
        {h, id}
      end)

    %{hierarchy | focused_widget: modes |> List.last() |> elem(0)}
  end

  defp seen(acc \\ []) do
    receive do
      {:seen, name} -> seen([name | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  test "an unhandled event reaches every ancestor, innermost first" do
    hierarchy = chain([{:root, :bubble}, {:mid, :bubble}, {:leaf, :bubble}])
    WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :probe})

    assert seen() == [:leaf, :mid, :root]
  end

  test "an ancestor that handles the event ends the walk" do
    hierarchy = chain([{:root, :bubble}, {:mid, :stop}, {:leaf, :bubble}])
    {_h, actions, consumed} = WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :probe})

    assert seen() == [:leaf, :mid]
    assert actions == [{:app_callback, :mid, nil}]
    assert consumed
  end

  test "a widget that ignores the event still lets it continue upward" do
    hierarchy = chain([{:root, :bubble}, {:mid, :ignore}, {:leaf, :bubble}])
    WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :probe})

    assert seen() == [:leaf, :mid, :root]
  end

  test "actions accumulate in the order the widgets produced them" do
    hierarchy = chain([{:root, :bubble}, {:mid, :bubble}, {:leaf, :bubble}])
    {_h, actions, _} = WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :emit})

    assert actions == [
             {:app_callback, :leaf, nil},
             {:app_callback, :mid, nil},
             {:app_callback, :root, nil}
           ]
  end

  test "a deep chain does not lose or reorder actions" do
    modes = for i <- 1..25, do: {:"w#{i}", :bubble}
    hierarchy = chain(modes)
    {_h, actions, _} = WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :emit})

    expected = modes |> Enum.reverse() |> Enum.map(fn {id, _} -> {:app_callback, id, nil} end)
    assert actions == expected
  end

  test "an event with no ancestors is still delivered to its target" do
    hierarchy = chain([{:only, :bubble}])
    WidgetHierarchy.handle_event_consumed(hierarchy, {:key, :probe})

    assert seen() == [:only]
  end
end
