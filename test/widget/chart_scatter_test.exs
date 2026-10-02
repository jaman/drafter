defmodule Drafter.Widget.ChartScatterTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.Chart

  @rect %{x: 0, y: 0, width: 40, height: 10}

  setup do
    case Drafter.ThemeManager.start_link() do
      {:ok, pid} -> Process.put(:drafter_theme_manager, pid)
      {:error, {:already_started, pid}} -> Process.put(:drafter_theme_manager, pid)
    end

    :ok
  end

  defp rendered?(type, data) do
    state = Chart.mount(%{data: data, chart_type: type, renderer: :kitty})

    case Chart.image(state, @rect, :probe) do
      nil -> false
      {paint, _clear, _geom} -> IO.iodata_length(paint) > 0
    end
  end

  defp fingerprint(type, data) do
    state = Chart.mount(%{data: data, chart_type: type, renderer: :kitty})
    {paint, _, _} = Chart.image(state, @rect, :probe)
    :crypto.hash(:sha, IO.iodata_to_binary(paint))
  end

  describe "scatter accepts the shapes callers actually pass" do
    test "a plain series of numbers is indexed by position" do
      assert rendered?(:scatter, [1, 5, 3, 8, 6])
    end

    test "{x, y} tuples" do
      assert rendered?(:scatter, [{1, 2}, {2, 5}, {3, 3}])
    end

    test "[x, y] pairs" do
      assert rendered?(:scatter, [[1, 2], [2, 5], [3, 3]])
    end

    test "%{x: x, y: y} maps" do
      assert rendered?(:scatter, [%{x: 1, y: 2}, %{x: 2, y: 5}, %{x: 3, y: 3}])
    end

    test "an empty series produces no image rather than a blank one" do
      refute rendered?(:scatter, [])
    end
  end

  describe "candlestick" do
    test "renders from ohlc lists" do
      assert rendered?(:candlestick, [[10, 15, 8, 12], [12, 18, 11, 17]])
    end
  end

  describe "a live candlestick series advances" do
    defp series(count, seed \\ 0) do
      Enum.map(1..count, fn i ->
        base = 100 + :math.sin((i + seed) / 5) * 10
        [base, base + 2, base - 2, base + 1]
      end)
    end

    test "the plot follows the newest candles, not the oldest" do
      padded = series(400)
      capacity = div(@rect.width * 4, 3)

      assert fingerprint(:candlestick, padded) ==
               fingerprint(:candlestick, Enum.take(padded, -capacity)),
             "an overflowing series should plot only the candles that fit at the right edge"

      refute fingerprint(:candlestick, padded) ==
               fingerprint(:candlestick, Enum.take(padded, capacity)),
             "plotting the oldest candles would leave the chart stuck as new ones arrive"
    end
  end
end
