defmodule Drafter.Widget.DegenerateRectTest do
  @moduledoc """
  Widgets rendered into rects too small to draw in.

  Layout hands out whatever is left, which in a narrow split, a collapsed pane,
  or a small terminal can be one column or none. Rendering into such a rect must
  produce strips that fit it, not raise.
  """

  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.Widget.{Card, Chart, ProgressBar, Rule}

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp fits?(strips, width) do
    Enum.all?(strips, &(Strip.width(&1) <= width))
  end

  describe "chart" do
    test "axes render in a rect too short for tick labels" do
      state = Chart.mount(%{data: [1, 2, 3], type: :line, show_axes: true})

      for height <- 0..6 do
        strips = Chart.render(state, rect(40, height))
        assert fits?(strips, 40), "chart overflowed at height #{height}"
      end
    end

    test "axes render in a narrow rect" do
      state = Chart.mount(%{data: [1, 2, 3], type: :line, show_axes: true})

      for width <- 0..6 do
        assert fits?(Chart.render(state, rect(width, 10)), width),
               "chart overflowed at width #{width}"
      end
    end
  end

  describe "progress bar" do
    test "an indeterminate bar renders with no width to animate in" do
      state = ProgressBar.mount(%{indeterminate: true})

      for width <- 0..4 do
        assert fits?(ProgressBar.render(state, rect(width, 1)), width),
               "progress bar overflowed at width #{width}"
      end
    end

    test "progress below zero does not draw past the rect" do
      state = ProgressBar.mount(%{progress: -50})

      assert fits?(ProgressBar.render(state, rect(30, 1)), 30)
    end

    test "progress above the maximum does not draw past the rect" do
      state = ProgressBar.mount(%{progress: 150})

      assert fits?(ProgressBar.render(state, rect(30, 1)), 30)
    end
  end

  describe "rule" do
    test "a vertical rule renders with no width" do
      state = Rule.mount(%{orientation: :vertical})

      for width <- 0..3 do
        assert fits?(Rule.render(state, rect(width, 5)), width),
               "rule overflowed at width #{width}"
      end
    end

    test "a horizontal rule renders with no height" do
      state = Rule.mount(%{orientation: :horizontal})

      assert fits?(Rule.render(state, rect(20, 0)), 20)
    end
  end

  describe "card" do
    test "a card renders narrower than its own border" do
      state = Card.mount(%{content: "x"})

      for width <- 0..4 do
        assert fits?(Card.render(state, rect(width, 5)), width),
               "card overflowed at width #{width}"
      end
    end

    test "a card renders shorter than its own border" do
      state = Card.mount(%{content: "x"})

      for height <- 0..3 do
        assert fits?(Card.render(state, rect(20, height)), 20)
      end
    end
  end
end
