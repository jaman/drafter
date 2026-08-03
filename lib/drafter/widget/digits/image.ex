defmodule Drafter.Widget.Digits.Image do
  @moduledoc """
  Draws `Drafter.Widget.Digits` text as a transmitted terminal image.

  On a terminal supporting the kitty, iTerm2, or sixel protocol, the glyph
  bitmaps are scaled into a raster and sent as a picture, so strokes land on
  pixel rather than cell boundaries.

  Every function returns `nil` when no protocol is available, and the widget
  renders cells instead.
  """

  alias Drafter.Widget.Chart.Pixel
  alias Drafter.Widget.Digits.Bitmap
  alias FrenchCurve.Raster

  @max_raster_width 1024
  @max_raster_height 320
  @cell_aspect 2

  @doc "The pixel protocol in use, or `nil` when the terminal has none."
  @spec protocol(atom() | nil) :: atom() | nil
  def protocol(renderer), do: Pixel.protocol(renderer)

  @doc """
  Renders text as a transmitted image sized to a cell box.

  Returns `{paint, clear}` as `Drafter.Widget`'s `image/3` expects, or `nil`
  when the text is empty, the box has no area, or the terminal cannot display
  an image.
  """
  @spec render(String.t(), {pos_integer(), pos_integer()}, tuple(), atom() | nil, term()) ::
          {iodata(), iodata()} | nil
  def render(text, {cols, rows}, color, renderer, id) do
    with true <- cols > 0 and rows > 0,
         graphemes when graphemes != [] <- String.graphemes(text),
         protocol when not is_nil(protocol) <- protocol(renderer),
         raster when not is_nil(raster) <- raster(graphemes, {cols, rows}, color) do
      encode(raster, protocol, {cols, rows}, id)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Rasterises text at the largest whole scale that fits a cell box.

  Scale is never below one; a box too small for native size is handled by the
  encoder's `fit`, which scales the finished picture down.
  """
  @spec raster([String.t()], {pos_integer(), pos_integer()}, tuple()) :: Raster.t()
  def raster(graphemes, {cols, rows}, color) do
    natural_width = length(graphemes) * Bitmap.width()
    scale = scale_for(natural_width, Bitmap.height(), cols, rows)

    graphemes
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(natural_width * scale, Bitmap.height() * scale), fn {grapheme,
                                                                                   index},
                                                                                  raster ->
      draw_glyph(raster, grapheme, index * Bitmap.width(), scale, rgba(color))
    end)
    |> Raster.finalize()
  end

  defp scale_for(natural_width, natural_height, cols, rows) do
    by_width = div(min(cols * @cell_aspect * 8, @max_raster_width), natural_width)
    by_height = div(min(rows * 8 * @cell_aspect, @max_raster_height), natural_height)

    max(min(by_width, by_height), 1)
  end

  defp draw_glyph(raster, grapheme, origin_x, scale, color) do
    Enum.reduce(Bitmap.pixels(grapheme), raster, fn {x, y}, acc ->
      fill_block(acc, (origin_x + x) * scale, y * scale, scale, color)
    end)
  end

  defp fill_block(raster, x0, y0, scale, color) do
    for dx <- 0..(scale - 1)//1, dy <- 0..(scale - 1)//1, reduce: raster do
      acc -> Raster.put_pixel(acc, x0 + dx, y0 + dy, color)
    end
  end

  defp rgba({r, g, b}), do: {r, g, b, 255}
  defp rgba({_r, _g, _b, _a} = color), do: color
  defp rgba(_), do: {255, 255, 255, 255}

  # See the note in Drafter.Widget.Chart.Pixel: not every terminal detected as :kitty keeps
  # images under an id, so the frame is built by FrenchCurve rather than assembled here.
  defp encode(raster, protocol, {cols, rows}, id) do
    case FrenchCurve.frame(raster, id, fit: {cols, rows}, protocol: protocol) do
      nil -> nil
      {paint, clear, _place} -> {paint, clear}
    end
  end
end
