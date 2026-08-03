defmodule Drafter.Runtime.AppLoopRegistrationTest do
  @moduledoc """
  How a loop is registered, and how callers resolve one.

  Covers registration on entering the loop, resolution with and without a session
  identity, and what `send_to_loop/1,2` reports when no loop resolves.
  """

  use ExUnit.Case, async: false

  alias Drafter.AppRegistry
  alias Drafter.Runtime.AppLoop

  defmodule Quiet do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{value: 0}
    def render(state), do: vertical([label("value #{state.value}")])
    def handle_event(_event, _data, state), do: {:noreply, state}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    on_exit(&AppRegistry.unregister/0)
    :ok
  end

  describe "enter_loop" do
    test "a loop entered through enter_loop is discoverable" do
      test_process = self()

      loop =
        spawn(fn ->
          AppLoop.enter_loop(Quiet, %{value: 0}, %{x: 0, y: 0, width: 20, height: 3})
          send(test_process, :never)
        end)

      Process.sleep(150)

      assert AppRegistry.whereis() == loop,
             "a loop entered through enter_loop/6 is not reachable through the registry"

      Process.exit(loop, :kill)
    end
  end

  describe "what an unregistered loop breaks" do
    test "sending to a loop that is not there reports the failure" do
      AppRegistry.unregister()

      assert AppRegistry.whereis() == nil
      assert AppRegistry.send_to_loop({:widget_render_needed, :w}) == {:error, :no_loop}
    end

    test "a registered loop actually receives what is sent to it" do
      AppRegistry.register()

      assert AppRegistry.send_to_loop({:widget_render_needed, :some_widget}) == :ok
      assert_receive {:widget_render_needed, :some_widget}, 500
    end
  end

  describe "resolution without a session identity" do
    setup do
      :persistent_term.erase({AppRegistry, :ambiguity_warned})
      on_exit(fn -> Enum.each(spare_loops(), &stop_loop/1) end)
      :ok
    end

    test "one loop answers, because there is nothing to disambiguate" do
      only = spawn_loop(:only_session)

      assert AppRegistry.whereis() == only

      stop_loop(only)
    end

    test "a second loop makes the question unanswerable rather than wrong" do
      first = spawn_loop(:first_session)
      second = spawn_loop(:second_session)

      assert AppRegistry.whereis() == nil,
             "an unkeyed lookup guessed between two loops instead of declining"

      Enum.each([first, second], &stop_loop/1)
    end

    test "a keyed caller still resolves its own loop with several running" do
      first = spawn_loop(:first_session)
      second = spawn_loop(:second_session)

      assert AppRegistry.whereis(:first_session) == first
      assert AppRegistry.whereis(:second_session) == second

      Enum.each([first, second], &stop_loop/1)
    end

    test "sending without a session identity reports the drop" do
      first = spawn_loop(:first_session)
      second = spawn_loop(:second_session)

      assert AppRegistry.send_to_loop({:app_event, :ping, nil}) == {:error, :no_loop}
      assert AppRegistry.send_to_loop(:first_session, {:app_event, :ping, nil}) == :ok

      Enum.each([first, second], &stop_loop/1)
    end

    test "the ambiguity is reported once, not on every lookup" do
      first = spawn_loop(:first_session)
      second = spawn_loop(:second_session)

      refute warned?()
      AppRegistry.whereis()
      assert warned?(), "an ambiguous lookup passed without reporting itself"

      AppRegistry.whereis()
      assert warned?()

      Enum.each([first, second], &stop_loop/1)
    end
  end

  defp spawn_loop(session) do
    test_process = self()

    pid =
      spawn(fn ->
        Process.put(:drafter_compositor, session)
        AppRegistry.register()
        send(test_process, :registered)

        receive do
          :stop -> :ok
        end
      end)

    receive do
      :registered -> pid
    after
      1000 -> flunk("second loop never registered")
    end
  end

  defp stop_loop(pid) do
    if Process.alive?(pid) do
      send(pid, :stop)
      Process.sleep(20)
    end
  end

  defp warned?, do: :persistent_term.get({AppRegistry, :ambiguity_warned}, false)

  defp spare_loops do
    :drafter_app_registry
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{:loop, _}, pid} when is_pid(pid) -> if pid == self(), do: [], else: [pid]
      _ -> []
    end)
  rescue
    ArgumentError -> []
  end
end
