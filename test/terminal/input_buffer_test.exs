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

  test "a paste split byte by byte decodes as one paste event" do
    {events, buffer} = feed_all(bytes("\e[200~hello\e[201~"))
    assert events == [bracketed_paste: "hello"]
    assert buffer.pending == ""
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

  test "a buffer opened with key release on adds key_down to legacy presses" do
    {events, buffer} = InputBuffer.feed(InputBuffer.new(key_release: true), "\e[A")
    assert events == [{:key, :up}, {:key_down, :up, []}]
    assert buffer.key_release
  end

  test "and flushes with it too" do
    {[], buffer} = InputBuffer.feed(InputBuffer.new(key_release: true), "\e")
    {events, _buffer} = InputBuffer.flush(buffer)
    assert events == [{:key, :escape}, {:key_down, :escape, []}]
  end

  test "a buffer opened without it leaves legacy presses alone" do
    {events, buffer} = InputBuffer.feed(InputBuffer.new(), "\e[A")
    assert events == [{:key, :up}]
    refute buffer.key_release
  end

  describe "mouse buttons" do
    test "motion reported with a button that was never pressed is a move" do
      {events, _buffer} = feed_all(["\e[<32;10;5M", "\e[<32;11;5M"])

      assert events == [
               mouse: %{type: :move, x: 9, y: 4, modifiers: []},
               mouse: %{type: :move, x: 10, y: 4, modifiers: []}
             ]
    end

    test "motion while the button is down is a drag, and a move again after release" do
      {events, _buffer} =
        feed_all(["\e[<0;10;5M", "\e[<32;11;5M", "\e[<0;11;5m", "\e[<32;12;5M"])

      assert [
               mouse: %{type: :mouse_down, button: :left},
               mouse: %{type: :drag, button: :left, x: 10},
               mouse: %{type: :mouse_up, button: :left},
               mouse: %{type: :move, x: 11}
             ] = events
    end

    test "the no-button motion code is a move whatever was pressed before" do
      {events, _buffer} = feed_all(["\e[<0;1;1M", "\e[<0;1;1m", "\e[<35;2;2M"])
      assert List.last(events) == {:mouse, %{type: :move, x: 1, y: 1, modifiers: []}}
    end

    test "held buttons survive across chunks" do
      {events, _buffer} = feed_all(["\e[<0;10;5M\e[<", "32;11;5M"])
      assert [mouse: %{type: :mouse_down}, mouse: %{type: :drag}] = events
    end
  end
end
