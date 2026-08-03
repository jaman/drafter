defmodule Drafter.Terminal.WinsizeTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.TermiosNif

  describe "get_winsize" do
    test "reports a result rather than raising, tty or not" do
      case TermiosNif.get_winsize() do
        {:ok, {cols, rows, xpixel, ypixel}} ->
          assert is_integer(cols) and cols >= 0
          assert is_integer(rows) and rows >= 0
          assert is_integer(xpixel) and xpixel >= 0
          assert is_integer(ypixel) and ypixel >= 0

        {:error, reason} ->
          assert is_atom(reason)
      end
    end

    test "is repeatable" do
      assert TermiosNif.get_winsize() == TermiosNif.get_winsize()
    end
  end

  describe "set_winsize" do
    test "reports failure on a descriptor that is not a terminal" do
      assert {:error, :ioctl_failed} = TermiosNif.set_winsize(9999, 80, 24, 0, 0)
    end

    test "rejects non-integer arguments" do
      assert_raise ArgumentError, fn -> TermiosNif.set_winsize(:not_an_fd, 80, 24, 0, 0) end
      assert_raise ArgumentError, fn -> TermiosNif.set_winsize(1, :wide, 24, 0, 0) end
    end
  end

  describe "signal watcher" do
    alias Drafter.Terminal.SignalWatcher

    test "forwards a window-change signal to the driver" do
      {:ok, state} = SignalWatcher.init(self())
      assert {:ok, ^state} = SignalWatcher.handle_event(:sigwinch, state)
      assert_receive {:signal, :winch}
    end

    test "ignores signals it does not own" do
      {:ok, state} = SignalWatcher.init(self())
      assert {:ok, ^state} = SignalWatcher.handle_event(:sigterm, state)
      refute_receive {:signal, _}, 50
    end
  end
end
