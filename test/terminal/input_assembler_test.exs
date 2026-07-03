defmodule Drafter.Terminal.InputAssemblerTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.InputAssembler

  defp start_assembler do
    InputAssembler.start(self(), pump: false)
  end

  defp feed(assembler, bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.each(fn byte -> send(assembler, {:byte, <<byte>>}) end)
  end

  defp assert_chunk(expected) do
    assert_receive {:stdin, ^expected}, 500
  end

  test "plain bytes pass through individually" do
    assembler = start_assembler()
    feed(assembler, "ab")
    assert_chunk("a")
    assert_chunk("b")
  end

  test "CSI sequences arrive as one complete unit" do
    assembler = start_assembler()
    feed(assembler, "\e[15~")
    assert_chunk("\e[15~")
  end

  test "CSI with parameters terminates on the final byte" do
    assembler = start_assembler()
    feed(assembler, "\e[1;5A")
    assert_chunk("\e[1;5A")
  end

  test "SS3 function keys are not split from their final byte" do
    assembler = start_assembler()
    feed(assembler, "\eOQ")
    assert_chunk("\eOQ")
  end

  test "a bare Escape flushes promptly without waiting for the next key" do
    assembler = start_assembler()
    feed(assembler, "\e")
    assert_chunk("\e")
  end

  test "Escape followed later by an unrelated key yields Escape then the key" do
    assembler = start_assembler()
    feed(assembler, "\e")
    assert_chunk("\e")
    feed(assembler, "q")
    assert_chunk("q")
  end

  test "SGR mouse reports arrive as one unit" do
    assembler = start_assembler()
    feed(assembler, "\e[<0;12;5M")
    assert_chunk("\e[<0;12;5M")
  end

  test "X10 mouse reports keep their three raw payload bytes, high-bit included" do
    assembler = start_assembler()
    feed(assembler, "\e[M" <> <<0x20, 0xC8, 0x9F>>)
    assert_chunk("\e[M" <> <<0x20, 0xC8, 0x9F>>)
  end

  test "linux console function keys arrive whole" do
    assembler = start_assembler()
    feed(assembler, "\e[[B")
    assert_chunk("\e[[B")
  end

  test "bracketed paste is one unit including multi-line content" do
    assembler = start_assembler()
    paste = "\e[200~select 1;\nselect 2;\e[201~"
    feed(assembler, paste)
    assert_chunk(paste)
  end

  test "a torn CSI sequence flushes on timeout instead of wedging input" do
    assembler = start_assembler()
    feed(assembler, "\e[1")
    assert_receive {:stdin, "\e[1"}, 500
    feed(assembler, "x")
    assert_chunk("x")
  end

  test "arbitrary non-UTF8 bytes flow through without killing anything" do
    assembler = start_assembler()
    feed(assembler, <<0xFF, 0xFE>>)
    assert_chunk(<<0xFF>>)
    assert_chunk(<<0xFE>>)
    assert Process.alive?(assembler)
  end
end
