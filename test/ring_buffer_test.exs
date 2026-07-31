defmodule Drafter.RingBufferTest do
  use ExUnit.Case, async: true

  alias Drafter.RingBuffer

  doctest Drafter.RingBuffer

  describe "new/1" do
    test "creates empty buffer with given max size" do
      buf = RingBuffer.new(5)
      assert RingBuffer.count(buf) == 0
      assert RingBuffer.max_size(buf) == 5
      assert RingBuffer.empty?(buf)
    end
  end

  describe "push/2" do
    test "adds items and increments count" do
      buf = RingBuffer.new(5) |> RingBuffer.push(:a) |> RingBuffer.push(:b)
      assert RingBuffer.count(buf) == 2
      refute RingBuffer.empty?(buf)
    end

    test "overwrites oldest when full" do
      buf =
        RingBuffer.new(3)
        |> RingBuffer.push(:a)
        |> RingBuffer.push(:b)
        |> RingBuffer.push(:c)
        |> RingBuffer.push(:d)

      assert RingBuffer.count(buf) == 3
      assert RingBuffer.to_list(buf) == [:b, :c, :d]
    end

    test "count never exceeds max_size" do
      buf = Enum.reduce(1..100, RingBuffer.new(10), &RingBuffer.push(&2, &1))
      assert RingBuffer.count(buf) == 10
    end
  end

  describe "push_many/2" do
    test "pushes multiple items" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many([:a, :b, :c])
      assert RingBuffer.to_list(buf) == [:a, :b, :c]
    end

    test "respects max size with overflow" do
      buf = RingBuffer.new(3) |> RingBuffer.push_many([:a, :b, :c, :d, :e])
      assert RingBuffer.to_list(buf) == [:c, :d, :e]
    end
  end

  describe "at/2" do
    test "returns item at logical index (0 = oldest)" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many([:a, :b, :c])
      assert RingBuffer.at(buf, 0) == :a
      assert RingBuffer.at(buf, 1) == :b
      assert RingBuffer.at(buf, 2) == :c
    end

    test "returns nil for out-of-bounds index" do
      buf = RingBuffer.new(5) |> RingBuffer.push(:a)
      assert RingBuffer.at(buf, 1) == nil
      assert RingBuffer.at(buf, 99) == nil
    end

    test "works after wraparound" do
      buf = RingBuffer.new(3) |> RingBuffer.push_many([:a, :b, :c, :d, :e])
      assert RingBuffer.at(buf, 0) == :c
      assert RingBuffer.at(buf, 1) == :d
      assert RingBuffer.at(buf, 2) == :e
    end
  end

  describe "last/1" do
    test "returns most recently pushed item" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many([:a, :b, :c])
      assert RingBuffer.last(buf) == :c
    end

    test "returns nil for empty buffer" do
      assert RingBuffer.last(RingBuffer.new(5)) == nil
    end
  end

  describe "slice/3" do
    test "returns items from offset with given length" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many([:a, :b, :c, :d, :e])
      assert RingBuffer.slice(buf, 1, 3) == [:b, :c, :d]
    end

    test "clamps to available data" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many([:a, :b, :c])
      assert RingBuffer.slice(buf, 1, 100) == [:b, :c]
    end

    test "returns empty list for offset beyond count" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many([:a, :b])
      assert RingBuffer.slice(buf, 5, 3) == []
    end

    test "returns empty list for zero length" do
      buf = RingBuffer.new(10) |> RingBuffer.push(:a)
      assert RingBuffer.slice(buf, 0, 0) == []
    end

    test "works correctly after wraparound" do
      buf = RingBuffer.new(4) |> RingBuffer.push_many([:a, :b, :c, :d, :e, :f])
      assert RingBuffer.slice(buf, 0, 2) == [:c, :d]
      assert RingBuffer.slice(buf, 2, 2) == [:e, :f]
      assert RingBuffer.slice(buf, 1, 3) == [:d, :e, :f]
    end
  end

  describe "last_n/2" do
    test "returns last n items" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many([:a, :b, :c, :d, :e])
      assert RingBuffer.last_n(buf, 3) == [:c, :d, :e]
    end

    test "returns all items when n exceeds count" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many([:a, :b])
      assert RingBuffer.last_n(buf, 5) == [:a, :b]
    end

    test "returns empty list for n = 0" do
      buf = RingBuffer.new(10) |> RingBuffer.push(:a)
      assert RingBuffer.last_n(buf, 0) == []
    end
  end

  describe "to_list/1" do
    test "returns all items oldest to newest" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many(1..5)
      assert RingBuffer.to_list(buf) == [1, 2, 3, 4, 5]
    end

    test "returns correct order after wraparound" do
      buf = RingBuffer.new(3) |> RingBuffer.push_many(1..7)
      assert RingBuffer.to_list(buf) == [5, 6, 7]
    end

    test "returns empty list for empty buffer" do
      assert RingBuffer.to_list(RingBuffer.new(5)) == []
    end
  end

  describe "resize/2" do
    test "shrinks buffer keeping newest items" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many(1..8) |> RingBuffer.resize(3)
      assert RingBuffer.max_size(buf) == 3
      assert RingBuffer.count(buf) == 3
      assert RingBuffer.to_list(buf) == [6, 7, 8]
    end

    test "grows buffer preserving all items" do
      buf = RingBuffer.new(3) |> RingBuffer.push_many(1..3) |> RingBuffer.resize(10)
      assert RingBuffer.max_size(buf) == 10
      assert RingBuffer.count(buf) == 3
      assert RingBuffer.to_list(buf) == [1, 2, 3]
    end

    test "push works correctly after resize" do
      buf =
        RingBuffer.new(3)
        |> RingBuffer.push_many(1..3)
        |> RingBuffer.resize(5)
        |> RingBuffer.push(4)
        |> RingBuffer.push(5)

      assert RingBuffer.to_list(buf) == [1, 2, 3, 4, 5]
    end
  end

  describe "Enumerable protocol" do
    test "Enum.count/1" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many([:a, :b, :c])
      assert Enum.count(buf) == 3
    end

    test "Enum.member?/2" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many([:a, :b, :c])
      assert Enum.member?(buf, :b)
      refute Enum.member?(buf, :z)
    end

    test "Enum.to_list/1" do
      buf = RingBuffer.new(3) |> RingBuffer.push_many(1..5)
      assert Enum.to_list(buf) == [3, 4, 5]
    end

    test "Enum.slice/2 uses efficient slice" do
      buf = RingBuffer.new(10) |> RingBuffer.push_many(1..10)
      assert Enum.slice(buf, 3..5) == [4, 5, 6]
    end

    test "Enum.map/2" do
      buf = RingBuffer.new(5) |> RingBuffer.push_many(1..3)
      assert Enum.map(buf, &(&1 * 2)) == [2, 4, 6]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into/2" do
      buf = Enum.into([:a, :b, :c], RingBuffer.new(5))
      assert RingBuffer.to_list(buf) == [:a, :b, :c]
    end

    test "Enum.into/2 respects max size" do
      buf = Enum.into(1..10, RingBuffer.new(3))
      assert RingBuffer.to_list(buf) == [8, 9, 10]
    end
  end
end
