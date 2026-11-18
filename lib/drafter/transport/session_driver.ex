defmodule Drafter.Transport.SessionDriver do
  @moduledoc false
  # A wedged peer must not block its caller for ever.
  @call_timeout 30_000

  @spec write(pid(), iodata()) :: :ok
  def write(driver_pid, data),
    do: GenServer.call(driver_pid, {:driver_write, data}, @call_timeout)

  @spec get_size(pid()) :: {pos_integer(), pos_integer()}
  def get_size(driver_pid), do: GenServer.call(driver_pid, :driver_get_size)

  @spec set_event_manager(pid(), pid()) :: :ok
  def set_event_manager(driver_pid, em_pid),
    do: GenServer.cast(driver_pid, {:set_event_manager, em_pid})
end
