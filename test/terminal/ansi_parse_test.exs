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
      <<head::binary-size(^size), rest::binary>> -> [head | chunks(rest, size)]
    end
  end

  describe "bracketed paste" do
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

    test "modified arrow keys split across chunks are recovered" do
      assert {[{:key, :up, [:shift]}], ""} = feed_in_chunks("\e[1;2A", 1)
    end
  end

  describe "scroll wheel" do
    test "button releases are still delivered" do
      assert {[{:mouse, %{type: :mouse_up}}], ""} = ANSI.parse_sequence("\e[<0;10;5m")
    end

    test "a wheel release between keys does not swallow them" do
      assert {[{:key, :a}, {:key, :b}], ""} =
               ANSI.parse_sequence("a\e[<65;1;1mb")
    end
  end

  describe "pixel mouse reports" do
    @pixel [pixel_mouse: true, cell_size: {8, 16}]

    test "a report in pixel mode carries the cell under the pointer and its pixel" do
      assert {[
                {:mouse,
                 %{type: :mouse_down, button: :left, x: 12, y: 3, px: {100, 50}, modifiers: []}}
              ], ""} = ANSI.parse_sequence("\e[<0;101;51M", @pixel)
    end

    test "a report in cell mode carries the cell and no pixel" do
      assert {[{:mouse, payload}], ""} = ANSI.parse_sequence("\e[<0;101;51M", cell_size: {8, 16})
      assert %{type: :mouse_down, x: 100, y: 50} = payload
      refute Map.has_key?(payload, :px)
    end

    test "the terminal's answer switches reading for the reports after it" do
      assert {[{:mouse, before}, {:pixel_mouse, true}, {:mouse, later}], ""} =
               ANSI.parse_sequence("\e[<35;3;2M\e[?1016;1$y\e[<35;101;51M", cell_size: {8, 16})

      assert %{x: 2, y: 1} = before
      refute Map.has_key?(before, :px)
      assert %{x: 12, y: 3, px: {100, 50}} = later
    end

    test "a terminal that does not know the mode leaves reports in cells" do
      assert {[{:pixel_mouse, false}, {:mouse, payload}], ""} =
               ANSI.parse_sequence("\e[?1016;0$y\e[<35;3;2M", @pixel)

      assert %{x: 2, y: 1} = payload
      refute Map.has_key?(payload, :px)
    end
  end

  describe "replies from the terminal" do
    @kitty_ok "\e_Gi=1;OK\e\\"

    test "a kitty acknowledgement arriving a byte at a time produces no events" do
      assert {[], ""} = feed_in_chunks(@kitty_ok, 1)
    end

    test "an OSC answer ending at BEL produces no events" do
      assert {[], ""} = ANSI.parse_sequence("\e]11;rgb:1e1e/1e1e/2e2e\a")
    end

    test "a reply that never terminates resolves on flush instead of being held forever" do
      assert {events, ""} = ANSI.flush_sequence("\e_Gi=1;O")
      assert events != []
    end

    test "a control sequence no table knows produces no events" do
      for reply <- ["\e[?62;4c", "\e[?2026;2$y", "\e[>1;4000;27c"] do
        assert {[], ""} = ANSI.parse_sequence(reply, key_release: true), inspect(reply)
        assert {[], ""} = feed_in_chunks(reply, 1), inspect(reply)
      end
    end

    test "keys typed around an unknown control sequence still arrive" do
      assert {[{:key, :a}, {:key, :b}], ""} = ANSI.parse_sequence("a\e[?62;4cb")
    end

    test "an unknown control sequence still missing its final byte is held" do
      assert {[], "\e[?62;4"} = ANSI.parse_sequence("\e[?62;4")
    end

    test "escape then a bracket resolve as two keys on flush" do
      assert {[{:key, :escape}, {:key, :"["}], ""} = ANSI.flush_sequence("\e[")
    end
  end
end
