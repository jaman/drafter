defmodule Drafter.Terminal.InputBufferTest do
  use ExUnit.Case, async: true

  alias Drafter.Terminal.InputBuffer

  defp feed_all(chunks) do
    Enum.reduce(chunks, {[], InputBuffer.new()}, fn chunk, {events, buffer} ->
      {new_events, buffer} = InputBuffer.feed(buffer, chunk)
      {events ++ new_events, buffer}
    end)
  end

  defp bytes(binary), do: for(<<byte <- binary>>, do: <<byte>>)

  test "a complete chunk decodes immediately and holds nothing" do
    {events, buffer} = InputBuffer.feed(InputBuffer.new(), "abc")
    assert events == [key: :a, key: :b, key: :c]
    assert buffer.pending == ""
    assert buffer.timer == nil
  end

  test "an escape sequence split across chunks decodes once complete" do
    {events, buffer} = feed_all(["\e[", "A"])
    assert events == [key: :up]
    assert buffer.pending == ""
  end

  test "a paste split byte by byte decodes as one paste event" do
    {events, buffer} = feed_all(bytes("\e[200~hello\e[201~"))
    assert events == [bracketed_paste: "hello"]
    assert buffer.pending == ""
  end

  test "a large paste split byte by byte survives intact" do
    body = String.duplicate("0123456789", 50)
    {events, _buffer} = feed_all(bytes("\e[200~#{body}\e[201~"))
    assert events == [bracketed_paste: body]
  end

  test "undecided bytes schedule a flush" do
    {events, buffer} = InputBuffer.feed(InputBuffer.new(), "\e[")
    assert events == []
    assert buffer.pending == "\e["
    assert is_reference(buffer.timer)
    assert_receive :input_flush, 500
  end

  test "a completed sequence cancels the pending flush" do
    {_, buffer} = InputBuffer.feed(InputBuffer.new(), "\e[")
    {events, buffer} = InputBuffer.feed(buffer, "A")
    assert events == [key: :up]
    assert buffer.timer == nil
    refute_receive :input_flush, 100
  end

  test "flushing a held escape yields the escape key" do
    {[], buffer} = InputBuffer.feed(InputBuffer.new(), "\e")
    {events, buffer} = InputBuffer.flush(buffer)
    assert events == [key: :escape]
    assert buffer.pending == ""
    assert buffer.timer == nil
  end

  test "flushing an empty buffer is a no-op" do
    assert {[], %InputBuffer{pending: ""}} = InputBuffer.flush(InputBuffer.new())
  end

  test "reset discards held bytes" do
    {[], buffer} = InputBuffer.feed(InputBuffer.new(), "\e[200~partial")
    buffer = InputBuffer.reset(buffer)
    assert buffer.pending == ""
    assert buffer.timer == nil
  end

  test "keys typed while a paste is buffering are not lost or reordered" do
    {events, _buffer} = feed_all(["x", "\e[200~pa", "ste\e[201~", "y"])
    assert events == [{:key, :x}, {:bracketed_paste, "paste"}, {:key, :y}]
  end
end
