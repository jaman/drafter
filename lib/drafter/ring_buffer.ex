defmodule Drafter.RingBuffer do
  @moduledoc """
  A bounded circular buffer backed by an integer-keyed map.

  Push and single-element access are O(1); a slice is O(k) in the length
  requested, without materializing the whole buffer. Once the buffer is full,
  each push overwrites the oldest entry.

  Implements `Enumerable`, in oldest-to-newest order.

  ## Examples

      iex> buffer = Drafter.RingBuffer.new(3)
      iex> buffer = Drafter.RingBuffer.push_many(buffer, [1, 2, 3, 4])
      iex> Drafter.RingBuffer.to_list(buffer)
      [2, 3, 4]
      iex> Drafter.RingBuffer.count(buffer)
      3
      iex> Drafter.RingBuffer.last(buffer)
      4
      iex> Drafter.RingBuffer.at(buffer, 0)
      2
      iex> Drafter.RingBuffer.last_n(buffer, 2)
      [3, 4]

  """

  defstruct store: %{}, max_size: 0, count: 0, write_pos: 0

  @type t :: %__MODULE__{
          store: %{non_neg_integer() => term()},
          max_size: pos_integer(),
          count: non_neg_integer(),
          write_pos: non_neg_integer()
        }

  @doc """
  An empty buffer holding at most `max_size` items.

  `max_size` must be a positive integer; anything else raises `FunctionClauseError`.

  ## Examples

      iex> buf = Drafter.RingBuffer.new(3)
      iex> Drafter.RingBuffer.count(buf)
      0
      iex> Drafter.RingBuffer.max_size(buf)
      3

  """
  @spec new(pos_integer()) :: t()
  def new(max_size) when is_integer(max_size) and max_size > 0 do
    %__MODULE__{max_size: max_size}
  end

  @doc """
  Append `item`, dropping the oldest item once the buffer is full.

  ## Examples

      iex> Drafter.RingBuffer.new(2) |> Drafter.RingBuffer.push(:a) |> Drafter.RingBuffer.push(:b) |> Drafter.RingBuffer.push(:c) |> Drafter.RingBuffer.to_list()
      [:b, :c]

  """
  @spec push(t(), term()) :: t()
  def push(%__MODULE__{} = buf, item) do
    store = Map.put(buf.store, buf.write_pos, item)
    count = min(buf.count + 1, buf.max_size)
    write_pos = rem(buf.write_pos + 1, buf.max_size)
    %{buf | store: store, count: count, write_pos: write_pos}
  end

  @doc """
  Append every item in `items`, in order.

  Pushing more than `max_size` items keeps only the last `max_size`.

  ## Examples

      iex> Drafter.RingBuffer.new(3) |> Drafter.RingBuffer.push_many([1, 2, 3, 4]) |> Drafter.RingBuffer.to_list()
      [2, 3, 4]

  """
  @spec push_many(t(), Enumerable.t()) :: t()
  def push_many(%__MODULE__{} = buf, items) do
    Enum.reduce(items, buf, &push(&2, &1))
  end

  @doc """
  How many items the buffer currently holds, never more than `max_size/1`.

  ## Examples

      iex> Drafter.RingBuffer.new(2) |> Drafter.RingBuffer.push_many([1, 2, 3]) |> Drafter.RingBuffer.count()
      2

  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @doc """
  The buffer's capacity, as given to `new/1` or `resize/2`.

  ## Examples

      iex> Drafter.RingBuffer.new(5) |> Drafter.RingBuffer.max_size()
      5

  """
  @spec max_size(t()) :: pos_integer()
  def max_size(%__MODULE__{max_size: max_size}), do: max_size

  @doc """
  Whether the buffer holds no items.

  ## Examples

      iex> Drafter.RingBuffer.empty?(Drafter.RingBuffer.new(3))
      true

      iex> Drafter.RingBuffer.new(3) |> Drafter.RingBuffer.push(:a) |> Drafter.RingBuffer.empty?()
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{count: 0}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  The item at `index`, counting `0` as the oldest, or `nil` when out of range.

  ## Examples

      iex> buf = Drafter.RingBuffer.push_many(Drafter.RingBuffer.new(3), [1, 2, 3, 4])
      iex> Drafter.RingBuffer.at(buf, 0)
      2
      iex> Drafter.RingBuffer.at(buf, 2)
      4
      iex> Drafter.RingBuffer.at(buf, 3)
      nil

  """
  @spec at(t(), non_neg_integer()) :: term() | nil
  def at(%__MODULE__{count: count}, index) when index >= count, do: nil

  def at(%__MODULE__{} = buf, index) do
    pos = read_pos(buf, index)
    Map.get(buf.store, pos)
  end

  @doc """
  The most recently pushed item, or `nil` when the buffer is empty.

  ## Examples

      iex> Drafter.RingBuffer.new(3) |> Drafter.RingBuffer.push_many([1, 2]) |> Drafter.RingBuffer.last()
      2

      iex> Drafter.RingBuffer.last(Drafter.RingBuffer.new(3))
      nil

  """
  @spec last(t()) :: term() | nil
  def last(%__MODULE__{count: 0}), do: nil

  def last(%__MODULE__{} = buf) do
    pos = rem(buf.write_pos - 1 + buf.max_size, buf.max_size)
    Map.get(buf.store, pos)
  end

  @doc """
  `length` items starting at `offset`, oldest first.

  A slice that runs past the end is truncated rather than padded. `offset` must be
  non-negative; a negative one raises `FunctionClauseError`.

  ## Examples

      iex> buf = Drafter.RingBuffer.push_many(Drafter.RingBuffer.new(5), [1, 2, 3, 4, 5])
      iex> Drafter.RingBuffer.slice(buf, 1, 3)
      [2, 3, 4]
      iex> Drafter.RingBuffer.slice(buf, 3, 10)
      [4, 5]
      iex> Drafter.RingBuffer.slice(buf, 0, 0)
      []

  """
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [term()]
  def slice(%__MODULE__{}, _offset, 0), do: []

  def slice(%__MODULE__{} = buf, offset, length) when offset >= 0 and length > 0 do
    actual_length = min(length, max(0, buf.count - offset))

    if actual_length <= 0 do
      []
    else
      for i <- 0..(actual_length - 1)//1 do
        pos = read_pos(buf, offset + i)
        Map.fetch!(buf.store, pos)
      end
    end
  end

  @doc """
  The newest `n` items, oldest first, or all of them when the buffer holds fewer.

  ## Examples

      iex> buf = Drafter.RingBuffer.push_many(Drafter.RingBuffer.new(5), [1, 2, 3, 4])
      iex> Drafter.RingBuffer.last_n(buf, 2)
      [3, 4]
      iex> Drafter.RingBuffer.last_n(buf, 10)
      [1, 2, 3, 4]
      iex> Drafter.RingBuffer.last_n(buf, 0)
      []

  """
  @spec last_n(t(), non_neg_integer()) :: [term()]
  def last_n(%__MODULE__{}, 0), do: []

  def last_n(%__MODULE__{} = buf, n) when n > 0 do
    take = min(n, buf.count)
    offset = buf.count - take
    slice(buf, offset, take)
  end

  @doc """
  Every item, oldest first.

  ## Examples

      iex> Drafter.RingBuffer.new(3) |> Drafter.RingBuffer.push_many([1, 2, 3, 4]) |> Drafter.RingBuffer.to_list()
      [2, 3, 4]

  """
  @spec to_list(t()) :: [term()]
  def to_list(%__MODULE__{} = buf), do: slice(buf, 0, buf.count)

  @doc """
  A buffer with capacity `new_max`, keeping the newest items that still fit.

  Shrinking discards the oldest items; growing keeps everything.

  ## Examples

      iex> buf = Drafter.RingBuffer.push_many(Drafter.RingBuffer.new(5), [1, 2, 3, 4, 5])
      iex> Drafter.RingBuffer.resize(buf, 2) |> Drafter.RingBuffer.to_list()
      [4, 5]

      iex> buf = Drafter.RingBuffer.push_many(Drafter.RingBuffer.new(2), [1, 2])
      iex> Drafter.RingBuffer.resize(buf, 4) |> Drafter.RingBuffer.to_list()
      [1, 2]

  """
  @spec resize(t(), pos_integer()) :: t()
  def resize(%__MODULE__{} = buf, new_max) when is_integer(new_max) and new_max > 0 do
    items = to_list(buf)
    kept = Enum.take(items, -new_max)

    kept
    |> Enum.with_index()
    |> Enum.reduce(%__MODULE__{max_size: new_max}, fn {item, idx}, acc ->
      %{acc | store: Map.put(acc.store, idx, item), count: idx + 1, write_pos: idx + 1}
    end)
    |> then(fn b -> %{b | write_pos: rem(b.write_pos, new_max)} end)
  end

  defp read_pos(%__MODULE__{} = buf, index) do
    start = rem(buf.write_pos - buf.count + buf.max_size, buf.max_size)
    rem(start + index, buf.max_size)
  end
end

defimpl Enumerable, for: Drafter.RingBuffer do
  def count(buf), do: {:ok, Drafter.RingBuffer.count(buf)}

  def member?(buf, element) do
    {:ok, Enum.any?(Drafter.RingBuffer.to_list(buf), &(&1 == element))}
  end

  def reduce(buf, acc, fun) do
    Enumerable.List.reduce(Drafter.RingBuffer.to_list(buf), acc, fun)
  end

  def slice(buf) do
    size = Drafter.RingBuffer.count(buf)

    slicer = fn start, length, _step ->
      Drafter.RingBuffer.slice(buf, start, length)
    end

    {:ok, size, slicer}
  end
end

defimpl Collectable, for: Drafter.RingBuffer do
  def into(buf) do
    collector = fn
      acc, {:cont, item} -> Drafter.RingBuffer.push(acc, item)
      acc, :done -> acc
      _acc, :halt -> :ok
    end

    {buf, collector}
  end
end
