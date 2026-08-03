defmodule Drafter.Widget.Slider.Scale do
  @moduledoc """
  Value arithmetic for `Drafter.Widget.Slider`.

  Every function takes the slider's bounds as `min_value`, `max_value` and a `step`
  that may be `nil`, and returns a value inside those bounds. A range whose bounds
  and step are all integers keeps integer values; any other range works in floats,
  rounded to the decimals the step implies so that repeated stepping does not
  accumulate float error.

  A `nil` step means "continuous", which is still quantised: `step_size/3` supplies
  a hundredth of the range as the working step, whole numbers for an integer range.
  """

  @max_decimals 6

  @doc """
  Whether the range works in integers.

  True when `min_value`, `max_value` and `step` are all integers; a `nil` step counts
  as integral when both bounds are.

      iex> Drafter.Widget.Slider.Scale.integral?(0, 10, 1)
      true

      iex> Drafter.Widget.Slider.Scale.integral?(0.0, 1.0, nil)
      false
  """
  @spec integral?(number(), number(), number() | nil) :: boolean()
  def integral?(min_value, max_value, nil), do: is_integer(min_value) and is_integer(max_value)

  def integral?(min_value, max_value, step),
    do: is_integer(min_value) and is_integer(max_value) and is_integer(step)

  @doc """
  The working step for a range.

  An explicit `step` is returned as given. A `nil` step becomes a hundredth of the
  range, rounded up to at least `1` when the range is integral.

      iex> Drafter.Widget.Slider.Scale.step_size(0.0, 1.0, nil)
      0.01

      iex> Drafter.Widget.Slider.Scale.step_size(0, 3, nil)
      1

      iex> Drafter.Widget.Slider.Scale.step_size(0.0, 1.0, 0.25)
      0.25
  """
  @spec step_size(number(), number(), number() | nil) :: number()
  def step_size(min_value, max_value, nil) do
    span = max_value - min_value

    if integral?(min_value, max_value, nil) do
      Kernel.max(1, round(span / 100))
    else
      span / 100
    end
  end

  def step_size(_min_value, _max_value, step), do: step

  @doc """
  `value` held inside `min_value..max_value`.

      iex> Drafter.Widget.Slider.Scale.clamp(1.5, 0.0, 1.0)
      1.0
  """
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, min_value, max_value) do
    value |> Kernel.max(min_value) |> Kernel.min(max_value)
  end

  @doc """
  Where `value` sits in the range, as `0.0` at `min_value` through `1.0` at
  `max_value`.

  Values outside the range come back clamped, and a range with no span reads as
  `0.0`.

      iex> Drafter.Widget.Slider.Scale.fraction(50, 0, 100)
      0.5

      iex> Drafter.Widget.Slider.Scale.fraction(5, 5, 5)
      0.0
  """
  @spec fraction(number(), number(), number()) :: float()
  def fraction(_value, min_value, max_value) when max_value <= min_value, do: 0.0

  def fraction(value, min_value, max_value) do
    (clamp(value, min_value, max_value) - min_value) / (max_value - min_value)
  end

  @doc """
  `value` moved onto the nearest step from `min_value` and clamped into the range.

  A `nil` or non-positive step clamps only.

      iex> Drafter.Widget.Slider.Scale.snap(0.37, 0.0, 1.0, 0.25)
      0.25

      iex> Drafter.Widget.Slider.Scale.snap(2.6, 0, 10, 1)
      3
  """
  @spec snap(number(), number(), number(), number() | nil) :: number()
  def snap(value, min_value, max_value, step) when is_number(step) and step > 0 do
    steps = round((value - min_value) / step)
    quantize(min_value + steps * step, min_value, max_value, step)
  end

  def snap(value, min_value, max_value, _step), do: clamp(value, min_value, max_value)

  @doc """
  The value at `fraction` of the way through the range, snapped to the working step.

      iex> Drafter.Widget.Slider.Scale.value_at(0.5, 0, 100, nil)
      50

      iex> Drafter.Widget.Slider.Scale.value_at(0.42, 0.0, 1.0, 0.25)
      0.5
  """
  @spec value_at(number(), number(), number(), number() | nil) :: number()
  def value_at(fraction, min_value, max_value, step) do
    position = clamp(fraction, 0.0, 1.0)

    snap(
      min_value + position * (max_value - min_value),
      min_value,
      max_value,
      step_size(min_value, max_value, step)
    )
  end

  @doc """
  `value` moved `count` steps, stopping at the ends of the range.

  `count` is negative to move down.

      iex> Drafter.Widget.Slider.Scale.nudge(0.5, 0.0, 1.0, 0.1, 1)
      0.6

      iex> Drafter.Widget.Slider.Scale.nudge(0.0, 0.0, 1.0, 0.1, -1)
      0.0
  """
  @spec nudge(number(), number(), number(), number() | nil, integer()) :: number()
  def nudge(value, min_value, max_value, step, count) do
    size = step_size(min_value, max_value, step)
    snap(value + count * size, min_value, max_value, size)
  end

  @doc """
  How many decimals a step needs to be written exactly, up to `#{@max_decimals}`.

      iex> Drafter.Widget.Slider.Scale.decimals(0.25)
      2

      iex> Drafter.Widget.Slider.Scale.decimals(5)
      0
  """
  @spec decimals(number()) :: non_neg_integer()
  def decimals(step) when is_integer(step), do: 0

  def decimals(step) do
    magnitude = abs(step)

    Enum.find(0..@max_decimals, @max_decimals, fn places ->
      scaled = magnitude * :math.pow(10, places)
      abs(scaled - Float.round(scaled)) < 1.0e-9
    end)
  end

  defp quantize(value, min_value, max_value, step) do
    if integral?(min_value, max_value, step) do
      value |> round() |> clamp(min_value, max_value)
    else
      (value * 1.0) |> Float.round(decimals(step)) |> clamp(min_value, max_value)
    end
  end
end
