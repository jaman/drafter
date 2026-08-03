defmodule Drafter.Terminal.DriverInputTest do
  use ExUnit.Case, async: false

  alias Drafter.Terminal.Driver

  defmodule StubEventManager do
    @moduledoc false
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

    @impl true
    def init(owner), do: {:ok, owner}

    @impl true
    def handle_cast({:event, event}, owner) do
      send(owner, {:emitted, event})
      {:noreply, owner}
    end
  end

  setup do
    {:ok, stub} = StubEventManager.start_link(self())

    stop_driver()
    {:ok, driver} = Driver.start_link(event_manager: stub)
    on_exit(fn -> stop_quietly(driver) end)

    {:ok, driver: driver}
  end

  defp stop_driver do
    case GenServer.whereis(Driver) do
      nil -> :ok
      pid -> stop_quietly(pid)
    end
  end

  defp stop_quietly(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp type(driver, binary) do
    for <<byte <- binary>>, do: send(driver, {:stdin, <<byte>>})
    :ok
  end

  defp collect(timeout \\ 300) do
    receive do
      {:emitted, event} -> [event | collect(timeout)]
    after
      timeout -> []
    end
  end

  test "plain characters typed one byte at a time reach the event manager", %{driver: driver} do
    type(driver, "hello")
    assert collect() == [key: :h, key: :e, key: :l, key: :l, key: :o]
  end

  test "control characters are delivered", %{driver: driver} do
    type(driver, "\x03")
    assert collect() == [{:key, :c, [:ctrl]}]
  end

  test "carriage return is delivered as enter", %{driver: driver} do
    type(driver, "\r")
    assert collect() == [key: :enter]
  end

  test "an arrow key typed one byte at a time arrives as a single key event", %{driver: driver} do
    type(driver, "\e[A")
    assert collect() == [key: :up]
  end

  test "a bare escape is delivered after the flush timeout", %{driver: driver} do
    type(driver, "\e")
    assert collect() == [key: :escape]
  end

  test "a paste typed one byte at a time arrives as one paste event", %{driver: driver} do
    type(driver, "\e[200~select 1\e[201~")
    assert collect() == [bracketed_paste: "select 1"]
  end

  test "typing continues to work after a paste", %{driver: driver} do
    type(driver, "\e[200~x\e[201~ab")
    assert collect() == [{:bracketed_paste, "x"}, {:key, :a}, {:key, :b}]
  end

  test "typing continues to work after a bare escape flushes", %{driver: driver} do
    type(driver, "\e")
    assert collect() == [key: :escape]
    type(driver, "ok")
    assert collect() == [key: :o, key: :k]
  end

  test "a multi-byte utf8 character split across reads arrives once", %{driver: driver} do
    type(driver, "é")
    assert collect() == [char: 233]
  end
end
