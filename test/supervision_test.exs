defmodule Drafter.SupervisionTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetServer
  alias Drafter.WidgetStripCache

  defmodule Faulty do
    @moduledoc false
    def mount(props), do: %{boom: Map.get(props, :boom, false)}
    def render(_state, _rect), do: [Strip.from_text("ok")]
    def handle_event(:explode, _state), do: raise("widget blew up")
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Steady do
    @moduledoc false
    def mount(_props), do: %{count: 0}
    def render(_state, _rect), do: [Strip.from_text("steady")]
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    WidgetStripCache.create()
    :ok
  end

  defp hierarchy_with_both do
    WidgetHierarchy.new()
    |> WidgetHierarchy.add_widget(:faulty, Faulty, %{}, nil, %{x: 0, y: 0, width: 4, height: 1})
    |> WidgetHierarchy.add_widget(:steady, Steady, %{}, nil, %{x: 0, y: 1, width: 4, height: 1})
  end

  describe "table ownership" do
    test "the shared tables are owned by the supervised owner, not a widget" do
      owner = Process.whereis(Drafter.TableOwner)
      assert is_pid(owner)

      for table <- [:drafter_widget_strips, :drafter_widget_pids, :drafter_app_registry] do
        assert :ets.info(:ets.whereis(table), :owner) == owner,
               "#{table} should be owned by Drafter.TableOwner"
      end
    end

    test "stopping a widget leaves the strip cache intact" do
      hierarchy = hierarchy_with_both()
      %{pid: pid} = hierarchy.widgets[:faulty]

      WidgetStripCache.put(:probe, %{x: 0, y: 0, width: 1, height: 1}, [])
      GenServer.stop(pid, :normal)

      assert :ets.whereis(:drafter_widget_strips) != :undefined
      assert WidgetStripCache.get(:probe) != nil
    end
  end

  describe "widget isolation" do
    test "a widget is not linked to the process that created it" do
      hierarchy = hierarchy_with_both()
      %{pid: pid} = hierarchy.widgets[:faulty]

      {:links, links} = Process.info(pid, :links)
      refute self() in links
    end

    test "a crashing widget does not take down its creator" do
      hierarchy = hierarchy_with_both()
      %{pid: pid} = hierarchy.widgets[:faulty]
      ref = Process.monitor(pid)

      catch_exit(WidgetServer.send_event_sync(pid, :explode))

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
      assert Process.alive?(self())
    end

    test "sibling widgets survive a crash" do
      hierarchy = hierarchy_with_both()
      %{pid: faulty} = hierarchy.widgets[:faulty]
      %{pid: steady} = hierarchy.widgets[:steady]

      catch_exit(WidgetServer.send_event_sync(faulty, :explode))
      Process.sleep(50)

      assert Process.alive?(steady)
      assert WidgetServer.get_state(steady) == %{count: 0}
    end

    test "reading a dead widget's state degrades instead of raising" do
      hierarchy = hierarchy_with_both()
      %{pid: pid} = hierarchy.widgets[:faulty]

      GenServer.stop(pid, :kill)
      Process.sleep(20)

      assert WidgetServer.safe_get_state(pid, 200) == nil
      assert WidgetHierarchy.get_widget_state(hierarchy, :faulty) != nil
    end
  end
end
