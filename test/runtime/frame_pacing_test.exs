defmodule Drafter.Runtime.FramePacingTest do
  @moduledoc """
  A headless run paces frames the same way a real terminal run does.

  `throttled_render/4` branches on the `:frame_interval_ms` process key: unset means
  render every event, set means throttle and defer. A headless run enters the loop
  with that key set, so it takes the paced branch and exercises the throttling,
  deferral and coalescing a real run depends on.

  The interval defaults to 30fps, honours an app's own `refresh_rate`, and is
  published where widgets can read it and pace against it.
  """

  use ExUnit.Case, async: false

  alias Drafter.Runtime.FrameClock

  defmodule Paced do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count=#{state.count}")])
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Slow do
    @moduledoc false
    use Drafter.App

    def refresh_rate, do: "10fps"

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count=#{state.count}")])
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp frame_interval(ctx) do
    {:dictionary, dict} = Process.info(ctx.app_pid, :dictionary)
    Keyword.get(dict, :frame_interval_ms)
  end

  test "the loop process has a frame interval, so renders take the paced branch" do
    ctx = Drafter.Test.start_headless(Paced, %{}, width: 20, height: 4)

    assert is_integer(frame_interval(ctx)),
           "the loop never armed frame pacing, so this test exercises a branch production does not"

    Drafter.Test.stop(ctx)
  end

  test "the default is 30fps" do
    ctx = Drafter.Test.start_headless(Paced, %{}, width: 20, height: 4)

    assert frame_interval(ctx) == FrameClock.interval_for("30fps")

    Drafter.Test.stop(ctx)
  end

  test "an app's own refresh_rate is honoured" do
    ctx = Drafter.Test.start_headless(Slow, %{}, width: 20, height: 4)

    assert frame_interval(ctx) == FrameClock.interval_for("10fps")
    assert frame_interval(ctx) > FrameClock.interval_for("30fps")

    Drafter.Test.stop(ctx)
  end

  test "the interval is published so widgets can pace against it" do
    ctx = Drafter.Test.start_headless(Slow, %{}, width: 20, height: 4)

    assert Drafter.AppRegistry.get_frame_interval() == FrameClock.interval_for("10fps")

    Drafter.Test.stop(ctx)
  end
end
