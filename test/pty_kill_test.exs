defmodule Drafter.PtyKillTest do
  @moduledoc """
  Shutting down a program that will not take the hint.

  Closing the descriptors sends `SIGHUP`, which a program is free to ignore.
  `close/2` can follow it with `SIGKILL` after a grace period, aimed at the
  process group so the children the program started go with it.
  """

  use ExUnit.Case, async: true

  alias Drafter.Pty
  alias Drafter.Terminal.TermiosNif

  # trap SIGHUP, then sit forever
  @stubborn "trap '' HUP; while :; do sleep 0.05; done"

  defp group_alive?(pid), do: TermiosNif.killpg(pid, 0) == :ok

  defp await_group_gone(pid, tries \\ 60)
  defp await_group_gone(_pid, 0), do: false

  defp await_group_gone(pid, tries) do
    if group_alive?(pid) do
      Process.sleep(50)
      await_group_gone(pid, tries - 1)
    else
      true
    end
  end

  defp stubborn_pty do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", @stubborn])
    {:ok, os_pid} = Pty.os_pid(pty)

    # let the shell install the trap before anything is sent
    Process.sleep(150)
    assert group_alive?(os_pid)

    {pty, os_pid}
  end

  test "a program ignoring SIGHUP survives a plain close" do
    {pty, os_pid} = stubborn_pty()

    Pty.close(pty)
    Process.sleep(300)

    assert group_alive?(os_pid), "the stub should have survived, or the test proves nothing"

    TermiosNif.killpg(os_pid, 9)
  end

  test "kill_after finishes it off" do
    {pty, os_pid} = stubborn_pty()

    Pty.close(pty, kill_after: 100)

    assert await_group_gone(os_pid), "the process group outlived kill_after"
  end

  test "the whole process group goes, not just the leader" do
    {:ok, pty} =
      Pty.spawn("/bin/sh", args: ["-c", "trap '' HUP; sleep 300 & while :; do sleep 0.05; done"])

    {:ok, os_pid} = Pty.os_pid(pty)
    Process.sleep(200)

    Pty.close(pty, kill_after: 100)

    assert await_group_gone(os_pid), "a child started by the program was left behind"
  end

  test "a program that exits on its own needs no killing" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "exit 0"])
    {:ok, os_pid} = Pty.os_pid(pty)

    assert_receive {_port, {:exit_status, 0}}, 3000

    Pty.close(pty, kill_after: 50)
    Process.sleep(200)

    refute group_alive?(os_pid)
  end

  test "close/1 still means no escalation" do
    {pty, os_pid} = stubborn_pty()

    Pty.close(pty)
    Process.sleep(300)

    assert group_alive?(os_pid)

    TermiosNif.killpg(os_pid, 9)
  end

  describe "killpg/2" do
    test "reports an absent group rather than raising" do
      assert {:error, message} = TermiosNif.killpg(999_999, 0)
      assert message =~ "No such process"
    end

    test "refuses a pid that would signal the caller's own group" do
      assert_raise ArgumentError, fn -> TermiosNif.killpg(0, 9) end
      assert_raise ArgumentError, fn -> TermiosNif.killpg(-1, 9) end
    end
  end
end
