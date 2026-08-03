defmodule Drafter.Terminal.ProbeTest do
  @moduledoc """
  The graphics handshake, driven against a scripted terminal.

  `run/3` is given the two things a transport differs in — how to write bytes and
  how to read them back — so the exchange itself is tested without a terminal, a
  socket or a pty.
  """

  use ExUnit.Case, async: true

  alias Drafter.Terminal.Probe

  defp terminal(chunks) do
    {:ok, agent} = Agent.start_link(fn -> {[], chunks} end)

    write = fn data ->
      Agent.update(agent, fn {w, r} -> {[IO.iodata_to_binary(data) | w], r} end)
    end

    read = fn _timeout ->
      Agent.get_and_update(agent, fn
        {w, [next | rest]} -> {{:ok, next}, {w, rest}}
        {w, []} -> {:timeout, {w, []}}
      end)
    end

    written = fn -> agent |> Agent.get(fn {w, _r} -> w end) |> Enum.reverse() |> Enum.join() end

    {write, read, written}
  end

  describe "what gets asked" do
    test "the query goes out before anything is read" do
      {write, read, written} = terminal(["\e[?62;4c"])

      Probe.run(write, read)

      assert written.() == FrenchCurve.Capability.probe()
    end
  end

  describe "what comes back" do
    test "a terminal naming itself kitty" do
      {write, read, _} = terminal(["\eP>|kitty(0.32.2)\e\\", "\e[?62;22c"])

      assert {:kitty, ""} = Probe.run(write, read)
    end

    test "a terminal naming itself iTerm2" do
      {write, read, _} = terminal(["\eP>|iTerm2 3.5.0\e\\\e[?62;22c"])

      assert {:iterm2, ""} = Probe.run(write, read)
    end

    test "a terminal that only reports sixel among its attributes" do
      {write, read, _} = terminal(["\e[?62;4;6c"])

      assert {:sixel, ""} = Probe.run(write, read)
    end

    test "a terminal with neither a known name nor sixel" do
      {write, read, _} = terminal(["\e[?62;22c"])

      assert {nil, ""} = Probe.run(write, read)
    end

    test "a reply split across reads is reassembled" do
      {write, read, _} = terminal(["\eP>|kit", "ty(0.32", ".2)\e\\", "\e[?6", "2;22c"])

      assert {:kitty, ""} = Probe.run(write, read)
    end
  end

  describe "a terminal that does not answer" do
    test "gives up and reports no protocol" do
      {write, read, _} = terminal([])

      assert {nil, ""} = Probe.run(write, read)
    end

    test "a name with no attributes reply still resolves once reads run dry" do
      {write, read, _} = terminal(["\eP>|kitty(0.32.2)\e\\"])

      assert {:kitty, ""} = Probe.run(write, read)
    end
  end

  describe "input typed during the handshake" do
    test "is handed back rather than swallowed" do
      {write, read, _} = terminal(["\e[?62;4c" <> "abc"])

      assert {:sixel, "abc"} = Probe.run(write, read)
    end

    test "the replies themselves are never handed back as input" do
      {write, read, _} = terminal(["\eP>|kitty(0.32.2)\e\\\e[?62;22c"])

      {_protocol, leftover} = Probe.run(write, read)

      refute leftover =~ "kitty"
      refute leftover =~ "\e"
    end
  end

  describe "the deadline" do
    test "reads stop once it passes" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      write = fn _data -> :ok end

      read = fn _timeout ->
        Agent.update(counter, &(&1 + 1))
        :timeout
      end

      assert {nil, ""} = Probe.run(write, read, timeout: 40)
      assert Agent.get(counter, & &1) < 50, "gave up rather than spinning on a silent terminal"
    end

    test "a read error ends the exchange" do
      write = fn _data -> :ok end
      read = fn _timeout -> {:error, :closed} end

      assert {nil, ""} = Probe.run(write, read)
    end
  end
end
