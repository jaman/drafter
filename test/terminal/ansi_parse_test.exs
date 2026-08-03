defmodule Drafter.Terminal.ANSIParseTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.ANSI

  defp feed_in_chunks(input, chunk_size) do
    input
    |> chunks(chunk_size)
    |> Enum.reduce({[], ""}, fn chunk, {events, buffer} ->
      {new_events, remaining} = ANSI.parse_sequence(buffer <> chunk)
      {events ++ new_events, remaining}
    end)
  end

  defp chunks(binary, size) do
    case binary do
      <<>> -> []
      _ when byte_size(binary) <= size -> [binary]
      <<head::binary-size(size), rest::binary>> -> [head | chunks(rest, size)]
    end
  end

  describe "bracketed paste" do
    test "whole paste in one buffer" do
      assert {[{:bracketed_paste, "hello world"}], ""} =
               ANSI.parse_sequence("\e[200~hello world\e[201~")
    end

    test "start marker alone is retained, not decomposed" do
      assert {[], "\e[200~"} = ANSI.parse_sequence("\e[200~")
    end

    test "partial start marker is retained" do
      assert {[], "\e[20"} = ANSI.parse_sequence("\e[20")
      assert {[], "\e["} = ANSI.parse_sequence("\e[")
    end

    test "paste with no terminator yet is retained whole" do
      assert {[], "\e[200~partial"} = ANSI.parse_sequence("\e[200~partial")
    end

    test "paste arriving one byte at a time yields a single paste event" do
      assert {[{:bracketed_paste, "hi"}], ""} = feed_in_chunks("\e[200~hi\e[201~", 1)
    end

    test "multi-line paste arriving one byte at a time survives intact" do
      body = "select * from quotes\nwhere id = 1\n"
      assert {[{:bracketed_paste, ^body}], ""} = feed_in_chunks("\e[200~#{body}\e[201~", 1)
    end

    test "paste split across arbitrary chunk boundaries survives intact" do
      body = String.duplicate("abcdefghij", 20)
      input = "\e[200~#{body}\e[201~"

      for size <- [1, 2, 3, 5, 7, 13, 64] do
        assert {[{:bracketed_paste, ^body}], ""} = feed_in_chunks(input, size)
      end
    end

    test "paste containing escape sequences is passed through verbatim" do
      body = "\e[31mred\e[0m"
      assert {[{:bracketed_paste, ^body}], ""} = ANSI.parse_sequence("\e[200~#{body}\e[201~")
    end

    test "keys before and after a paste are preserved in order" do
      assert {[{:key, :a}, {:bracketed_paste, "x"}, {:key, :b}], ""} =
               ANSI.parse_sequence("a\e[200~x\e[201~b")
    end
  end

  describe "incomplete escape sequences" do
    test "a proper prefix of a known sequence is retained" do
      assert {[], "\e[1;"} = ANSI.parse_sequence("\e[1;")
      assert {[], "\eO"} = ANSI.parse_sequence("\eO")
    end

    test "a bare escape is held until flushed, then delivered as the escape key" do
      assert {[], "\e"} = ANSI.parse_sequence("\e")
      assert {[{:key, :escape}], ""} = ANSI.flush_sequence("\e")
    end

    test "flushing an unterminated paste delivers what arrived" do
      assert {[{:bracketed_paste, "partial"}], ""} = ANSI.flush_sequence("\e[200~partial")
    end

    test "flushing an empty buffer yields nothing" do
      assert {[], ""} = ANSI.flush_sequence("")
    end

    test "arrow keys split across chunks are recovered" do
      assert {[{:key, :up}], ""} = feed_in_chunks("\e[A", 1)
      assert {[{:key, :right}, {:key, :left}], ""} = feed_in_chunks("\e[C\e[D", 2)
    end

    test "modified arrow keys split across chunks are recovered" do
      assert {[{:key, :up, [:shift]}], ""} = feed_in_chunks("\e[1;2A", 1)
    end

    test "function keys split across chunks are recovered" do
      assert {[{:key, :f5}], ""} = feed_in_chunks("\e[15~", 1)
    end
  end

  describe "regular keys" do
    test "printable ascii" do
      assert {[{:key, :a}, {:key, :b}], ""} = ANSI.parse_sequence("ab")
    end

    test "control keys" do
      assert {[{:key, :c, [:ctrl]}], ""} = ANSI.parse_sequence("\x03")
      assert {[{:key, :enter}], ""} = ANSI.parse_sequence("\r")
      assert {[{:key, :backspace}], ""} = ANSI.parse_sequence("\x7f")
    end

    test "non-ascii text arrives as char events" do
      assert {[{:char, 233}], ""} = ANSI.parse_sequence("é")
    end

    test "an incomplete utf8 codepoint is retained" do
      <<first, rest::binary>> = "é"
      assert {[], <<^first>>} = ANSI.parse_sequence(<<first>>)
      assert {[{:char, 233}], ""} = ANSI.parse_sequence(<<first>> <> rest)
    end
  end

  describe "scroll wheel" do
    test "a wheel notch produces exactly one scroll event" do
      assert {[{:mouse, %{type: :scroll, direction: :down}}], ""} =
               ANSI.parse_sequence("\e[<65;10;5M")
    end

    test "a wheel release produces nothing" do
      assert {[], ""} = ANSI.parse_sequence("\e[<65;10;5m")
      assert {[], ""} = ANSI.parse_sequence("\e[<64;10;5m")
    end

    test "a press/release pair scrolls one row, not two" do
      {events, ""} = ANSI.parse_sequence("\e[<65;10;5M\e[<65;10;5m")
      assert length(events) == 1
    end

    test "three notches reported as pairs scroll three rows" do
      pair = "\e[<65;10;5M\e[<65;10;5m"
      {events, ""} = ANSI.parse_sequence(pair <> pair <> pair)
      assert length(events) == 3
    end

    test "wheel up and down keep their directions" do
      assert {[{:mouse, %{direction: :up}}], ""} = ANSI.parse_sequence("\e[<64;1;1M")
      assert {[{:mouse, %{direction: :down}}], ""} = ANSI.parse_sequence("\e[<65;1;1M")
    end

    test "button releases are still delivered" do
      assert {[{:mouse, %{type: :mouse_up}}], ""} = ANSI.parse_sequence("\e[<0;10;5m")
    end

    test "a wheel release between keys does not swallow them" do
      assert {[{:key, :a}, {:key, :b}], ""} =
               ANSI.parse_sequence("a\e[<65;1;1mb")
    end
  end

  describe "mouse" do
    test "sgr mouse press" do
      assert {[{:mouse, %{}}], ""} = ANSI.parse_sequence("\e[<0;10;5M")
    end

    test "sgr mouse split across chunks is recovered" do
      assert {[{:mouse, %{}}], ""} = feed_in_chunks("\e[<0;10;5M", 1)
    end
  end

  describe "replies from the terminal" do
    @kitty_ok "\e_Gi=1;OK\e\\"

    test "a kitty acknowledgement produces no events" do
      assert {[], ""} = ANSI.parse_sequence(@kitty_ok)
    end

    test "a kitty acknowledgement arriving a byte at a time produces no events" do
      assert {[], ""} = feed_in_chunks(@kitty_ok, 1)
    end

    test "keys typed around a reply still arrive" do
      assert {[{:key, :a}, {:key, :b}], ""} =
               ANSI.parse_sequence("a" <> @kitty_ok <> "b")
    end

    test "an OSC answer ending at BEL produces no events" do
      assert {[], ""} = ANSI.parse_sequence("\e]11;rgb:1e1e/1e1e/2e2e\a")
    end

    test "an unterminated reply is held rather than spelled out" do
      assert {[], "\e_Gi=1;O"} = ANSI.parse_sequence("\e_Gi=1;O")
    end

    test "a reply that never terminates resolves on flush instead of being held forever" do
      assert {events, ""} = ANSI.flush_sequence("\e_Gi=1;O")
      assert events != []
    end
  end
end
