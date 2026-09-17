defmodule Drafter.Test.HeadlessDriverSyncTest do
  use ExUnit.Case, async: false

  alias Drafter.Event.Manager
  alias Drafter.Test.HeadlessDriver

  setup do
    {:ok, manager} = Manager.start_link(name: nil)
    driver = start_supervised!({HeadlessDriver, event_manager: manager, test_pid: self()})
    :ok = Manager.subscribe_to(manager, self())
    {:ok, manager: manager, driver: driver}
  end

  test "sync/0 returns once every injected event has been handed to the event manager",
       %{manager: manager} do
    :sys.suspend(manager)

    for n <- 1..20, do: HeadlessDriver.inject_event({:key, :"k#{n}"})
    assert :ok == HeadlessDriver.sync()

    {:messages, queued} = Process.info(manager, :messages)
    assert length(queued) == 20

    :sys.resume(manager)
    :ok = Manager.sync(manager)

    for n <- 1..20 do
      key = :"k#{n}"
      assert_received {:tui_event, {:key, ^key}}
    end
  end
end
