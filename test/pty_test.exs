defmodule Drafter.PtyTest do
  use ExUnit.Case, async: true

  alias Drafter.Pty

  defp collect(pty, acc \\ [], timeout \\ 3000) do
    io = pty.io
    control = pty.control

    receive do
      {^io, {:data, bytes}} -> collect(pty, [acc, bytes], timeout)
      {^control, {:exit_status, status}} -> {IO.iodata_to_binary(acc), status}
    after
      timeout -> {IO.iodata_to_binary(acc), :timeout}
    end
  end

  defp await(pty, pattern, acc \\ [], timeout \\ 3000) do
    io = pty.io

    receive do
      {^io, {:data, bytes}} ->
        text = IO.iodata_to_binary([acc, bytes])
        if text =~ pattern, do: text, else: await(pty, pattern, text, timeout)
    after
      timeout -> flunk("never saw #{inspect(pattern)}; got #{inspect(IO.iodata_to_binary(acc))}")
    end
  end

  test "runs a program and reports its output and exit status" do
    {:ok, pty} = Pty.spawn("/bin/echo", args: ["hello from the pty"])

    assert {output, 0} = collect(pty)
    assert output =~ "hello from the pty"

    Pty.close(pty)
  end

  test "reports a non-zero exit status" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "exit 3"])

    assert {_output, 3} = collect(pty)

    Pty.close(pty)
  end

  test "reports a status when the program cannot be executed" do
    {:ok, pty} = Pty.spawn("/nonexistent/program")

    assert {output, status} = collect(pty)
    assert status != 0
    assert output =~ "pty_spawn"

    Pty.close(pty)
  end

  test "the program sees a terminal on its standard output" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "test -t 1 && echo IS_A_TTY"])

    assert {output, 0} = collect(pty)
    assert output =~ "IS_A_TTY"

    Pty.close(pty)
  end

  test "the program has a controlling terminal" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "test -r /dev/tty && echo HAS_CTTY"])

    assert {output, 0} = collect(pty)
    assert output =~ "HAS_CTTY"

    Pty.close(pty)
  end

  test "the initial size is visible to the program" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "stty size"], cols: 100, rows: 40)

    assert {output, 0} = collect(pty)
    assert output =~ "40 100"

    Pty.close(pty)
  end

  test "writes reach the program's standard input" do
    {:ok, pty} = Pty.spawn("/bin/cat")

    Pty.write(pty, "round trip\n")
    assert await(pty, "round trip")

    Pty.close(pty)
  end

  test "resize/3 changes the size the program reports" do
    {:ok, pty} =
      Pty.spawn("/bin/sh",
        args: ["-c", "echo READY; read line; stty size"],
        cols: 80,
        rows: 24
      )

    await(pty, "READY")
    :ok = Pty.resize(pty, 120, 50)
    Pty.write(pty, "\n")

    assert await(pty, "50 120")

    Pty.close(pty)
  end

  test "TERM is set for the program" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "echo TERM=$TERM"], term: "xterm-256color")

    assert {output, 0} = collect(pty)
    assert output =~ "TERM=xterm-256color"

    Pty.close(pty)
  end

  test "cd runs the program in the given directory" do
    {:ok, pty} = Pty.spawn("/bin/pwd", cd: "/tmp")

    assert {output, 0} = collect(pty)
    assert output =~ "tmp"

    Pty.close(pty)
  end

  test "os_pid/1 returns the running program's pid" do
    {:ok, pty} = Pty.spawn("/bin/sleep", args: ["2"])

    assert {:ok, pid} = Pty.os_pid(pty)
    assert is_integer(pid) and pid > 0

    Pty.close(pty)
  end

  test "the program runs in its own session, not the emulator's" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "echo SID=$$"])

    assert {output, 0} = collect(pty)
    assert output =~ "SID="

    Pty.close(pty)
  end

  test "close/1 is safe to call twice" do
    {:ok, pty} = Pty.spawn("/bin/sh", args: ["-c", "echo UP; sleep 5"])

    await(pty, "UP")

    assert :ok = Pty.close(pty)
    assert :ok = Pty.close(pty)
  end
end
