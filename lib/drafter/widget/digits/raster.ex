defmodule Drafter.Widget.Digits.Raster do
  @moduledoc """
  Rasterises `Drafter.Widget.Digits.Bitmap` glyphs into terminal cells.

  Three packings put multiple pixels in one cell: `:braille` (2×4), `:quadrant`
  (2×2), and `:half` (1×2). `Drafter.Widget.Chart.Pixels` supplies the cell
  characters. See the [large text guide](large_text.md) for how the packings
  compare.

  ## Examples

      iex> Drafter.Widget.Digits.Raster.cell_pixels(:braille)
      {2, 4}

      iex> Drafter.Widget.Digits.Raster.shrink(:quadrant)
      {1, 2}

      iex> font = Drafter.Widget.Digits.Raster.font(:braille)
      iex> {font.width, font.height}
      {4, 4}

  """

  alias Drafter.Widget.Chart.Pixels
  alias Drafter.Widget.Digits.Bitmap

  @type packing :: :braille | :quadrant | :half

  @doc "Pixels a cell holds, as `{across, down}`, for a packing."
  @spec cell_pixels(packing()) :: {pos_integer(), pos_integer()}
  def cell_pixels(:braille), do: {2, 4}
  def cell_pixels(:quadrant), do: {2, 2}
  def cell_pixels(:half), do: {1, 2}

  @doc """
  Divisors applied to the bitmap before rasterising, as `{x, y}`.

  `:braille` reads the bitmap at full resolution. The coarser packings halve the
  rows; a shrunk pixel is lit when any pixel it covers was lit.
  """
  @spec shrink(packing()) :: {pos_integer(), pos_integer()}
  def shrink(:braille), do: {1, 1}
  def shrink(:quadrant), do: {1, 2}
  def shrink(:half), do: {1, 2}

  @doc """
  Rasterise every bitmap into a font map for `Drafter.Widget.Digits.Font`.

  Returns `%{height: rows, width: columns, glyphs: %{character => [row, ...]}}`.
  """
  @spec font(packing()) :: %{height: pos_integer(), width: pos_integer(), glyphs: map()}
  def font(packing) do
    {across, down} = cell_pixels(packing)
    {shrink_x, shrink_y} = shrink(packing)
    columns = div(div(Bitmap.width(), shrink_x), across)
    rows = div(div(Bitmap.height(), shrink_y), down)

    glyphs =
      Map.new(Bitmap.characters(), fn character ->
        {character, glyph(packing, Bitmap.pixels(character), columns, rows)}
      end)

    %{height: rows, width: columns, glyphs: glyphs}
  end

  @doc "Rasterise one set of lit pixels into `rows` strings of `columns` cells."
  @spec glyph(packing(), MapSet.t(), pos_integer(), pos_integer()) :: [String.t()]
  def glyph(packing, lit, columns, rows) do
    shrunk = shrink_pixels(lit, shrink(packing))

    for row <- 0..(rows - 1)//1 do
      Enum.map_join(0..(columns - 1)//1, &cell(packing, shrunk, &1, row))
    end
  end

  defp shrink_pixels(lit, {1, 1}), do: lit

  defp shrink_pixels(lit, {shrink_x, shrink_y}) do
    MapSet.new(lit, fn {x, y} -> {div(x, shrink_x), div(y, shrink_y)} end)
  end

  defp cell(packing, lit, column, row) do
    {across, down} = cell_pixels(packing)
    origin_x = column * across
    origin_y = row * down

    lit_in_cell =
      for x <- 0..(across - 1)//1,
          y <- 0..(down - 1)//1,
          MapSet.member?(lit, {origin_x + x, origin_y + y}),
          do: {x, y}

    render_cell(packing, lit_in_cell)
  end

  defp render_cell(:braille, lit_in_cell) do
    bits = Enum.reduce(lit_in_cell, 0, &(&2 + Map.fetch!(Pixels.braille_dot_offsets(), &1)))
    Pixels.braille_char(bits)
  end

  defp render_cell(:quadrant, lit_in_cell) do
    bits = Enum.reduce(lit_in_cell, 0, &(&2 + Pixels.quadrant_bit(&1)))
    Pixels.quadrant_char(bits)
  end

  defp render_cell(:half, lit_in_cell) do
    case {{0, 0} in lit_in_cell, {0, 1} in lit_in_cell} do
      {true, true} -> "█"
      {true, false} -> "▀"
      {false, true} -> "▄"
      {false, false} -> " "
    end
  end
end
