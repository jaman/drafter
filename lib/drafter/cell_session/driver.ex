defmodule Drafter.CellSession.Driver do
  @moduledoc """
  A terminal driver that holds a size and discards ANSI output.

  `Drafter.CellSession` reads the composited cell grid straight from the Compositor's
  buffer, so the encoded ANSI stream is not needed — this driver satisfies the
  Compositor's `write/2` + `get_size/1` contract while throwing the bytes away, and
  lets the session resize the virtual surface.
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
