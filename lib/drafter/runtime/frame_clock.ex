defmodule Drafter.Runtime.FrameClock do
  @moduledoc """
  Converts an application's `:refresh_rate` setting into a frame interval.

  Frame pacing itself is done by `Drafter.Runtime.AppLoop`.
  """

  @type interval :: pos_integer() | nil

  @doc """
  Frame interval in milliseconds for a refresh-rate specification.

  Accepts `"30fps"`, `"7.5fps"`, `"unlimited"`, `:unlimited`, or a millisecond
  integer. Returns `nil` for unlimited. Raises `ArgumentError` on anything else.

  ## Examples

      iex> Drafter.Runtime.FrameClock.interval_for("30fps")
      33

      iex> Drafter.Runtime.FrameClock.interval_for("7.5fps")
      133

      iex> Drafter.Runtime.FrameClock.interval_for(:unlimited)
      nil

      iex> Drafter.Runtime.FrameClock.interval_for(16)
      16

  """
  @spec interval_for(term()) :: interval()
  def interval_for(:unlimited), do: nil
  def interval_for("unlimited"), do: nil
  def interval_for(ms) when is_integer(ms) and ms > 0, do: ms

  def interval_for(spec) when is_binary(spec) do
    if Regex.match?(~r/^\d+(\.\d+)?\s*fps$/i, spec) do
      [fps] = Regex.run(~r/[\d.]+/, spec)
      round(1000 / String.to_float(ensure_float(fps)))
    else
      raise ArgumentError, "invalid refresh_rate: #{inspect(spec)}"
    end
  end

  defp ensure_float(value) do
    if String.contains?(value, "."), do: value, else: value <> ".0"
  end
end
