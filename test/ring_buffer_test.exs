defmodule Drafter.RingBufferTest do
  use ExUnit.Case, async: true

  alias Drafter.RingBuffer

  doctest Drafter.RingBuffer

  describe "slice/3" do
    test "works correctly after wraparound" do
      buf = RingBuffer.new(4) |> RingBuffer.push_many([:a, :b, :c, :d, :e, :f])
      assert RingBuffer.slice(buf, 0, 2) == [:c, :d]
      assert RingBuffer.slice(buf, 2, 2) == [:e, :f]
      assert RingBuffer.slice(buf, 1, 3) == [:d, :e, :f]
    end
  end

  describe "Enumerable protocol" do
    test "Enum.slice/2 uses efficient slice" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many(1..10)
      assert Enum.slice(buf, 3..5) == [4, 5, 6]
    end
  end
end
