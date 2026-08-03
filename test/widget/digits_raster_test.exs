defmodule Drafter.Widget.DigitsRasterTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Digits.{Bitmap, Font, Raster}

  doctest Drafter.Widget.Digits.Raster
  doctest Drafter.Widget.Digits.Bitmap

  @packings [:braille, :quadrant, :half]

  @blank_cells [" ", <<0x2800::utf8>>]

  defp blank_row?(row), do: row |> String.graphemes() |> Enum.all?(&(&1 in @blank_cells))

  defp inked_row?(row), do: not blank_row?(row)

  describe "bitmaps" do
    test "every bitmap fits the declared pixel box" do
      for character <- Bitmap.characters(), {x, y} <- Bitmap.pixels(character) do
        assert x in 0..(Bitmap.width() - 1),
               "#{inspect(character)} has a pixel at column #{x}"

        assert y in 0..(Bitmap.height() - 1),
               "#{inspect(character)} has a pixel at row #{y}"
      end
    end

    test "every bitmap leaves the side bearing column blank" do
      for character <- Bitmap.characters() do
        refute Enum.any?(Bitmap.pixels(character), fn {x, _y} -> x == Bitmap.width() - 1 end),
               "#{inspect(character)} bleeds into its side bearing"
      end
    end

    test "a space is blank and a zero is not" do
      assert MapSet.size(Bitmap.pixels(" ")) == 0
      assert MapSet.size(Bitmap.pixels("0")) > 0
    end

    test "lower case resolves to the upper-case bitmap" do
      assert Bitmap.pixels("q") == Bitmap.pixels("Q")
      assert Bitmap.drawable?("q")
    end

    test "an unknown character yields no pixels rather than raising" do
      assert MapSet.size(Bitmap.pixels("☃")) == 0
      refute Bitmap.drawable?("☃")
    end
  end

  describe "rasterising" do
    test "every packing produces glyphs of its own declared size" do
      for packing <- @packings do
        font = Raster.font(packing)

        for {character, rows} <- font.glyphs do
          assert length(rows) == font.height,
                 "#{packing} #{inspect(character)} is #{length(rows)} rows"

          for row <- rows do
            assert String.length(row) == font.width,
                   "#{packing} #{inspect(character)} row #{inspect(row)} is #{String.length(row)} wide"
          end
        end
      end
    end

    test "cell size and shrink together account for the glyph size" do
      for packing <- @packings do
        {across, down} = Raster.cell_pixels(packing)
        {shrink_x, shrink_y} = Raster.shrink(packing)
        font = Raster.font(packing)

        assert font.width == div(div(Bitmap.width(), shrink_x), across)
        assert font.height == div(div(Bitmap.height(), shrink_y), down)
      end
    end

    test "a blank bitmap rasterises to blank cells, not to nothing" do
      for packing <- @packings do
        font = Raster.font(packing)
        rows = font.glyphs[" "]

        assert length(rows) == font.height
        assert Enum.all?(rows, &blank_row?/1)
      end
    end

    test "an inked bitmap rasterises to at least one non-blank cell" do
      for packing <- @packings, character <- ["0", "A", "Z", "#"] do
        rows = Raster.font(packing).glyphs[character]

        assert Enum.any?(rows, &inked_row?/1),
               "#{packing} rendered #{inspect(character)} blank"
      end
    end

    test "every packing covers exactly the bitmap repertoire" do
      for packing <- @packings do
        assert packing |> Raster.font() |> Map.fetch!(:glyphs) |> Map.keys() |> Enum.sort() ==
                 Bitmap.characters()
      end
    end

    test "shrinking keeps a thin stroke rather than dropping it" do
      lit = MapSet.new([{0, 0}])

      for packing <- @packings do
        [first | _] = Raster.glyph(packing, lit, 1, 1)
        assert inked_row?(first), "#{packing} lost a single lit pixel"
      end
    end
  end

  describe "catalogue wiring" do
    test "the rasterised fonts are the ones the catalogue publishes" do
      assert Font.get(:braille) == Raster.font(:braille)
      assert Font.get(:pixel) == Raster.font(:quadrant)
      assert Font.get(:tall) == Raster.font(:half)
    end

    test "braille and quadrant occupy the same cells at different detail" do
      assert {Font.width(:braille), Font.height(:braille)} ==
               {Font.width(:pixel), Font.height(:pixel)}

      assert Raster.cell_pixels(:braille) > Raster.cell_pixels(:quadrant)
    end

    test "the rasterised fonts share one height" do
      assert Enum.uniq(Enum.map([:braille, :pixel, :tall], &Font.height/1)) |> length() == 1
    end
  end
end
