defmodule Drafter.Terminal.DriverProbeTest do
  @moduledoc """
  Asking the local driver what the terminal supports.

  The probe writes to the terminal and waits for its answer, so a driver with no
  terminal to ask must say so at once. Parking the caller instead takes the whole
  application down on the `GenServer.call` timeout, and takes it down during
  startup, before anything is in place to put the terminal back the way it was.
  """

  use ExUnit.Case, async: false

  alias Drafter.Terminal.Driver

  setup do
    case Driver.start_link() do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  test "a driver with no terminal reports it was never asked" do
    assert Driver.probe() == :unprobed
  end

  test "and does so immediately, rather than waiting out the deadline" do
    {elapsed, result} = :timer.tc(fn -> Driver.probe(1_000) end)

    assert result == :unprobed
    assert elapsed < 250_000, "took #{div(elapsed, 1000)}ms to say there was nothing to ask"
  end

  test "asking twice is harmless" do
    assert Driver.probe() == :unprobed
    assert Driver.probe() == :unprobed
  end

  test "a driver that is not running reports it was never asked rather than raising" do
    case Process.whereis(Driver) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    assert Driver.probe() == :unprobed
  end
end
