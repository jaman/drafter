defmodule Drafter.Widget.Chart.Paint do
  @moduledoc false

  alias Drafter.Widget.Chart.Scene
  alias Drafter.Widget.Digits.Bitmap
  alias FrenchCurve.{Curve, Draw, Raster}

  @box_lines %{
    "─" => [:west, :east],
    "│" => [:north, :south],
    "╭" => [:east, :south],
    "╮" => [:west, :south],
    "╰" => [:north, :east],
    "╯" => [:north, :west],
    "┃" => [:north, :south]
  }

  @spec raster(Scene.t(), Scene.grid()) :: Raster.t()
  def raster(%Scene{shapes: shapes}, grid) do
    canvas = %{w: grid.cols * grid.sx, h: grid.rows * grid.sy, sx: grid.sx, sy: grid.sy}
    Enum.reduce(shapes, Raster.new(canvas.w, canvas.h), &draw(&2, &1, canvas))
  end

  @spec cells(
          Raster.t(),
          [{integer(), integer(), String.t(), Scene.color(), Scene.color() | nil}],
          Scene.grid()
        ) ::
          Raster.t()
  def cells(raster, cells, grid) do
    canvas = %{w: grid.cols * grid.sx, h: grid.rows * grid.sy, sx: grid.sx, sy: grid.sy}
    draw(raster, {:cells, cells}, canvas)
  end

  defp draw(raster, {:polyline, points, color, width, smooth}, canvas) do
    pixels = points |> Enum.map(&to_px(&1, canvas)) |> smoothed(smooth)
    thick_polyline(raster, pixels, color, width)
  end

  defp draw(raster, {:dots, points, color, radius}, canvas) do
    r = max(0, round(radius))

    spans =
      for point <- points,
          {cx, cy} <- [to_px(point, canvas)],
          dy <- -r..r//1 do
        half = round(:math.sqrt(max(0, r * r - dy * dy)))
        {cy + dy, cx - half, cx + half}
      end

    Raster.fill_spans(raster, spans, color)
  end

  defp draw(raster, {:band, points, color}, canvas) do
    columns =
      points
      |> Enum.map(fn {x, top, bottom} -> {x * canvas.sx, top * canvas.sy, bottom * canvas.sy} end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(&band_columns(&1, canvas))

    Draw.fill_columns(raster, columns, color)
  end

  defp draw(raster, {:rects, boxes, color}, canvas) do
    spans = Enum.flat_map(boxes, &rect_spans(&1, canvas))
    Raster.fill_spans(raster, spans, color)
  end

  defp draw(raster, {:pie, slices}, canvas), do: pie(raster, slices, canvas)

  defp draw(raster, {:gauge, value, fill, track}, canvas),
    do: gauge(raster, value, fill, track, canvas)

  defp draw(raster, {:cells, cells}, canvas) do
    Enum.reduce(cells, raster, fn {col, row, char, fg, bg}, acc ->
      cell(acc, col, row, char, fg, bg, canvas)
    end)
  end

  defp to_px({x, y}, canvas) do
    {(x * canvas.sx) |> round() |> Scene.clamp(0, canvas.w - 1),
     (y * canvas.sy) |> round() |> Scene.clamp(0, canvas.h - 1)}
  end

  defp smoothed(pixels, true) when length(pixels) > 2,
    do: pixels |> Curve.catmull_rom() |> Curve.to_pixels()

  defp smoothed(pixels, _smooth), do: pixels

  defp thick_polyline(raster, pixels, color, width) when width <= 1,
    do: Draw.polyline(raster, pixels, color)

  defp thick_polyline(raster, pixels, color, width) do
    low = -div(width - 1, 2)
    offsets = for dx <- low..(low + width - 1)//1, dy <- low..(low + width - 1)//1, do: {dx, dy}

    points =
      for {x, y} <- path_points(pixels), {dx, dy} <- offsets, uniq: true, do: {x + dx, y + dy}

    Raster.put_pixels(raster, points, color)
  end

  defp path_points([single]), do: [single]

  defp path_points(pixels) do
    pixels
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [from, to] -> Draw.line_points(from, to) end)
  end

  defp band_columns([{xa, ta, ba}, {xb, tb, bb}], canvas) do
    from = xa |> round() |> Scene.clamp(0, canvas.w - 1)
    to = xb |> round() |> Scene.clamp(0, canvas.w - 1)

    for col <- from..to//1 do
      t = if to == from, do: 0.0, else: (col - from) / (to - from)
      top = ta + (tb - ta) * t
      bottom = ba + (bb - ba) * t

      {col, top |> round() |> Scene.clamp(0, canvas.h - 1),
       bottom |> round() |> Scene.clamp(0, canvas.h - 1)}
    end
  end

  defp rect_spans({x0, y0, x1, y1}, canvas) do
    left = (x0 * canvas.sx) |> round() |> Scene.clamp(0, canvas.w - 1)
    right = max(left, round(x1 * canvas.sx) - 1) |> Scene.clamp(0, canvas.w - 1)
    top = (y0 * canvas.sy) |> round() |> Scene.clamp(0, canvas.h - 1)
    bottom = max(top, round(y1 * canvas.sy) - 1) |> Scene.clamp(0, canvas.h - 1)
    for y <- top..bottom//1, do: {y, left, right}
  end

  defp pie(raster, slices, canvas) do
    cx = canvas.w / 2
    cy = canvas.h / 2
    radius = min(canvas.w, canvas.h) / 2 - 1
    reach = radius * radius

    spans =
      for y <- max(0, ceil(cy - radius))..min(canvas.h - 1, floor(cy + radius))//1,
          x <- max(0, ceil(cx - radius))..min(canvas.w - 1, floor(cx + radius))//1,
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= reach do
        {slice_color(slices, angle(x - cx, y - cy)), {y, x, x}}
      end

    spans
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(raster, fn {color, color_spans}, acc ->
      Raster.fill_spans(acc, color_spans, color)
    end)
  end

  defp angle(dx, dy) do
    a = :math.atan2(dy, dx)
    if a < 0, do: a + 2 * :math.pi(), else: a
  end

  defp slice_color(slices, angle) do
    Enum.find_value(slices, fn {start, stop, color} ->
      if angle >= start and angle < stop, do: color
    end) ||
      elem(List.last(slices), 2)
  end

  defp gauge(raster, value, fill, track, canvas) do
    cx = canvas.w / 2
    cy = canvas.h - 1
    outer = min(canvas.w / 2, canvas.h) - 1
    inner = outer * 0.74
    threshold = :math.pi() * (1 - value)

    spans =
      for y <- 0..(canvas.h - 1)//1,
          x <- 0..(canvas.w - 1)//1,
          on_ring?(x - cx, cy - y, inner, outer) do
        {if(:math.atan2(cy - y, x - cx) >= threshold, do: fill, else: track), {y, x, x}}
      end

    spans
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(raster, fn {color, color_spans}, acc ->
      Raster.fill_spans(acc, color_spans, color)
    end)
  end

  defp on_ring?(dx, dy, inner, outer) do
    dist = dx * dx + dy * dy
    dy >= 0 and dist >= inner * inner and dist <= outer * outer
  end

  defp cell(raster, col, row, char, fg, bg, canvas) do
    x0 = col * canvas.sx
    y0 = row * canvas.sy
    raster = if bg, do: Raster.fill_spans(raster, cell_spans(x0, y0, canvas), bg), else: raster
    glyph(raster, char, {x0, y0}, fg, canvas)
  end

  defp cell_spans(x0, y0, canvas),
    do: for(y <- y0..(y0 + canvas.sy - 1)//1, do: {y, x0, x0 + canvas.sx - 1})

  defp glyph(raster, " ", _origin, _fg, _canvas), do: raster

  defp glyph(raster, "■", {x0, y0}, fg, canvas) do
    inset_x = div(canvas.sx, 5)
    inset_y = div(canvas.sy, 4)
    side = max(1, min(canvas.sx - 2 * inset_x, canvas.sy - 2 * inset_y))
    top = y0 + div(canvas.sy - side, 2)

    Raster.fill_spans(
      raster,
      for(y <- top..(top + side - 1)//1, do: {y, x0 + inset_x, x0 + inset_x + side - 1}),
      fg
    )
  end

  defp glyph(raster, "…", {x0, y0}, fg, canvas) do
    y = (y0 + canvas.sy * 3 / 4) |> round()
    dots = for i <- 0..2, do: {x0 + round((i + 0.5) * canvas.sx / 3), y}
    Raster.put_pixels(raster, dots, fg)
  end

  defp glyph(raster, char, origin, fg, canvas) when is_map_key(@box_lines, char),
    do: box_line(raster, Map.fetch!(@box_lines, char), origin, fg, canvas)

  defp glyph(raster, char, {x0, y0}, fg, canvas) do
    lit = Bitmap.pixels(char)
    ink_x = Enum.frequencies(Enum.map(lit, &elem(&1, 0)))
    ink_y = Enum.frequencies(Enum.map(lit, &elem(&1, 1)))
    {left, width} = shape_span(canvas.sx, Bitmap.width(), 0, 1)
    {top, height} = shape_span(canvas.sy, Bitmap.height(), 1, 3)
    shape_w = Bitmap.width() - 1
    shape_h = Bitmap.height() - 4

    points =
      for py <- 0..(height - 1)//1,
          source_y = inkiest(py, height, shape_h, 1, ink_y),
          px <- 0..(width - 1)//1,
          MapSet.member?(lit, {inkiest(px, width, shape_w, 0, ink_x), source_y}),
          do: {x0 + left + px, y0 + top + py}

    Raster.put_pixels(raster, points, fg)
  end

  defp shape_span(pixels, font_pixels, lead, trail) do
    margin_before = round(pixels * lead / font_pixels)
    margin_after = round(pixels * trail / font_pixels)
    {margin_before, max(1, pixels - margin_before - margin_after)}
  end

  defp inkiest(target, targets, sources, offset, ink) do
    first = div(target * sources, targets)
    last = max(first, div((target + 1) * sources - 1, targets))
    Enum.max_by(first..last, &Map.get(ink, &1 + offset, 0)) + offset
  end

  defp box_line(raster, arms, {x0, y0}, fg, canvas) do
    cx = x0 + div(canvas.sx, 2)
    cy = y0 + div(canvas.sy, 2)

    Enum.reduce(arms, raster, fn
      :west, acc -> Draw.line(acc, {x0, cy}, {cx, cy}, fg)
      :east, acc -> Draw.line(acc, {cx, cy}, {x0 + canvas.sx - 1, cy}, fg)
      :north, acc -> Draw.line(acc, {cx, y0}, {cx, cy}, fg)
      :south, acc -> Draw.line(acc, {cx, cy}, {cx, y0 + canvas.sy - 1}, fg)
    end)
  end
end
