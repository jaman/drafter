defmodule Drafter.Render.WriterTest do
  use ExUnit.Case, async: true

  alias Drafter.Render.Writer

  defmodule Sink do
    def start(delay_ms), do: Agent.start_link(fn -> {delay_ms, []} end)

    def write(pid, bytes) do
      {delay, _} = Agent.get(pid, & &1)
      if delay > 0, do: Process.sleep(delay)
      Agent.update(pid, fn {d, writes} -> {d, [IO.iodata_to_binary(bytes) | writes]} end)
    end

    def writes(pid), do: pid |> Agent.get(fn {_, writes} -> writes end) |> Enum.reverse()
  end

  test "writes reach the sink whole and in order, and behind? holds until they have" do
    {:ok, sink} = Sink.start(20)
    {:ok, writer} = Writer.start_link(&Sink.write(sink, &1))

    for n <- 1..4, do: Writer.write(writer, ["frame", Integer.to_string(n)])
    assert Writer.behind?(writer)

    Writer.flush(writer)

    refute Writer.behind?(writer)
    assert Sink.writes(sink) == for(n <- 1..4, do: "frame#{n}")
  end
end
