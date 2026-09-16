defmodule Drafter.Terminal.KittyKeyboardTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.{ANSI, KittyKeyboard}

  describe "sequences" do
    test "push asks for disambiguation, event types, all keys as escape codes, and text" do
      assert KittyKeyboard.push() == "\e[>27u"
    end

    test "pop restores the previous mode" do
      assert KittyKeyboard.pop() == "\e[<u"
    end

    test "query asks for the current flags" do
      assert KittyKeyboard.query() == "\e[?u"
    end
  end

  describe "query reply" do
    test "releases are reported only when the reply's flags carry event types (bit 2)" do
      assert {[{:key_release_support, true}], ""} = ANSI.parse_sequence("\e[?27u")
      assert {[{:key_release_support, true}], ""} = ANSI.parse_sequence("\e[?3u")
      assert {[{:key_release_support, false}], ""} = ANSI.parse_sequence("\e[?0u")
      assert {[{:key_release_support, false}], ""} = ANSI.parse_sequence("\e[?1u")
      assert {[{:key_release_support, false}], ""} = ANSI.parse_sequence("\e[?9u")
    end
  end

  describe "text keys" do
    test "a plain press is the legacy key plus a key_down on the base key" do
      assert {[{:key, :a}, {:key_down, :a, []}], ""} = ANSI.parse_sequence("\e[97u")
    end

    test "a repeat is only the legacy key" do
      assert {[{:key, :a}], ""} = ANSI.parse_sequence("\e[97;1:2u")
    end

    test "a release is a key_up on the base key" do
      assert {[{:key_up, :a, []}], ""} = ANSI.parse_sequence("\e[97;1:3u")
    end

    test "ctrl is carried on both events" do
      assert {[{:key, :a, [:ctrl]}, {:key_down, :a, [:ctrl]}], ""} =
               ANSI.parse_sequence("\e[97;5u")
    end

    test "alt is carried on both events" do
      assert {[{:key, :a, [:alt]}, {:key_down, :a, [:alt]}], ""} =
               ANSI.parse_sequence("\e[97;3u")
    end

    test "modifiers are ordered ctrl, alt, shift" do
      assert {[{:key, :a, [:ctrl, :alt, :shift]}, {:key_down, :a, [:ctrl, :alt, :shift]}], ""} =
               ANSI.parse_sequence("\e[97;8u")
    end

    test "shift with text reports the typed glyph as the legacy key and the base key on key_down" do
      assert {[{:key, :A}, {:key_down, :a, [:shift]}], ""} = ANSI.parse_sequence("\e[97;2;65u")
      assert {[{:key, :!}, {:key_down, :"1", [:shift]}], ""} = ANSI.parse_sequence("\e[49;2;33u")
    end

    test "shift on a letter without text uppercases it" do
      assert {[{:key, :A}, {:key_down, :a, [:shift]}], ""} = ANSI.parse_sequence("\e[97;2u")
    end

    test "shift on a non-letter without text keeps the modifier" do
      assert {[{:key, :"1", [:shift]}, {:key_down, :"1", [:shift]}], ""} =
               ANSI.parse_sequence("\e[49;2u")
    end

    test "text with ctrl held is not typed" do
      assert {[{:key, :a, [:ctrl]}, {:key_down, :a, [:ctrl]}], ""} =
               ANSI.parse_sequence("\e[97;5;97u")
    end

    test "a non-ascii glyph is a char event" do
      assert {[{:char, 233}, {:key_down, 233, []}], ""} = ANSI.parse_sequence("\e[233u")
    end

    test "text with several codepoints types each one" do
      assert {[{:char, 233}, {:char, 233}, {:key_down, :e, []}], ""} =
               ANSI.parse_sequence("\e[101;1;233:233u")
    end

    test "caps lock and num lock are not modifiers" do
      assert {[{:key, :a}, {:key_down, :a, []}], ""} = ANSI.parse_sequence("\e[97;65u")
      assert {[{:key, :a}, {:key_down, :a, []}], ""} = ANSI.parse_sequence("\e[97;129u")
    end

    test "space" do
      assert {[{:key, :" "}, {:key_down, :" ", []}], ""} = ANSI.parse_sequence("\e[32u")
    end

    test "alternate key codes are ignored in favour of the base key" do
      assert {[{:key, :A}, {:key_down, :a, [:shift]}], ""} =
               ANSI.parse_sequence("\e[97:65:97;2;65u")
    end
  end

  describe "keys with CSI u codes" do
    test "escape, enter, tab and backspace keep their legacy names" do
      assert {[{:key, :escape}, {:key_down, :escape, []}], ""} = ANSI.parse_sequence("\e[27u")
      assert {[{:key, :enter}, {:key_down, :enter, []}], ""} = ANSI.parse_sequence("\e[13u")
      assert {[{:key, :tab}, {:key_down, :tab, []}], ""} = ANSI.parse_sequence("\e[9u")

      assert {[{:key, :backspace}, {:key_down, :backspace, []}], ""} =
               ANSI.parse_sequence("\e[127u")
    end

    test "shift+tab matches the legacy event" do
      assert {[{:key, :tab, [:shift]}, {:key_down, :tab, [:shift]}], ""} =
               ANSI.parse_sequence("\e[9;2u")
    end

    test "their releases are key_up" do
      assert {[{:key_up, :enter, []}], ""} = ANSI.parse_sequence("\e[13;1:3u")
    end

    test "modifier keys are only ever key_down and key_up" do
      assert {[{:key_down, :left_shift, []}], ""} = ANSI.parse_sequence("\e[57441u")
      assert {[{:key_up, :left_shift, []}], ""} = ANSI.parse_sequence("\e[57441;1:3u")
      assert {[{:key_down, :right_control, []}], ""} = ANSI.parse_sequence("\e[57448u")
    end

    test "keypad keys without text are only key_down and key_up" do
      assert {[{:key_down, :kp_5, []}], ""} = ANSI.parse_sequence("\e[57404u")
      assert {[{:key_up, :kp_enter, []}], ""} = ANSI.parse_sequence("\e[57414;1:3u")
    end

    test "keypad keys with text also type it" do
      assert {[{:key, :"5"}, {:key_down, :kp_5, []}], ""} = ANSI.parse_sequence("\e[57404;1;53u")
    end

    test "function keys beyond f12 and media keys are named" do
      assert {[{:key_down, :f13, []}], ""} = ANSI.parse_sequence("\e[57376u")
      assert {[{:key_down, :media_play, []}], ""} = ANSI.parse_sequence("\e[57428u")
    end

    test "an unknown functional code is dropped" do
      assert {[], ""} = ANSI.parse_sequence("\e[58000u")
    end
  end

  describe "keys with legacy finals" do
    test "a release carries the event type in the modifier field" do
      assert {[{:key_up, :up, []}], ""} = ANSI.parse_sequence("\e[1;1:3A")
      assert {[{:key_up, :delete, []}], ""} = ANSI.parse_sequence("\e[3;1:3~")
      assert {[{:key_up, :f5, []}], ""} = ANSI.parse_sequence("\e[15;1:3~")
      assert {[{:key_up, :f1, []}], ""} = ANSI.parse_sequence("\e[1;1:3P")
    end

    test "a repeat is only the legacy key" do
      assert {[{:key, :page_up}], ""} = ANSI.parse_sequence("\e[5;1:2~")
    end

    test "an explicit press is the legacy key plus key_down" do
      assert {[{:key, :right, [:ctrl]}, {:key_down, :right, [:ctrl]}], ""} =
               ANSI.parse_sequence("\e[1;5:1C")
    end

    test "a release with modifiers" do
      assert {[{:key_up, :left, [:shift]}], ""} = ANSI.parse_sequence("\e[1;2:3D")
    end

    test "home and end in both encodings" do
      assert {[{:key_up, :home, []}], ""} = ANSI.parse_sequence("\e[1;1:3H")
      assert {[{:key_up, :home, []}], ""} = ANSI.parse_sequence("\e[7;1:3~")
      assert {[{:key_up, :end, []}], ""} = ANSI.parse_sequence("\e[8;1:3~")
    end

    test "kp_begin" do
      assert {[{:key, :kp_begin}, {:key_down, :kp_begin, []}], ""} =
               ANSI.parse_sequence("\e[1;1:1E")
    end
  end

  describe "without key release mode, legacy sequences are untouched" do
    test "a table sequence does not gain a key_down" do
      assert {[{:key, :up}], ""} = ANSI.parse_sequence("\e[A")
      assert {[{:key, :right, [:ctrl]}], ""} = ANSI.parse_sequence("\e[1;5C")
      assert {[{:key, :a}], ""} = ANSI.parse_sequence("a")
    end
  end

  describe "in key release mode, legacy sequences gain a key_down" do
    test "named keys" do
      assert {[{:key, :up}, {:key_down, :up, []}], ""} =
               ANSI.parse_sequence("\e[A", key_release: true)

      assert {[{:key, :right, [:ctrl]}, {:key_down, :right, [:ctrl]}], ""} =
               ANSI.parse_sequence("\e[1;5C", key_release: true)

      assert {[{:key, :delete}, {:key_down, :delete, []}], ""} =
               ANSI.parse_sequence("\e[3~", key_release: true)
    end

    test "flush_sequence too" do
      assert {[{:key, :escape}, {:key_down, :escape, []}], ""} =
               ANSI.flush_sequence("\e", key_release: true)
    end

    test "mouse and paste events are unchanged" do
      assert {[{:mouse, _}], ""} = ANSI.parse_sequence("\e[<0;10;5M", key_release: true)

      assert {[{:bracketed_paste, "x"}], ""} =
               ANSI.parse_sequence("\e[200~x\e[201~", key_release: true)
    end
  end

  describe "partial sequences" do
    test "an unterminated CSI u is retained" do
      assert {[], "\e[97;1:"} = ANSI.parse_sequence("\e[97;1:")
    end

    test "a sequence split across reads parses whole" do
      {events, rest} = ANSI.parse_sequence("\e[97;1")
      assert events == []
      assert {[{:key_up, :a, []}], ""} = ANSI.parse_sequence(rest <> ":3u")
    end
  end
end
