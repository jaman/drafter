defmodule Drafter.Regression.Stage3AppRegistryTest do
  use ExUnit.Case, async: false

  alias Drafter.AppRegistry

  setup do
    on_exit(fn ->
      Process.put(:drafter_compositor, :sess_a)
      AppRegistry.unregister()
      Process.put(:drafter_compositor, :sess_b)
      AppRegistry.unregister()
      Process.delete(:drafter_compositor)
    end)
  end

  test "concurrent sessions resolve their own loop instead of colliding on one global key" do
    test_pid = self()

    spawn_session = fn session ->
      pid =
        spawn(fn ->
          Process.put(:drafter_compositor, session)
          AppRegistry.register()
          send(test_pid, {:ready, session, self()})
          receive do: (:stop -> :ok)
        end)

      assert_receive {:ready, ^session, ^pid}
      pid
    end

    loop_a = spawn_session.(:sess_a)
    loop_b = spawn_session.(:sess_b)

    Process.put(:drafter_compositor, :sess_a)
    assert AppRegistry.whereis() == loop_a

    Process.put(:drafter_compositor, :sess_b)
    assert AppRegistry.whereis() == loop_b

    send(loop_a, :stop)
    send(loop_b, :stop)
  end
end
