defmodule Drafter.Widget.RichLogTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.RingBuffer
  alias Drafter.Widget.RichLog

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp texts(strips), do: Enum.map(strips, &(&1 |> strip_text() |> String.trim_trailing()))

  defp strip_text(strip), do: Enum.map_join(strip.segments, & &1.text)

  describe "mount" do
    test "accepts the plain string form the moduledoc documents" do
      state = RichLog.mount(%{lines: ["one", "two"]})

      assert texts(RichLog.render(state, rect(20, 4))) == ["one", "two", "", ""]
    end

    test "accepts the annotated tuple form" do
      state = RichLog.mount(%{lines: [{"warn", %{color: {255, 0, 0}}}]})

      assert "warn" in texts(RichLog.render(state, rect(20, 2)))
    end

    test "keeps the newest lines when more than max_lines are given" do
      state = RichLog.mount(%{lines: Enum.map(1..10, &"line #{&1}"), max_lines: 3})

      assert texts(RichLog.render(state, rect(20, 3))) == ["line 8", "line 9", "line 10"]
    end
  end

  describe "update" do
    test "a growing lines prop reaches the widget" do
      state = RichLog.mount(%{lines: []})
      state = RichLog.update(%{lines: ["alpha", "beta"]}, state)

      assert texts(RichLog.render(state, rect(20, 2))) == ["alpha", "beta"]
    end

    test "an omitted lines prop leaves the existing content alone" do
      state = RichLog.mount(%{lines: ["kept"]})
      state = RichLog.update(%{wrap: false}, state)

      assert texts(RichLog.render(state, rect(20, 1))) == ["kept"]
    end

    test "update honours max_lines" do
      state = RichLog.mount(%{lines: [], max_lines: 2})
      state = RichLog.update(%{lines: ["a", "b", "c"]}, state)

      assert texts(RichLog.render(state, rect(20, 2))) == ["b", "c"]
    end
  end

  describe "render" do
    test "each visible line gets its own strip" do
      state = RichLog.mount(%{lines: ["alpha", "beta", "gamma"]})

      assert texts(RichLog.render(state, rect(40, 3))) == ["alpha", "beta", "gamma"]
    end

    test "every strip is exactly the rect width" do
      state = RichLog.mount(%{lines: ["alpha", "beta", "gamma"]})

      for strip <- RichLog.render(state, rect(40, 5)) do
        assert Strip.width(strip) == 40
      end
    end

    test "the strip count always fills the rect height" do
      for line_count <- [0, 1, 3, 20] do
        state = RichLog.mount(%{lines: Enum.map(1..line_count//1, &"line #{&1}")})

        assert length(RichLog.render(state, rect(30, 6))) == 6
      end
    end

    test "a wrapped line occupies as many rows as it needs" do
      state = RichLog.mount(%{lines: ["aaaa bbbb cccc dddd"], wrap: true})
      strips = RichLog.render(state, rect(10, 4))

      assert length(strips) == 4
      assert texts(strips) |> Enum.reject(&(&1 == "")) |> length() > 1
    end

    test "wrapping off truncates instead of spilling rows" do
      state = RichLog.mount(%{lines: ["aaaa bbbb cccc dddd"], wrap: false})
      strips = RichLog.render(state, rect(10, 3))

      assert length(strips) == 3
      assert Enum.all?(strips, &(Strip.width(&1) == 10))
    end

    test "wrapped rows overflowing the rect keep the newest rows" do
      state = RichLog.mount(%{lines: ["first", "a bb ccc dddd eeeee ffffff"], wrap: true})
      shown = texts(RichLog.render(state, rect(8, 3)))

      assert length(shown) == 3
      assert "ffffff" in shown
      refute "first" in shown
    end

    test "more lines than fit shows the newest ones" do
      state = RichLog.mount(%{lines: Enum.map(1..10, &"line #{&1}")})

      assert texts(RichLog.render(state, rect(20, 3))) == ["line 8", "line 9", "line 10"]
    end
  end

  describe "streaming" do
    test "a write event appends a line" do
      state = RichLog.mount(%{lines: []})
      {:ok, state} = RichLog.handle_event({:write, "hello"}, state)

      assert "hello" in texts(RichLog.render(state, rect(20, 2)))
    end

    test "push_data applies the buffer" do
      state = RichLog.mount(%{lines: [], max_lines: 100})
      buffer = Enum.reduce(1..5, RingBuffer.new(100), &RingBuffer.push(&2, "line #{&1}"))

      state = RichLog.apply_data_buffer(state, buffer, rect(20, 3))

      assert texts(RichLog.render(state, rect(20, 3))) == ["line 3", "line 4", "line 5"]
    end

    test "push_data keeps scrollback beyond the visible height" do
      state = RichLog.mount(%{lines: [], max_lines: 100})
      buffer = Enum.reduce(1..50, RingBuffer.new(100), &RingBuffer.push(&2, "line #{&1}"))

      state = RichLog.apply_data_buffer(state, buffer, rect(20, 3))

      assert length(state.lines) == 50
    end
  end
end
