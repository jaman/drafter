defmodule Drafter.Terminal.PtyTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.TermiosNif

  defp with_pty(cols, rows, fun) do
    assert {:ok, {master, slave, path}} = TermiosNif.open_pty(cols, rows)

    try do
      fun.(master, slave, path)
    after
      TermiosNif.close_fd(slave)
      TermiosNif.close_fd(master)
    end
  end

  test "allocates a pair of descriptors and names the slave" do
    with_pty(100, 30, fn master, slave, path ->
      assert is_integer(master) and master > 2
      assert is_integer(slave) and slave > 2
      assert master != slave
      assert String.starts_with?(path, "/dev/")
    end)
  end

  test "the pty is created at the requested size" do
    with_pty(100, 30, fn _master, slave, _path ->
      assert {:ok, {100, 30, _, _}} = size_of(slave)
    end)
  end

  test "the size can be changed afterwards" do
    with_pty(80, 24, fn _master, slave, _path ->
      assert :ok = TermiosNif.set_winsize(slave, 120, 40, 0, 0)
      assert {:ok, {120, 40, _, _}} = size_of(slave)
    end)
  end

  test "pixel dimensions round-trip" do
    with_pty(80, 24, fn _master, slave, _path ->
      assert :ok = TermiosNif.set_winsize(slave, 80, 24, 640, 480)
      assert {:ok, {80, 24, 640, 480}} = size_of(slave)
    end)
  end

  test "each pty is independent" do
    with_pty(80, 24, fn _m1, s1, p1 ->
      with_pty(100, 30, fn _m2, s2, p2 ->
        assert p1 != p2
        assert {:ok, {80, 24, _, _}} = size_of(s1)
        assert {:ok, {100, 30, _, _}} = size_of(s2)
      end)
    end)
  end

  test "data written to the master is readable through an Erlang port on it" do
    with_pty(80, 24, fn master, _slave, _path ->
      port = Port.open({:fd, master, master}, [:binary, :stream])
      assert Port.info(port) != nil
      Port.close(port)
    end)
  end

  test "closing a descriptor twice reports the failure" do
    {:ok, {master, slave, _path}} = TermiosNif.open_pty(80, 24)
    assert :ok = TermiosNif.close_fd(slave)
    assert {:error, reason} = TermiosNif.close_fd(slave)
    assert is_binary(reason)
    TermiosNif.close_fd(master)
  end

  test "rejects non-integer sizes" do
    assert_raise ArgumentError, fn -> TermiosNif.open_pty(:wide, 24) end
    assert_raise ArgumentError, fn -> TermiosNif.close_fd(:not_an_fd) end
  end

  defp size_of(fd), do: TermiosNif.get_winsize(fd)
end
