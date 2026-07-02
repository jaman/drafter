defmodule Drafter.Regression.FkeySequencesTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.ANSI

  test "parses SS3 F1-F4 (xterm/Terminal.app default)" do
    assert {[{:key, :f1}], ""} = ANSI.parse_sequence("\eOP")
    assert {[{:key, :f2}], ""} = ANSI.parse_sequence("\eOQ")
    assert {[{:key, :f3}], ""} = ANSI.parse_sequence("\eOR")
    assert {[{:key, :f4}], ""} = ANSI.parse_sequence("\eOS")
  end

  test "parses CSI tilde F1-F4 (vt220, screen, tmux terminfo)" do
    assert {[{:key, :f1}], ""} = ANSI.parse_sequence("\e[11~")
    assert {[{:key, :f2}], ""} = ANSI.parse_sequence("\e[12~")
    assert {[{:key, :f3}], ""} = ANSI.parse_sequence("\e[13~")
    assert {[{:key, :f4}], ""} = ANSI.parse_sequence("\e[14~")
  end

  test "parses CSI letter F1-F4 (some xterm configurations)" do
    assert {[{:key, :f2}], ""} = ANSI.parse_sequence("\e[1Q")
    assert {[{:key, :f3}], ""} = ANSI.parse_sequence("\e[1R")
  end

  test "parses Linux console F1-F5" do
    assert {[{:key, :f1}], ""} = ANSI.parse_sequence("\e[[A")
    assert {[{:key, :f5}], ""} = ANSI.parse_sequence("\e[[E")
  end

  test "F5-F12 CSI tilde forms still parse" do
    assert {[{:key, :f5}], ""} = ANSI.parse_sequence("\e[15~")
    assert {[{:key, :f12}], ""} = ANSI.parse_sequence("\e[24~")
  end
end
