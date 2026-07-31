defmodule Drafter.Widget.Chart.Pixels do
  @moduledoc false

  import Bitwise

  alias Drafter.Draw.{Segment, Strip}

  @braille_base 0x2800

  @braille_dot_offsets %{
    {0, 0} => 0x01,
    {0, 1} => 0x02,
    {0, 2} => 0x04,
    {0, 3} => 0x40,
    {1, 0} => 0x08,
    {1, 1} => 0x10,
    {1, 2} => 0x20,
    {1, 3} => 0x80
  }

  @quadrant_chars %{
    0 => " ",
    1 => "▘",
    2 => "▝",
    3 => "▀",
    4 => "▖",
    5 => "▌",
    6 => "▚",
    7 => "▛",
    8 => "▗",
    9 => "▞",
    10 => "▐",
    11 => "▜",
    12 => "▄",
    13 => "▙",
    14 => "▟",
    15 => "█"
  }

  def braille_base, do: @braille_base
  def braille_dot_offsets, do: @braille_dot_offsets

  def braille_char_for_pixels([], _fg, bg), do: Segment.new(braille_char(0), %{fg: bg, bg: bg})

  def braille_char_for_pixels(char_pixels, fg, bg),
    do: Segment.new(build_braille_char(char_pixels), %{fg: fg, bg: bg})

  def render_braille_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 4

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 4)} end)

    for row <- 0..(height - 1)//1 do
      segments =
        for col <- 0..(width - 1)//1 do
          braille_char_for_pixels(Map.get(pixels_by_char, {col, row}, []), fg, bg)
        end

      Strip.new(segments)
    end
  end

  def render_quadrant_pixels(pixels, width, height, bg, fg) do
    pixel_height = height * 2

    pixels_by_char =
      pixels
      |> Enum.filter(fn {x, y} -> x >= 0 and x < width * 2 and y >= 0 and y < pixel_height end)
      |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 2)} end)

    for row <- 0..(height - 1)//1 do
      segments =
        for col <- 0..(width - 1)//1, do: quadrant_pixel_segment(pixels_by_char, col, row, fg, bg)

      Strip.new(segments)
    end
  end

  def quadrant_pixel_segment(pixels_by_char, col, row, fg, bg) do
    char_pixels = Map.get(pixels_by_char, {col, row}, [])

    bits =
      Enum.reduce(char_pixels, 0, fn {x, y}, acc ->
        acc ||| quadrant_bit({rem(x, 2), rem(y, 2)})
      end)

    Segment.new(quadrant_char(bits), %{fg: fg, bg: bg})
  end

  def quadrant_char(bits), do: Map.get(@quadrant_chars, bits, " ")

  def quadrant_bit({0, 0}), do: 1
  def quadrant_bit({1, 0}), do: 2
  def quadrant_bit({0, 1}), do: 4
  def quadrant_bit({1, 1}), do: 8
  def quadrant_bit(_), do: 0

  def build_braille_char(pixels) do
    bits =
      pixels
      |> Enum.map(fn {x, y} ->
        local_x = rem(x, 2)
        local_y = rem(y, 4)
        Map.get(@braille_dot_offsets, {local_x, local_y}, 0)
      end)
      |> Enum.sum()

    braille_char(bits)
  end

  def braille_char(bits) when bits >= 0 and bits <= 255 do
    <<@braille_base + bits::utf8>>
  end

  def braille_char(_), do: " "

  def colored_braille_segment([], bg), do: Segment.new(braille_char(0), %{bg: bg})

  def colored_braille_segment(char_pixels, bg) do
    {bits, color} =
      Enum.reduce(char_pixels, {0, nil}, fn {x, y, c}, {b, _} ->
        bit = Map.get(@braille_dot_offsets, {rem(x, 2), rem(y, 4)}, 0)
        {b ||| bit, c}
      end)

    Segment.new(braille_char(bits), %{fg: color, bg: bg})
  end

  def render_braille_pixels_colored(colored_pixels, width, height, bg) do
    pixel_height = height * 4

    pixels_by_char =
      colored_pixels
      |> Enum.filter(fn {x, y, _c} ->
        x >= 0 and x < width * 2 and y >= 0 and y < pixel_height
      end)
      |> Enum.group_by(fn {x, y, _c} -> {div(x, 2), div(y, 4)} end)

    for row <- 0..(height - 1)//1 do
      segments =
        for col <- 0..(width - 1)//1 do
          colored_braille_segment(Map.get(pixels_by_char, {col, row}, []), bg)
        end

      Strip.new(segments)
    end
  end
end
