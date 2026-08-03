defmodule Drafter.CellSession.Driver do
  @moduledoc """
  A terminal driver that holds a screen size and discards everything written to it.

  Satisfies the `write/2` and `get_size/1` contract `Drafter.Compositor` requires of
  a terminal driver. `Drafter.CellSession` reads the composited cell grid out of the
  compositor's buffer directly and never needs the encoded ANSI stream, so the bytes
  passed to `write/2` are dropped. `set_size/2` resizes the virtual surface.
  """

  use GenServer

  @spec start_link({pos_integer(), pos_integer()}) :: GenServer.on_start()
  def start_link(size), do: GenServer.start_link(__MODULE__, size)

  @spec write(pid(), iodata()) :: :ok
  def write(_pid, _data), do: :ok

  @spec get_size(pid()) :: {pos_integer(), pos_integer()}
  def get_size(pid), do: GenServer.call(pid, :get_size)

  @spec set_size(pid(), {pos_integer(), pos_integer()}) :: :ok
  def set_size(pid, size), do: GenServer.call(pid, {:set_size, size})

  @impl true
  def init(size), do: {:ok, size}

  @impl true
  def handle_call(:get_size, _from, size), do: {:reply, size, size}
  def handle_call({:set_size, new_size}, _from, _size), do: {:reply, :ok, new_size}
end
