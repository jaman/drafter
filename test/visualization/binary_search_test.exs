defmodule Drafter.Visualization.BinarySearchTest do
  use ExUnit.Case, async: true

  alias Drafter.Visualization.BinarySearch

  describe "find_range/3" do
    test "returns correct indices for range in middle" do
      list = [1, 3, 5, 7, 9, 11, 13, 15]
      assert {2, 5} = BinarySearch.find_range(list, 5, 11)
    end

    test "returns correct indices for range at start" do
      list = [1, 3, 5, 7, 9]
      assert {0, 1} = BinarySearch.find_range(list, 1, 3)
    end

    test "returns correct indices for range at end" do
      list = [1, 3, 5, 7, 9]
      assert {3, 4} = BinarySearch.find_range(list, 7, 9)
    end

    test "returns correct indices for exact boundary values" do
      list = [10, 20, 30, 40, 50]
      assert {1, 3} = BinarySearch.find_range(list, 20, 40)
    end

    test "returns {0, -1} for empty list" do
      assert {0, -1} = BinarySearch.find_range([], 1, 10)
    end

    test "handles single element within range" do
      assert {0, 0} = BinarySearch.find_range([5], 1, 10)
    end

    test "handles single element outside range" do
      assert {0, -1} = BinarySearch.find_range([5], 10, 20)
    end

    test "returns {0, -1} when min > max" do
      list = [1, 2, 3, 4, 5]
      assert {0, -1} = BinarySearch.find_range(list, 10, 5)
    end

    test "returns {0, -1} when range is entirely above data" do
      list = [1, 2, 3, 4, 5]
      assert {0, -1} = BinarySearch.find_range(list, 10, 20)
    end

    test "returns {0, -1} when range is entirely below data" do
      list = [10, 20, 30, 40, 50]
      assert {0, -1} = BinarySearch.find_range(list, 1, 5)
    end

    test "handles range covering all elements" do
      list = [1, 2, 3, 4, 5]
      assert {0, 4} = BinarySearch.find_range(list, 0, 10)
    end

    test "handles range with values between elements" do
      list = [10, 20, 30, 40, 50]
      assert {1, 3} = BinarySearch.find_range(list, 15, 45)
    end
  end
end
