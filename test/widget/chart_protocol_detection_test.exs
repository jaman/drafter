defmodule Drafter.Widget.Chart.ProtocolDetectionTest do
  @moduledoc """
  Which graphics protocol `renderer: :auto` resolves to, per terminal.

  The rules themselves belong to `FrenchCurve.Capability`; these cover that Drafter
  asks it, and that a terminal it cannot place still reports no protocol rather than
  guessing one.
  """

  use ExUnit.Case, async: false

  alias Drafter.Session.Context
  alias Drafter.Widget.Chart.Pixel

  @controlled ~w(
    TERM TERM_PROGRAM TERM_PROGRAM_VERSION KITTY_WINDOW_ID WEZTERM_PANE
    LC_TERMINAL LC_TERMINAL_VERSION KONSOLE_VERSION DRAFTER_MODE DRAFTER_NO_PIXEL FRENCH_CURVE_ITERM2
  )

  defp detected_for(overrides) do
    kept = Map.new(@controlled, &{&1, System.get_env(&1)})
    unset = Map.new(@controlled, &{&1, nil})

    put_env(Map.merge(unset, overrides))

    try do
      Pixel.protocol(:auto)
    after
      put_env(kept)
    end
  end

  defp put_env(env) do
    Enum.each(env, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)
  end

  describe "terminals that speak kitty" do
    test "kitty, by the window id it exports" do
      assert detected_for(%{"KITTY_WINDOW_ID" => "1"}) == :kitty
    end
  end

  describe "terminals with no graphics" do
    test "a plain xterm reports no protocol" do
      assert detected_for(%{"TERM" => "xterm-256color"}) == nil
    end
  end

  describe "a session detects its own terminal, not the host's" do
    setup do
      on_exit(fn -> Process.delete(:drafter_terminal_env) end)
      :ok
    end

    test "the session's terminal is what gets detected" do
      Context.put_terminal_env(%{"TERM" => "xterm-kitty"})

      assert detected_for(%{"TERM" => "xterm-256color"}) == :kitty
    end
  end

  describe "a probed answer is used in place of guessing" do
    setup do
      on_exit(fn ->
        Process.delete(:drafter_terminal_protocol)
        Process.delete(:drafter_terminal_env)
      end)

      :ok
    end

    test "what the terminal answered wins over what its environment implies" do
      Context.put_terminal_protocol(:sixel)

      assert detected_for(%{"TERM" => "xterm-kitty"}) == :sixel
    end

    test "a terminal that answered without naming a protocol is guessed at from its environment" do
      Context.put_terminal_protocol(nil)

      assert detected_for(%{"KITTY_WINDOW_ID" => "1"}) == :kitty
      assert detected_for(%{"TERM" => "xterm-256color"}) == nil
    end

    test "whatever iTerm2 answers, its environment decides between inline and kitty" do
      iterm = %{"TERM_PROGRAM" => "iTerm.app", "TERM_PROGRAM_VERSION" => "3.7.2"}
      forced = Map.put(iterm, "FRENCH_CURVE_ITERM2", "kitty")

      for answered <- [:kitty, :sixel, :iterm2] do
        Context.put_terminal_protocol(answered)

        assert detected_for(iterm) == :iterm2, "answered #{answered}"
        assert detected_for(forced) == :kitty, "answered #{answered}"
      end

      Context.put_terminal_protocol(:sixel)
      assert detected_for(%{"TERM" => "foot"}) == :sixel

      Context.put_terminal_protocol(:kitty)
      assert detected_for(%{"TERM" => "xterm-ghostty"}) == :kitty
    end
  end

  describe "an explicit renderer still wins over the terminal" do
    test "a named protocol is used whatever the terminal says" do
      kept = Map.new(@controlled, &{&1, System.get_env(&1)})
      put_env(Map.merge(Map.new(@controlled, &{&1, nil}), %{"TERM" => "xterm-256color"}))

      try do
        assert Pixel.protocol(:sixel) == :sixel
        assert Pixel.protocol(:text) == nil
      after
        put_env(kept)
      end
    end
  end
end
