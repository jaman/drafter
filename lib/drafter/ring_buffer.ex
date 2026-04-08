defmodule Drafter.RingBuffer do
  @moduledoc """
  Bounded circular buffer backed by an integer-keyed map.

  Provides O(1) push, O(1) single-element access, and O(k) slice reads
  where k is the requested slice length — without materializing the full buffer.
  When the buffer is full, the oldest entry is overwritten.
  """

  defstruct store: %{}, max_size: 0, count: 0, write_pos: 0

  @type t :: %__MODULE__{
          store: %{non_neg_integer() => term()},
          max_size: pos_integer(),
          count: non_neg_integer(),
          write_pos: non_neg_integer()
        }

  @spec new(pos_integer()) :: t()
  def new(max_size) when is_integer(max_size) and max_size > 0 do
    %__MODULE__{max_size: max_size}
  end

  @spec push(t(), term()) :: t()
  def push(%__MODULE__{} = buf, item) do
    store = Map.put(buf.store, buf.write_pos, item)
    count = min(buf.count + 1, buf.max_size)
    write_pos = rem(buf.write_pos + 1, buf.max_size)
    %{buf | store: store, count: count, write_pos: write_pos}
  end

  @spec push_many(t(), Enumerable.t()) :: t()
  def push_many(%__MODULE__{} = buf, items) do
    Enum.reduce(items, buf, &push(&2, &1))
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @spec max_size(t()) :: pos_integer()
  def max_size(%__MODULE__{max_size: max_size}), do: max_size

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{count: 0}), do: true
  def empty?(%__MODULE__{}), do: false

  @spec at(t(), non_neg_integer()) :: term() | nil
  def at(%__MODULE__{count: count}, index) when index >= count, do: nil

  def at(%__MODULE__{} = buf, index) do
    pos = read_pos(buf, index)
    Map.get(buf.store, pos)
  end

  @spec last(t()) :: term() | nil
  def last(%__MODULE__{count: 0}), do: nil

  def last(%__MODULE__{} = buf) do
    pos = rem(buf.write_pos - 1 + buf.max_size, buf.max_size)
    Map.get(buf.store, pos)
  end

  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [term()]
  def slice(%__MODULE__{}, _offset, 0), do: []

  def slice(%__MODULE__{} = buf, offset, length) when offset >= 0 and length > 0 do
    actual_length = min(length, max(0, buf.count - offset))

    if actual_length <= 0 do
      []
    else
      for i <- 0..(actual_length - 1) do
        pos = read_pos(buf, offset + i)
        Map.fetch!(buf.store, pos)
      end
    end
  end

  @spec last_n(t(), non_neg_integer()) :: [term()]
  def last_n(%__MODULE__{}, 0), do: []

  def last_n(%__MODULE__{} = buf, n) when n > 0 do
    take = min(n, buf.count)
    offset = buf.count - take
    slice(buf, offset, take)
  end

  @spec to_list(t()) :: [term()]
  def to_list(%__MODULE__{} = buf), do: slice(buf, 0, buf.count)

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
