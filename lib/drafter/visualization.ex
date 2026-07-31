defmodule Drafter.Visualization do
  @moduledoc """
  Numeric helpers shared across Drafter widgets for data visualization.

  Covers value normalization, scaling, range calculation, zone lookup,
  string duplication, and color cycling — everything widgets need to
  convert raw data into rendered characters.
  """

  @doc """
  Normalizes `value` into the range `[0.0, 1.0]` given `min` and `max`.
  Returns `0.0` when `min == max`.
  """
  @spec normalize(number(), number(), number()) :: float()
  def normalize(_value, min, max) when min == max, do: 0.0

  def normalize(value, min, max) do
    ((value - min) / (max - min))
    |> clamp(0.0, 1.0)
  end

  @doc """
  Scales `value` from `[src_min, src_max]` to `[dst_min, dst_max]`.
  Returns `dst_min` when the source range is empty.
  """
  @spec scale(number(), number(), number(), number(), number()) :: float()
  def scale(_value, src_min, src_max, dst_min, _dst_max) when src_min == src_max,
    do: dst_min * 1.0

  def scale(value, src_min, src_max, dst_min, dst_max) do
    t = normalize(value, src_min, src_max)
    dst_min + t * (dst_max - dst_min)
  end

  @doc """
  Clamps `value` to the range `[lo, hi]`.
  """
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  @doc """
  Formats `value` as a compact human-readable string.

  Numbers >= 1_000_000 use `M` suffix, >= 1_000 use `K` suffix,
  otherwise formatted with up to `precision` decimal places with
  trailing zeros removed.
  """
  @spec format_number(number(), non_neg_integer()) :: String.t()
  def format_number(value, precision \\ 1)

  def format_number(value, _precision) when abs(value) >= 1_000_000 do
    :erlang.float_to_binary(value / 1_000_000, decimals: 1) <> "M"
  end

  def format_number(value, _precision) when abs(value) >= 1_000 do
    :erlang.float_to_binary(value / 1_000, decimals: 1) <> "K"
  end

  def format_number(value, precision) when is_integer(value) and precision == 0 do
    Integer.to_string(value)
  end

  def format_number(value, precision) when is_integer(value) do
    Float.to_string(value * 1.0) |> trim_decimals(precision)
  end

  def format_number(value, precision) do
    :erlang.float_to_binary(value * 1.0, decimals: precision) |> trim_decimals(precision)
  end

  @doc """
  Calculates a `{min, max}` range for a list of numbers, optionally
  padded so that zero is always visible (`include_zero: true`).
  Returns `{0, 1}` for an empty list.
  """
  @spec calculate_range([number()], keyword()) :: {number(), number()}
  def calculate_range(values, opts \\ [])
  def calculate_range([], _opts), do: {0, 1}

  def calculate_range(values, opts) do
    raw_min = Enum.min(values)
    raw_max = Enum.max(values)

    if Keyword.get(opts, :include_zero, false) do
      {min(0, raw_min), max(0, raw_max)}
    else
      {raw_min, raw_max}
    end
  end

  @doc """
  Maps a normalized value in `[0.0, 1.0]` to an index into `levels`,
  where index 0 is "empty" and the last index is "full".
  """
  @spec level_index(float(), [term()]) :: non_neg_integer()
  def level_index(normalized, levels) do
    count = length(levels)

    round(normalized * (count - 1))
    |> clamp(0, count - 1)
  end

  @doc """
  Finds the first zone in `zones` whose threshold the `value` meets.
  `zones` is a list of `{threshold, term}` pairs sorted ascending.
  Returns the value from the last zone if none match.
  """
  @spec find_zone(number(), [{number(), term()}]) :: term()
  def find_zone(_value, [{_threshold, zone}]), do: zone
  def find_zone(value, [{threshold, zone} | _rest]) when value <= threshold, do: zone
  def find_zone(value, [_head | rest]), do: find_zone(value, rest)

  @doc """
  Repeats `string` exactly `count` times. Returns `""` when `count <= 0`.
  """
  @spec safe_duplicate(String.t(), integer()) :: String.t()
  def safe_duplicate(_string, count) when count <= 0, do: ""
  def safe_duplicate(string, count), do: String.duplicate(string, count)

  @doc """
  Returns the color at `index` in `palette`, cycling if `index`
  exceeds the palette length.
  """
  @spec cycle_color(non_neg_integer(), [{integer(), integer(), integer()}]) ::
          {integer(), integer(), integer()}
  def cycle_color(_index, []), do: {255, 255, 255}
  def cycle_color(index, palette), do: Enum.at(palette, rem(index, length(palette)))

  @doc """
  Computes bar height in whole cells plus a fractional sub-cell index
  given a normalized value, cell height, and a sub-cell level list.

  Returns `{whole_cells, sub_index}`.
  """
  @spec bar_height(float(), non_neg_integer(), [term()]) ::
          {non_neg_integer(), non_neg_integer()}
  def bar_height(normalized, cell_height, levels) do
    total_steps = cell_height * length(levels)
    steps = round(normalized * total_steps) |> clamp(0, total_steps)
    whole = div(steps, length(levels))
    sub = rem(steps, length(levels))
    {whole, sub}
  end

  defp trim_decimals(str, 0), do: String.replace(str, ~r/\..*$/, "")

  defp trim_decimals(str, _precision),
    do: String.replace(str, ~r/(\.\d*?)0+$/, "\\1") |> String.trim_trailing(".")
end
