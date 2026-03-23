defmodule Drafter.EventCaptureIntegrationTest do
  use ExUnit.Case
  alias Drafter.{Event, WidgetHierarchy}

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  defmodule ParentWidget do
    use Drafter.Widget

    defstruct [:capture_log, :bubble_log]

    def mount(_props) do
      %__MODULE__{
        capture_log: [],
        bubble_log: []
      }
    end

    def render(_state, _rect), do: []

    def handle_event_capture(%Event.Object{type: :key, data: :x} = event, state) do
      new_state = %{state | capture_log: [:captured_x | state.capture_log]}
      {:stop, event, new_state, []}
    end

    def handle_event_capture(%Event.Object{} = event, state) do
      new_state = %{state | capture_log: [:captured_other | state.capture_log]}
      {:continue, event, new_state}
    end

    def handle_event(_event, state) do
      new_state = %{state | bubble_log: [:bubbled | state.bubble_log]}
      {:ok, new_state}
    end
  end

  defmodule ChildWidget do
    use Drafter.Widget

    defstruct [:event_log]

    def mount(_props) do
      %__MODULE__{event_log: []}
    end

    def render(_state, _rect), do: []

    def handle_event({:key, _} = event, state) do
      new_state = %{state | event_log: [event | state.event_log]}
      {:ok, new_state}
    end

    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  test "capture phase intercepts events before target" do
    hierarchy = WidgetHierarchy.new()

    hierarchy =
      hierarchy
      |> WidgetHierarchy.add_widget(:parent, ParentWidget, %{}, nil)
      |> WidgetHierarchy.add_widget(:child, ChildWidget, %{}, :parent)
      |> WidgetHierarchy.focus_widget(:child)

    {new_hierarchy, _actions} = WidgetHierarchy.handle_event(hierarchy, {:key, :a})

    parent_state = WidgetHierarchy.get_widget_state(new_hierarchy, :parent)
    child_state = WidgetHierarchy.get_widget_state(new_hierarchy, :child)

    assert :captured_other in parent_state.capture_log
    assert length(child_state.event_log) == 1
  end

  test "capture phase can stop propagation" do
    hierarchy = WidgetHierarchy.new()

    hierarchy =
      hierarchy
      |> WidgetHierarchy.add_widget(:parent, ParentWidget, %{}, nil)
      |> WidgetHierarchy.add_widget(:child, ChildWidget, %{}, :parent)
      |> WidgetHierarchy.focus_widget(:child)

    {new_hierarchy, _actions} = WidgetHierarchy.handle_event(hierarchy, {:key, :x})

    parent_state = WidgetHierarchy.get_widget_state(new_hierarchy, :parent)
    child_state = WidgetHierarchy.get_widget_state(new_hierarchy, :child)

    assert :captured_x in parent_state.capture_log
    assert child_state.event_log == []
  end

  test "events without capture handlers work normally" do
    hierarchy = WidgetHierarchy.new()

    hierarchy =
      hierarchy
      |> WidgetHierarchy.add_widget(:child, ChildWidget, %{}, nil)
      |> WidgetHierarchy.focus_widget(:child)

    {new_hierarchy, _actions} = WidgetHierarchy.handle_event(hierarchy, {:key, :enter})

    child_state = WidgetHierarchy.get_widget_state(new_hierarchy, :child)
    assert length(child_state.event_log) == 1
  end
end
