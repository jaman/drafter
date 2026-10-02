defmodule Drafter.Terminal.PtyTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.TermiosNif

  test "rejects non-integer sizes" do
    assert_raise ArgumentError, fn -> TermiosNif.open_pty(:wide, 24) end
    assert_raise ArgumentError, fn -> TermiosNif.close_fd(:not_an_fd) end
  end
end
