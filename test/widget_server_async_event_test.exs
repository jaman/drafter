defmodule Drafter.WidgetServerAsyncEventTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetServer

  defmodule Counting do
    @behaviour Drafter.Widget

    @impl true
    def mount(props), do: %{count: Map.get(props, :count, 0)}

    @impl true
    def render(state, _rect), do: [Strip.from_text("#{state.count}")]

    @impl true
    def update(props, state), do: Map.merge(state, props)

    @impl true
    def handle_event({:write, _line}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp start_widget do
    Drafter.WidgetStripCache.create()
    id = :"counting_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      WidgetServer.start_link(
        id: id,
        module: Counting,
        props: %{},
        rect: %{x: 0, y: 0, width: 10, height: 1}
      )

    {pid, id}
  end

  defp count(pid), do: WidgetServer.get_state(pid).count

  defp flush_renders do
    receive do
      {:widget_render_needed, _} -> flush_renders()
    after
      0 -> :ok
    end
  end

  describe "asynchronous events" do
    test "a single cast is applied" do
      {pid, _id} = start_widget()

      WidgetServer.send_event(pid, {:write, "one"})

      assert count(pid) == 1
    end

    test "a burst of casts is applied in full, not throttled away" do
      {pid, _id} = start_widget()

      for line <- 1..500, do: WidgetServer.send_event(pid, {:write, line})

      assert count(pid) == 500
    end

    test "casts sent faster than the frame interval still all land" do
      {pid, _id} = start_widget()

      for line <- 1..50 do
        WidgetServer.send_event(pid, {:write, line})
        WidgetServer.get_state(pid)
      end

      assert count(pid) == 50
    end

    test "state advances identically whether sent async or sync" do
      {async, _} = start_widget()
      {sync, _} = start_widget()

      for line <- 1..100 do
        WidgetServer.send_event(async, {:write, line})
        WidgetServer.send_event_sync(sync, {:write, line})
      end

      assert count(async) == count(sync)
    end

    test "a throttled burst is followed by a catch-up render" do
      Drafter.AppRegistry.register()
      on_exit(&Drafter.AppRegistry.unregister/0)

      {pid, id} = start_widget()

      for line <- 1..200, do: WidgetServer.send_event(pid, {:write, line})
      assert count(pid) == 200
      flush_renders()

      assert_receive {:widget_render_needed, ^id}, 500
    end

    test "an event a widget ignores leaves its state alone" do
      {pid, _id} = start_widget()

      WidgetServer.send_event(pid, {:unhandled, :thing})

      assert count(pid) == 0
    end
  end
end
