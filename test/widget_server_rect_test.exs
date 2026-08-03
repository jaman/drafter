defmodule Drafter.WidgetServerRectTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetServer
  alias Drafter.WidgetStripCache

  defmodule Probe do
    @moduledoc false

    def mount(props), do: %{label: Map.get(props, :label, "x"), rect_changes: 0}

    def render(state, rect) do
      send_count(state, rect)
      [Strip.from_text(state.label)]
    end

    def handle_event(_event, state), do: {:noreply, state}

    def on_rect_change(_rect, state), do: %{state | rect_changes: state.rect_changes + 1}

    defp send_count(_state, _rect) do
      case :persistent_term.get({__MODULE__, :counter}, nil) do
        nil -> :ok
        ref -> :counters.add(ref, 1, 1)
      end
    end
  end

  setup do
    WidgetStripCache.create()
    counter = :counters.new(1, [])
    :persistent_term.put({Probe, :counter}, counter)
    on_exit(fn -> :persistent_term.erase({Probe, :counter}) end)
    {:ok, counter: counter}
  end

  defp renders(counter), do: :counters.get(counter, 1)

  defp start_probe(rect) do
    {:ok, pid} =
      WidgetServer.start_link(
        id: :"probe_#{System.unique_integer([:positive])}",
        module: Probe,
        props: %{},
        rect: rect
      )

    pid
  end

  test "each rect update re-renders the widget, which is how live content refreshes",
       %{counter: counter} do
    rect = %{x: 0, y: 0, width: 10, height: 1}
    pid = start_probe(rect)
    before = renders(counter)

    WidgetServer.update_rect(pid, rect)
    WidgetServer.update_rect(pid, rect)
    WidgetServer.update_rect(pid, rect)

    assert renders(counter) == before + 3
  end

  test "a changed rect re-renders the widget", %{counter: counter} do
    pid = start_probe(%{x: 0, y: 0, width: 10, height: 1})
    before = renders(counter)

    WidgetServer.update_rect(pid, %{x: 0, y: 0, width: 20, height: 1})

    assert renders(counter) > before
  end

  test "rect-derived state is applied once at mount" do
    pid = start_probe(%{x: 0, y: 0, width: 10, height: 1})
    assert WidgetServer.get_state(pid).rect_changes == 1
  end

  test "an unchanged rect does not re-invoke on_rect_change" do
    rect = %{x: 0, y: 0, width: 10, height: 1}
    pid = start_probe(rect)
    at_mount = WidgetServer.get_state(pid).rect_changes

    WidgetServer.update_rect(pid, rect)
    WidgetServer.update_rect(pid, rect)

    assert WidgetServer.get_state(pid).rect_changes == at_mount
  end

  test "a changed rect invokes on_rect_change once" do
    pid = start_probe(%{x: 0, y: 0, width: 10, height: 1})
    at_mount = WidgetServer.get_state(pid).rect_changes

    WidgetServer.update_rect(pid, %{x: 0, y: 0, width: 11, height: 1})
    WidgetServer.update_rect(pid, %{x: 0, y: 0, width: 11, height: 1})

    assert WidgetServer.get_state(pid).rect_changes == at_mount + 1
  end

  test "a rect update notifies the loop so the frame picks up the new strips" do
    rect = %{x: 0, y: 0, width: 10, height: 1}
    pid = start_probe(rect)

    Drafter.AppRegistry.ensure_table()
    Drafter.AppRegistry.register()

    WidgetServer.update_rect(pid, rect)

    assert_receive {:widget_render_needed, _}, 500
  after
    Drafter.AppRegistry.unregister()
  end
end
