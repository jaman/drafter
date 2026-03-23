defmodule Drafter.CharacterWidth do
  @moduledoc """
  Unicode character display width calculation for terminal rendering.
  """

  @spec grapheme(String.t()) :: non_neg_integer()
  def grapheme(<<cp::utf8, _rest::binary>>), do: codepoint(cp)
  def grapheme(_), do: 0

  @spec string(String.t()) :: non_neg_integer()
  def string(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn g, acc -> acc + grapheme(g) end)
  end

  @double_width_ranges [
    {0x1100, 0x11FF},
    {0x2E80, 0x9FFF},
    {0xAC00, 0xD7AF},
    {0xFE10, 0xFE1F},
    {0xFE30, 0xFE6F},
    {0xFF00, 0xFF60},
    {0xFFE0, 0xFFE6},
    {0x1F300, 0x1F9FF},
    {0x2600, 0x26FF},
    {0x2700, 0x27BF},
    {0x1F600, 0x1F64F},
    {0x1F680, 0x1F6FF}
  ]

  defp codepoint(cp) do
    if double_width?(cp), do: 2, else: 1
  end

  defp double_width?(cp) do
    Enum.any?(@double_width_ranges, fn {lo, hi} -> cp >= lo and cp <= hi end)
  end
end
