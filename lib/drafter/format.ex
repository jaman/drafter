defmodule Drafter.Format do
  @moduledoc """
  Number formatting utilities that produce strings suitable for the `digits` widget.

  ## Usage

      digits(Drafter.Format.compact(12_000))        # "12k"
      digits(Drafter.Format.compact(1_500_000))     # "1.5M"
      digits(Drafter.Format.bytes(1_048_576))       # "1MB"
      digits(Drafter.Format.percent(0.42, as_ratio: true))  # "42%"
      digits(Drafter.Format.percent(99.5, decimals: 1))     # "99.5%"
  """

  @spec compact(number()) :: String.t()
  def compact(value) when is_number(value) do
    abs_val = abs(value)

    cond do
      abs_val >= 1_000_000_000_000 -> with_suffix(value, 1_000_000_000_000, "T")
      abs_val >= 1_000_000_000 -> with_suffix(value, 1_000_000_000, "B")
      abs_val >= 1_000_000 -> with_suffix(value, 1_000_000, "M")
      abs_val >= 1_000 -> with_suffix(value, 1_000, "k")
      true -> format_value(value * 1.0)
    end
  end

  @spec bytes(number()) :: String.t()
  def bytes(value) when is_number(value) do
    abs_val = abs(value)

    cond do
      abs_val >= 1_099_511_627_776 -> with_suffix(value, 1_099_511_627_776, "TB")
      abs_val >= 1_073_741_824 -> with_suffix(value, 1_073_741_824, "GB")
      abs_val >= 1_048_576 -> with_suffix(value, 1_048_576, "MB")
      abs_val >= 1_024 -> with_suffix(value, 1_024, "KB")
      true -> "#{trunc(value)}B"
    end
  end

  @spec percent(number()) :: String.t()
  @spec percent(number(), keyword()) :: String.t()
  def percent(value, opts \\ []) when is_number(value) do
    decimals = Keyword.get(opts, :decimals, 0)
    as_ratio = Keyword.get(opts, :as_ratio, false)
    pct = if as_ratio, do: value * 100.0, else: value * 1.0
    "#{format_value(pct, decimals)}%"
  end

  defp with_suffix(value, divisor, unit) do
    "#{format_value(value / divisor)}#{unit}"
  end

  defp format_value(value, decimals \\ nil) do
    f = value * 1.0
    rounded = if decimals, do: Float.round(f, decimals), else: smart_round(f)

    if rounded == trunc(rounded) do
      "#{trunc(rounded)}"
    else
      places = decimals || 1
      :erlang.float_to_binary(rounded, decimals: places)
    end
  end

  defp smart_round(value) when abs(value) >= 10, do: Float.round(value, 0)
  defp smart_round(value), do: Float.round(value, 1)
end
