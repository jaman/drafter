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
    LC_TERMINAL KONSOLE_VERSION DRAFTER_MODE DRAFTER_NO_PIXEL
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

    test "kitty, by TERM alone, with no window id to go on" do
      assert detected_for(%{"TERM" => "xterm-kitty"}) == :kitty
    end

    test "ghostty" do
      assert detected_for(%{"TERM" => "xterm-ghostty"}) == :kitty
    end

    test "wezterm, by program name" do
      assert detected_for(%{"TERM_PROGRAM" => "WezTerm"}) == :kitty
    end

    test "wezterm, by pane id, for when a multiplexer dropped the program name" do
      assert detected_for(%{"TERM" => "xterm-256color", "WEZTERM_PANE" => "0"}) == :kitty
    end
  end

  describe "terminals that speak their own protocol" do
    test "iTerm uses its inline protocol, not kitty" do
      assert detected_for(%{"TERM_PROGRAM" => "iTerm.app", "TERM_PROGRAM_VERSION" => "3.5.0"}) ==
               :iterm2
    end

    test "iTerm over ssh, by the locale variable it forwards" do
      assert detected_for(%{"TERM" => "xterm-256color", "LC_TERMINAL" => "iTerm2"}) == :iterm2
    end

    test "konsole uses sixel" do
      assert detected_for(%{"KONSOLE_VERSION" => "220400"}) == :sixel
    end

    test "foot uses sixel" do
      assert detected_for(%{"TERM" => "foot"}) == :sixel
    end
  end

  describe "terminals with no graphics" do
    test "a plain xterm reports no protocol" do
      assert detected_for(%{"TERM" => "xterm-256color"}) == nil
    end

    test "an empty environment reports no protocol" do
      assert detected_for(%{}) == nil
    end

    test "a variable exported empty does not count as a terminal" do
      assert detected_for(%{"KITTY_WINDOW_ID" => ""}) == nil
      assert detected_for(%{"WEZTERM_PANE" => ""}) == nil
    end

    test "another terminal's LC_TERMINAL is not iTerm" do
      assert detected_for(%{"LC_TERMINAL" => "Alacritty"}) == nil
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

    test "a session on a plain terminal gets no protocol from a host that has one" do
      Context.put_terminal_env(%{"TERM" => "xterm-256color"})

      assert detected_for(%{"KITTY_WINDOW_ID" => "1"}) == nil
    end

    test "two sessions on different terminals detect differently" do
      Context.put_terminal_env(%{"LC_TERMINAL" => "iTerm2"})
      assert Pixel.protocol(:auto) == :iterm2

      Context.put_terminal_env(%{"KONSOLE_VERSION" => "220400"})
      assert Pixel.protocol(:auto) == :sixel
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

    test "a terminal that answered with no graphics is not second-guessed" do
      Context.put_terminal_protocol(nil)

      assert detected_for(%{"KITTY_WINDOW_ID" => "1"}) == nil
    end

    test "a terminal that was never asked is guessed at from its environment" do
      assert Context.terminal_protocol() == :unprobed
      assert detected_for(%{"KITTY_WINDOW_ID" => "1"}) == :kitty
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
