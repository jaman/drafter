defmodule Drafter.Widget.Slider.Pixel do
  @moduledoc """
  Draws `Drafter.Widget.Slider` through the `french_curve` rasteriser.

  One drawing path with two outputs: a transmitted picture for terminals speaking the
  kitty, iTerm2 or sixel protocol, and braille `Drafter.Draw.Strip`s for any other
  truecolor terminal. Both draw the same shape — a rounded track, a rounded fill up to
  the value, and a disc for the thumb — so the slider keeps its outline wherever it is
  drawn.

  A `t:spec/0` describes what to draw; the caller supplies the cell box and this module
  picks the pixel resolution. Every function returns `nil` rather than raising when the
  box has no area or the drawing fails, and the widget falls back to characters.
  """

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Widget.Chart.Pixel
  alias FrenchCurve.Backend.Cells
  alias FrenchCurve.{Draw, Raster}

  @image_scale 4
  @cell_aspect 2
  @max_raster_width 1024
  @max_raster_height 256

  @type rgba :: {0..255, 0..255, 0..255, 0..255}

  @typedoc """
  What to draw: where the thumb sits, which way the slider runs, and the colours of
  the track, the fill behind the thumb and the thumb itself.
  """
  @type spec :: %{
          fraction: float(),
          orientation: :horizontal | :vertical,
          track: rgba(),
          fill: rgba(),
          thumb: rgba()
        }

  @doc """
  How a slider with this `renderer` should be drawn: `:pixel`, `:braille` or `:text`.

  Resolution follows `Drafter.Widget.Chart.Pixel.resolve/1`, so the `DRAFTER_MODE`
  environment variable wins over a per-widget `renderer`, which wins over the mode the
  app was run with. A mode asking for pixels on a terminal with no graphics protocol
  falls back to braille.
  """
  @spec mode(atom() | nil) :: Pixel.drawing()
  def mode(renderer) do
    case Pixel.resolve(renderer) do
      :text -> :text
      :braille -> :braille
      resolved -> if Pixel.protocol(resolved), do: :pixel, else: cells_or_braille(resolved)
    end
  end

  defp cells_or_braille(resolved) do
    if resolved in Pixel.cell_sets(), do: {:cells, resolved}, else: :braille
  end

  @doc "The pixel protocol in use, or `nil` when the terminal has none."
  @spec protocol(atom() | nil) :: atom() | nil
  def protocol(renderer), do: Pixel.protocol(renderer)

  @doc """
  Renders `spec` as a `Drafter.Render.Picture` filling a `cols` by `rows` cell box at
  the widget's top left, a whole number of pixels per cell.

  Returns `nil` when the terminal has no pixel protocol or the box has no area.
  """
  @spec picture(spec(), {pos_integer(), pos_integer()}, atom() | nil) ::
          Drafter.Render.Picture.t() | nil
  def picture(spec, {cols, rows}, renderer) do
    with protocol when not is_nil(protocol) <- protocol(renderer),
         raster when not is_nil(raster) <- raster(spec, image_pixels(cols, rows)) do
      %{raster: Raster.finalize(raster), protocol: protocol, dx: 0, dy: 0, cols: cols, rows: rows}
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Renders `spec` as `rows` strips of `cols` cells in the glyph set `set`, or `nil` when
  it cannot be drawn.
  """
  @spec cells_strips(spec(), {pos_integer(), pos_integer()}, Cells.set()) ::
          [Strip.t()] | nil
  def cells_strips(spec, {cols, rows}, set) do
    {sx, sy} = Cells.subpixels(set)

    case raster(spec, {cols * sx, rows * sy}) do
      nil ->
        nil

      raster ->
        raster
        |> FrenchCurve.render(:cells, set: set)
        |> Enum.map(&Strip.from_cells/1)
        |> fit_rows(rows, cols)
    end
  rescue
    _ -> nil
  end

  @doc """
  Renders `spec` as `rows` braille strips of `cols` cells, or `nil` when it cannot be
  drawn.
  """
  @spec braille_strips(spec(), {pos_integer(), pos_integer()}) :: [Strip.t()] | nil
  def braille_strips(spec, {cols, rows}) do
    case raster(spec, {cols * 2, rows * 4}) do
      nil ->
        nil

      raster ->
        raster
        |> FrenchCurve.render(:braille, [])
        |> rows_to_strips()
        |> fit_rows(rows, cols)
    end
  rescue
    _ -> nil
  end

  @doc """
  Draws `spec` into a raster `width` by `height` pixels.

  Returns `nil` for a raster with no area.
  """
  @spec raster(spec(), {integer(), integer()}) :: Raster.t() | nil
  def raster(spec, {width, height}) when width > 0 and height > 0 do
    draw(Raster.new(width, height), spec, width, height)
  end

  def raster(_spec, _size), do: nil

  defp draw(raster, %{orientation: :vertical} = spec, width, height) do
    {radius_x, radius_y} = vertical_thumb(width, height)
    track = shrink({radius_x, radius_y})
    center = div(width - 1, 2)
    top = radius_y
    bottom = height - 1 - radius_y
    thumb = bottom - round(spec.fraction * (bottom - top))

    raster
    |> capsule({top, bottom}, center, track, :vertical, spec.track)
    |> capsule({thumb, bottom}, center, track, :vertical, spec.fill)
    |> fill_ellipse({center, thumb}, {radius_x, radius_y}, spec.thumb)
  end

  defp draw(raster, spec, width, height) do
    {radius_x, radius_y} = horizontal_thumb(width, height)
    track = shrink({radius_x, radius_y})
    center = div(height - 1, 2)
    left = radius_x
    right = width - 1 - radius_x
    thumb = left + round(spec.fraction * (right - left))

    raster
    |> capsule({left, right}, center, track, :horizontal, spec.track)
    |> capsule({left, thumb}, center, track, :horizontal, spec.fill)
    |> fill_ellipse({thumb, center}, {radius_x, radius_y}, spec.thumb)
  end

  defp horizontal_thumb(width, height) do
    radius_y = Kernel.max(1, div(height, 2))
    {Kernel.max(1, Kernel.min(div(radius_y, @cell_aspect), div(width, 4))), radius_y}
  end

  defp vertical_thumb(width, height) do
    radius_x = Kernel.max(1, div(width, 2))
    {radius_x, Kernel.max(1, Kernel.min(radius_x * @cell_aspect, div(height, 4)))}
  end

  defp shrink({radius_x, radius_y}) do
    {Kernel.max(0, div(radius_x - 1, 2)), Kernel.max(0, div(radius_y - 1, 2))}
  end

  defp capsule(raster, {from, to}, center, {radius_x, radius_y}, :horizontal, color) do
    raster
    |> Draw.fill_rect({from, center - radius_y}, {to, center + radius_y}, color)
    |> fill_ellipse({from, center}, {radius_x, radius_y}, color)
    |> fill_ellipse({to, center}, {radius_x, radius_y}, color)
  end

  defp capsule(raster, {from, to}, center, {radius_x, radius_y}, :vertical, color) do
    raster
    |> Draw.fill_rect({center - radius_x, from}, {center + radius_x, to}, color)
    |> fill_ellipse({center, from}, {radius_x, radius_y}, color)
    |> fill_ellipse({center, to}, {radius_x, radius_y}, color)
  end

  defp fill_ellipse(raster, {center_x, center_y}, {radius_x, 0}, color) do
    Draw.line(raster, {center_x - radius_x, center_y}, {center_x + radius_x, center_y}, color)
  end

  defp fill_ellipse(raster, {center_x, center_y}, {radius_x, radius_y}, color) do
    Enum.reduce(-radius_y..radius_y//1, raster, fn offset, acc ->
      span = round(radius_x * :math.sqrt(1.0 - offset * offset / (radius_y * radius_y)))
      row = center_y + offset

      Draw.line(acc, {center_x - span, row}, {center_x + span, row}, color)
    end)
  end

  defp image_pixels(cols, rows) do
    {
      cols * Kernel.max(1, Kernel.min(@image_scale, div(@max_raster_width, cols))),
      rows * Kernel.max(1, Kernel.min(@image_scale * 2, div(@max_raster_height, rows)))
    }
  end

  defp rows_to_strips(rows) do
    Enum.map(rows, fn row ->
      Strip.new(
        Enum.map(row, fn
          {glyph, nil} -> Segment.new(glyph)
          {glyph, {r, g, b}} -> Segment.new(glyph, %{fg: {r, g, b}})
        end)
      )
    end)
  end

  defp fit_rows(strips, rows, cols) do
    sized = Enum.map(strips, &Strip.fit_to_width(&1, cols))
    blank = Strip.new([Segment.new(String.duplicate(" ", cols))])

    if length(sized) >= rows do
      Enum.take(sized, rows)
    else
      sized ++ List.duplicate(blank, rows - length(sized))
    end
  end
end
