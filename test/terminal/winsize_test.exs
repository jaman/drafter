defmodule Drafter.Terminal.WinsizeTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.TermiosNif

  describe "set_winsize" do
    test "reports failure on a descriptor that is not a terminal" do
      assert {:error, :ioctl_failed} = TermiosNif.set_winsize(9999, 80, 24, 0, 0)
    end

    test "rejects non-integer arguments" do
      assert_raise ArgumentError, fn -> TermiosNif.set_winsize(:not_an_fd, 80, 24, 0, 0) end
      assert_raise ArgumentError, fn -> TermiosNif.set_winsize(1, :wide, 24, 0, 0) end
    end
  end
end
