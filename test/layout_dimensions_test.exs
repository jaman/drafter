defmodule Drafter.LayoutDimensionsTest do
  use ExUnit.Case, async: true

  alias Drafter.Layout

  @rect %{x: 0, y: 0, width: 100, height: 40}

  defp input(opts), do: {:text_input, opts}
  defp heights(sizes), do: Enum.map(sizes, & &1.height)
  defp widths(sizes), do: Enum.map(sizes, & &1.width)

  defp vertical(children, opts \\ []) do
    Layout.calculate_vertical_layout(children, @rect, opts, nil)
  end

  defp horizontal(children) do
    opts = [children_opts: Enum.map(children, &Layout.component_opts/1)]
    Layout.calculate_horizontal_layout(children, @rect, opts)
  end

  describe "resolve_dimension" do
    test "an integer is a cell count" do
      assert Layout.resolve_dimension(12, 100, :auto) == 12
    end

    test "a percentage is a share of the available space" do
      assert Layout.resolve_dimension({:percent, 50}, 100, :auto) == 50
      assert Layout.resolve_dimension({:percent, 25}, 40, :auto) == 10
      assert Layout.resolve_dimension({:percent, 33}, 100, :auto) == 33
    end

    test "auto and nil defer to the fallback" do
      assert Layout.resolve_dimension(:auto, 100, 7) == 7
      assert Layout.resolve_dimension(nil, 100, 7) == 7
    end

    test "fractional units defer until the flex pass" do
      assert Layout.resolve_dimension({:fr, 2}, 100, 3) == 3
    end
  end

  describe "clamp_size" do
    test "min raises an undersized value" do
      assert Layout.clamp_size(2, [min_height: 5], :height) == 5
      assert Layout.clamp_size(2, [min_width: 5], :width) == 5
    end

    test "max lowers an oversized value" do
      assert Layout.clamp_size(90, [max_height: 10], :height) == 10
      assert Layout.clamp_size(90, [max_width: 10], :width) == 10
    end

    test "min and max together bracket the value" do
      assert Layout.clamp_size(1, [min_height: 4, max_height: 8], :height) == 4
      assert Layout.clamp_size(99, [min_height: 4, max_height: 8], :height) == 8
      assert Layout.clamp_size(6, [min_height: 4, max_height: 8], :height) == 6
    end

    test "absent constraints leave the value alone" do
      assert Layout.clamp_size(6, [], :height) == 6
    end
  end

  describe "vertical layout" do
    test "percentage heights resolve against the container" do
      sizes = vertical([input(height: {:percent, 25}), input(height: {:percent, 50})])
      assert heights(sizes) == [10, 20]
    end

    test "min_height raises a child that asked for less" do
      sizes = vertical([input(height: 1, min_height: 6), input(height: 4)])
      assert heights(sizes) == [6, 4]
    end

    test "max_height caps a child that asked for more" do
      sizes = vertical([input(height: 30, max_height: 8), input(height: 4)])
      assert heights(sizes) == [8, 4]
    end

    test "fractional units share the remaining space" do
      sizes = vertical([input(height: 10), input(height: {:fr, 1}), input(height: {:fr, 2})])
      [fixed, one, two] = heights(sizes)

      assert fixed == 10
      assert one + two == 30
      assert two > one
    end
  end

  describe "horizontal layout" do
    test "percentage widths resolve against the container" do
      sizes =
        horizontal([input(width: {:percent, 20}), input(width: {:percent, 30}), input(flex: 1)])

      [a, b, rest] = widths(sizes)

      assert a == 20
      assert b == 30
      assert rest == 50
    end

    test "min_width raises a child that asked for less" do
      sizes = horizontal([input(width: 2, min_width: 10), input(flex: 1)])
      assert hd(widths(sizes)) == 10
    end

    test "max_width caps a child that asked for more" do
      sizes = horizontal([input(width: 80, max_width: 25), input(flex: 1)])
      assert hd(widths(sizes)) == 25
    end

    test "children keep their declared order" do
      sizes = horizontal([input(width: 10), input(width: 20), input(width: 30)])
      assert widths(sizes) == [10, 20, 30]
      assert Enum.map(sizes, & &1.x) == [0, 10, 30]
    end
  end

  describe "margin" do
    test "a single value applies to every side" do
      assert Layout.get_margin(margin: 2) == {2, 2, 2, 2}
    end

    test "a pair is vertical then horizontal" do
      assert Layout.get_margin(margin: {1, 4}) == {1, 4, 1, 4}
    end

    test "applying a margin insets the rect on all sides" do
      inset = Layout.apply_margin(@rect, {1, 2, 3, 4})

      assert inset == %{x: 4, y: 1, width: 94, height: 36}
    end

    test "an absent margin is zero" do
      assert Layout.get_margin([]) == {0, 0, 0, 0}
    end
  end
end
