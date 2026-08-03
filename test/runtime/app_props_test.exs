defmodule Drafter.Runtime.AppPropsTest do
  @moduledoc """
  Props given to a run reach the app's `mount/1`.

  The props arrive as the map they were given, not nested under a `:props` key and
  not mixed with the run's other options; a run with no props mounts with `%{}`. A
  timer armed in `on_ready/1` fires against the same mounted state.

  These assertions drive `Drafter.Runtime.AppLoop.start/3`, the function a real
  terminal run enters once the terminal is set up, so a call site that drops props
  on the way to `mount/1` fails here.
  """

  use ExUnit.Case, async: false

  defmodule PropApp do
    @moduledoc false
    use Drafter.App

    def mount(props), do: %{seen: props, ticks: 0}

    def render(state),
      do: vertical([label("cwd=#{inspect(state.seen[:cwd])} ticks=#{state.ticks}")])

    def on_ready(state) do
      Drafter.set_interval(20, :tick)
      state
    end

    def on_timer(:tick, state), do: %{state | ticks: state.ticks + 1}

    def handle_event(_event, state), do: {:noreply, state}
  end

  test "mount receives the props the run was given" do
    ctx = Drafter.Test.start_headless(PropApp, %{cwd: "/some/dir", history_file: "/h"})

    assert Drafter.Test.get_state(ctx).seen == %{cwd: "/some/dir", history_file: "/h"}

    Drafter.Test.stop(ctx)
  end

  test "props are not nested under a :props key" do
    ctx = Drafter.Test.start_headless(PropApp, %{cwd: "/some/dir"})

    seen = Drafter.Test.get_state(ctx).seen
    refute Map.has_key?(seen, :props)
    assert seen.cwd == "/some/dir"

    Drafter.Test.stop(ctx)
  end

  test "no props means an empty map, not the run's options" do
    ctx = Drafter.Test.start_headless(PropApp)

    assert Drafter.Test.get_state(ctx).seen == %{}

    Drafter.Test.stop(ctx)
  end

  test "a timer started in on_ready is armed" do
    ctx = Drafter.Test.start_headless(PropApp, %{cwd: "/some/dir"})

    ticked =
      Drafter.Test.wait_for(ctx, fn c -> Drafter.Test.get_state(c).ticks > 0 end, timeout: 1000)

    assert ticked == :ok,
           "on_ready registered an interval that never fired, so startup timers are being dropped"

    Drafter.Test.stop(ctx)
  end
end
