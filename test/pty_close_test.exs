defmodule Drafter.PtyCloseTest do
  use ExUnit.Case, async: false

  alias Drafter.Pty

  test "closing a handle again leaves the descriptors of a later pty alone" do
    {:ok, first} = Pty.spawn("/bin/sh", args: ["-c", "sleep 5"])
    Pty.close(first)
    {:ok, second} = Pty.spawn("/bin/cat")

    assert {second.master, second.slave} == {first.master, first.slave}

    Pty.close(first)

    assert Pty.resize(second, 100, 30) == :ok

    Pty.close(second)
  end
end
