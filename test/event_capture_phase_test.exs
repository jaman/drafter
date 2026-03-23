defmodule Drafter.EventCapturePhaseTest do
  use ExUnit.Case
  alias Drafter.{Event, WidgetHierarchy}

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  defmodule ParentWidget do
    use Drafter.Widget

    defstruct [:captured_events, :bubble_events]

    def mount(_props) do
      %__MODULE__{
        captured_events: [],
        bubble_events: []
      }
    end

    def render(_state, _rect), do: []

    def handle_event_capture(%Event.Object{type: :key, data: :x} = event, state) do
      new_state = %{state | captured_events: [event | state.captured_events]}
      {:stop, event, new_state, []}
    end

    def handle_event_capture(event, state) do
      new_state = %{state | captured_events: [event | state.captured_events]}
      {:continue, event, new_state}
    end

    def handle_event(event, state) do
      new_state = %{state | bubble_events: [event | state.bubble_events]}
      {:bubble, new_state}
    end
  end

  defmodule ChildWidget do
    use Drafter.Widget

    defstruct [:received_events]

    def mount(_props) do
      %__MODULE__{received_events: []}
    end

    def render(_state, _rect), do: []

    def handle_event(event, state) do
      new_state = %{state | received_events: [event | state.received_events]}
      {:ok, new_state}
    end
  end

  test "widgets can define handle_event_capture callback" do
    hierarchy = WidgetHierarchy.new()
    hierarchy = WidgetHierarchy.add_widget(hierarchy, :parent, ParentWidget, %{}, nil)

    widget_info = Map.get(hierarchy.widgets, :parent)
    assert function_exported?(widget_info.module, :handle_event_capture, 2)
  end

  test "handle_event_capture is optional" do
    hierarchy = WidgetHierarchy.new()
    hierarchy = WidgetHierarchy.add_widget(hierarchy, :child, ChildWidget, %{}, nil)

    widget_info = Map.get(hierarchy.widgets, :child)
    refute function_exported?(widget_info.module, :handle_event_capture, 2)
  end

  test "Event.Object conversion works" do
    tuple_event = {:key, :enter}
    event_object = Event.from_tuple(tuple_event)

    assert event_object.type == :key
    assert event_object.data == :enter
    assert event_object.phase == :bubble

    back_to_tuple = Event.to_tuple(event_object)
    assert back_to_tuple == tuple_event
  end

  test "Event.Object supports phase tracking" do
    event = Event.Object.new(:key, :a, phase: :capture, target: :my_widget)
    assert event.phase == :capture
    assert event.target == :my_widget
  end

  test "Event.Object supports propagation control" do
    event = Event.Object.new(:key, :a)
    assert event.propagation_stopped == false

    event = Event.stop_propagation(event)
    assert event.propagation_stopped == true
  end
end
