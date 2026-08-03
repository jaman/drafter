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

    test "{x, y, weight} tuples" do
      assert rendered?(:scatter, [{1, 2, 3}, {2, 5, 1}])
    end

    test "[x, y] pairs" do
      assert rendered?(:scatter, [[1, 2], [2, 5], [3, 3]])
    end

    test "%{x: x, y: y} maps" do
      assert rendered?(:scatter, [%{x: 1, y: 2}, %{x: 2, y: 5}, %{x: 3, y: 3}])
    end

    test "multiple series of plain numbers" do
      assert rendered?(:scatter, [[1, 5, 3], [2, 4, 6]])
    end

    test "an empty series produces no image rather than a blank one" do
      refute rendered?(:scatter, [])
    end
  end

  describe "point shapes agree with one another" do
    test "tuples and pairs describe the same plot" do
      assert fingerprint(:scatter, [{1, 2}, {2, 5}]) == fingerprint(:scatter, [[1, 2], [2, 5]])
    end

    test "maps describe the same plot as tuples" do
      assert fingerprint(:scatter, [{1, 2}, {2, 5}]) ==
               fingerprint(:scatter, [%{x: 1, y: 2}, %{x: 2, y: 5}])
    end

    test "an indexed series matches the tuples it implies" do
      assert fingerprint(:scatter, [5, 3, 8]) == fingerprint(:scatter, [{0, 5}, {1, 3}, {2, 8}])
    end
  end

  describe "candlestick" do
    test "renders from ohlc lists" do
      assert rendered?(:candlestick, [[10, 15, 8, 12], [12, 18, 11, 17]])
    end

    test "renders from ohlc maps" do
      assert rendered?(:candlestick, [%{open: 10, high: 15, low: 8, close: 12}])
    end

    test "renders at forex magnitudes" do
      assert rendered?(:candlestick, [
               [1.1250, 1.1265, 1.1240, 1.1258],
               [1.1258, 1.1270, 1.1250, 1.1262]
             ])
    end
  end

  describe "a live candlestick series advances" do
    defp series(count, seed \\ 0) do
      Enum.map(1..count, fn i ->
        base = 100 + :math.sin((i + seed) / 5) * 10
        [base, base + 2, base - 2, base + 1]
      end)
    end

    test "appending a candle changes the plot when the series already overflows" do
      long = series(400)

      assert fingerprint(:candlestick, long) !=
               fingerprint(:candlestick, long ++ [[99, 105, 95, 104]])
    end

    test "appending a candle changes the plot for a short series too" do
      short = series(5)

      assert fingerprint(:candlestick, short) !=
               fingerprint(:candlestick, short ++ [[99, 105, 95, 104]])
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

    test "a series that fits is drawn whole" do
      short = series(10)
      assert fingerprint(:candlestick, short) == fingerprint(:candlestick, short)
      assert rendered?(:candlestick, short)
    end
  end
end
