defmodule Drafter.Render.WriterTest do
  use ExUnit.Case, async: true

  alias Drafter.Render.Writer

  defmodule Sink do
    def start(delay_ms), do: Agent.start_link(fn -> {delay_ms, []} end)

    def write(pid, bytes) do
      binary = IO.iodata_to_binary(bytes)
      {delay, _} = Agent.get(pid, & &1)
      if delay > 0 and String.contains?(binary, "IMG"), do: Process.sleep(delay)
      Agent.update(pid, fn {d, writes} -> {d, [binary | writes]} end)
    end

    def writes(pid), do: pid |> Agent.get(fn {_, writes} -> writes end) |> Enum.reverse()
  end

  test "text is written in order and never dropped" do
    {:ok, sink} = Sink.start(0)
    {:ok, writer} = Writer.start_link(&Sink.write(sink, &1))
    for n <- 1..20, do: Writer.write(writer, "t#{n}")
    Writer.flush(writer)
    assert Sink.writes(sink) == for(n <- 1..20, do: "t#{n}")
  end

  test "an image is written after the text that preceded it, and stale images are skipped" do
    {:ok, sink} = Sink.start(30)
    {:ok, writer} = Writer.start_link(&Sink.write(sink, &1))

    Writer.write(writer, "t1")
    Writer.write_image(writer, "IMG1")
    Process.sleep(5)

    for n <- 2..6 do
      Writer.write(writer, "t#{n}")
      Writer.write_image(writer, "IMG#{n}")
    end

    Writer.flush(writer)
    writes = Sink.writes(sink)

    assert Enum.filter(writes, &String.starts_with?(&1, "t")) == for(n <- 1..6, do: "t#{n}")
    images = Enum.filter(writes, &String.starts_with?(&1, "IMG"))
    assert List.last(images) == "IMG6"
    assert length(images) < 6
    assert Enum.find_index(writes, &(&1 == "t6")) < Enum.find_index(writes, &(&1 == "IMG6"))
  end

  test "every write is one call to the sink, so bytes of one frame never interleave with another" do
    {:ok, sink} = Sink.start(0)
    {:ok, writer} = Writer.start_link(&Sink.write(sink, &1))
    Writer.write(writer, ["a", "b"])
    Writer.write_image(writer, ["IMG", "x"])
    Writer.flush(writer)
    assert Sink.writes(sink) == ["ab", "IMGx"]
  end
end
