defmodule Drafter.Runtime.FrameClockTest do
  use ExUnit.Case, async: true

  alias Drafter.Runtime.FrameClock

  doctest Drafter.Runtime.FrameClock

  describe "interval_for" do
    test "frames per second convert to milliseconds" do
      assert FrameClock.interval_for("30fps") == 33
      assert FrameClock.interval_for("60fps") == 17
      assert FrameClock.interval_for("7.5fps") == 133
      assert FrameClock.interval_for("120 fps") == 8
    end

    test "unlimited means no pacing" do
      assert FrameClock.interval_for(:unlimited) == nil
      assert FrameClock.interval_for("unlimited") == nil
    end

    test "a millisecond interval passes through" do
      assert FrameClock.interval_for(50) == 50
    end

    test "an unparseable rate is rejected loudly" do
      assert_raise ArgumentError, fn -> FrameClock.interval_for("fast") end
      assert_raise ArgumentError, fn -> FrameClock.interval_for("30hz") end
    end
  end
end
