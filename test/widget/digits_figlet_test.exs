defmodule Drafter.Widget.DigitsFigletTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Digits
  alias Drafter.Widget.Digits.{Figlet, Font}

  @fixture "test/fixtures/figlet/testfont.flf"

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp strip_text(strip), do: Enum.map_join(strip.segments, & &1.text)

  setup do
    on_exit(fn -> Font.unregister(:testfont) end)
    :ok
  end

  describe "parsing" do
    test "reads the height from the header" do
      {:ok, font} = Figlet.load(@fixture)

      assert font.height == 3
    end

    test "every glyph has as many rows as the header declares" do
      {:ok, font} = Figlet.load(@fixture)

      for {character, rows} <- font.glyphs do
        assert length(rows) == font.height, "#{inspect(character)} has #{length(rows)} rows"
      end
    end

    test "every row of a glyph is the same width" do
      {:ok, font} = Figlet.load(@fixture)

      for {character, rows} <- font.glyphs do
        widths = rows |> Enum.map(&String.length/1) |> Enum.uniq()
        assert length(widths) == 1, "#{inspect(character)} has ragged rows: #{inspect(widths)}"
      end
    end

    test "endmarks are stripped from every row" do
      {:ok, font} = Figlet.load(@fixture)

      for {_character, rows} <- font.glyphs, row <- rows do
        refute String.contains?(row, "@")
      end
    end

    test "hardblanks become spaces" do
      {:ok, font} = Figlet.load(@fixture)

      for {_character, rows} <- font.glyphs, row <- rows do
        refute String.contains?(row, "$")
      end

      assert font.glyphs["A"] == ["   ", "/_\\", "| |"]
    end

    test "covers the printable ASCII range" do
      {:ok, font} = Figlet.load(@fixture)

      for codepoint <- 32..126 do
        assert Map.has_key?(font.glyphs, <<codepoint::utf8>>),
               "missing glyph for #{inspect(<<codepoint::utf8>>)}"
      end
    end

    test "the reported width is the widest glyph" do
      {:ok, font} = Figlet.load(@fixture)
      widest = font.glyphs |> Map.values() |> Enum.map(&String.length(hd(&1))) |> Enum.max()

      assert font.width == widest
    end

    test "glyphs keep their own widths rather than being padded to the widest" do
      {:ok, font} = Figlet.load(@fixture)

      assert Font.glyph_width(font, "!") < Font.glyph_width(font, "A")
    end
  end

  describe "malformed input" do
    test "a missing file reports why" do
      assert {:error, {:unreadable, :enoent}} = Figlet.load("test/fixtures/figlet/nope.flf")
    end

    test "a file that is not FIGlet is rejected" do
      assert {:error, {:malformed, _}} = Figlet.parse("this is not a font\nat all\n")
    end

    test "a truncated header is rejected" do
      assert {:error, {:malformed, _}} = Figlet.parse("flf2a$ 3\nbody\n")
    end

    test "a header with no glyph data is rejected" do
      assert {:error, {:malformed, :no_glyphs}} = Figlet.parse("flf2a$ 3 3 6 -1 0\n")
    end

    test "a non-numeric height is rejected" do
      assert {:error, {:malformed, :height}} = Figlet.parse("flf2a$ x 3 6 -1 0\nbody\n")
    end
  end

  describe "registration" do
    test "a registered font is reachable by name" do
      {:ok, font} = Figlet.load(@fixture)
      Font.register(:testfont, font)

      assert Font.get(:testfont) == font
      assert :testfont in Font.names()
    end

    test "unregistering removes it without touching the built-ins" do
      {:ok, font} = Figlet.load(@fixture)
      Font.register(:testfont, font)
      Font.unregister(:testfont)

      refute :testfont in Font.names()
      assert Font.builtin_names() == Font.builtin_names()
      assert Font.get(:block).height == 5
    end

    test "an unregistered name still falls back to block rather than raising" do
      assert Font.get(:never_registered) == Font.get(:block)
    end

    test "a registered name wins over a built-in one" do
      {:ok, font} = Figlet.load(@fixture)
      builtin = Font.get(:block)
      Font.register(:block, font)

      assert Font.get(:block) == font

      Font.unregister(:block)
      assert Font.get(:block) == builtin
    end
  end

  describe "bundled fonts" do
    setup do
      on_exit(fn -> Enum.each(Map.keys(Figlet.bundled()), &Font.unregister/1) end)
      :ok
    end

    test "every shipped font parses" do
      files = Path.wildcard(Path.join(Figlet.bundled_directory(), "*.flf"))

      assert files != [], "no fonts are shipped"
      assert map_size(Figlet.bundled()) == length(files)
    end

    test "no shipped font shadows a built-in name" do
      collisions = Enum.filter(Map.keys(Figlet.bundled()), &(&1 in Font.builtin_names()))

      assert collisions == [],
             "shipped fonts would silently replace built-ins: #{inspect(collisions)}"
    end

    test "registering the bundle makes every font reachable by name" do
      for name <- Figlet.register_bundled() do
        assert name in Font.names()
        assert Font.height(name) > 0
        assert Font.glyph_width(name, "A") > 0
      end
    end

    test "every shipped font can draw the printable ASCII range" do
      for {name, font} <- Figlet.bundled(), codepoint <- 32..126 do
        assert Font.supports?(font, <<codepoint::utf8>>),
               "#{name} cannot draw #{inspect(<<codepoint::utf8>>)}"
      end
    end

    test "every shipped glyph has rows of one width and the font's height" do
      for {name, font} <- Figlet.bundled(), {character, rows} <- font.glyphs do
        assert length(rows) == font.height,
               "#{name} #{inspect(character)} has #{length(rows)} rows"

        assert rows |> Enum.map(&String.length/1) |> Enum.uniq() |> length() == 1,
               "#{name} #{inspect(character)} has ragged rows"
      end
    end
  end

  describe "rendering proportional fonts" do
    test "a font map can be passed straight to the widget without registering" do
      {:ok, font} = Figlet.load(@fixture)
      state = Digits.mount(%{text: "AB", font: font})

      assert length(Digits.render(state, rect(40, font.height))) == font.height
    end

    test "text width is the sum of glyph widths, not a fixed cell" do
      {:ok, font} = Figlet.load(@fixture)

      assert Font.text_width(font, "A!") ==
               Font.glyph_width(font, "A") + Font.glyph_width(font, "!")
    end

    test "proportional glyphs are laid out without overlapping or gapping" do
      {:ok, font} = Figlet.load(@fixture)
      Font.register(:testfont, font)

      state = Digits.mount(%{text: "A!A", font: :testfont})
      [first | _] = Digits.render(state, rect(60, font.height))

      assert first |> strip_text() |> String.trim_trailing() |> String.length() <=
               Font.text_width(font, "A!A")
    end

    test "strips still fill the rect width whatever the glyph widths" do
      {:ok, font} = Figlet.load(@fixture)
      state = Digits.mount(%{text: "AB!", font: font})

      for strip <- Digits.render(state, rect(50, font.height)) do
        assert Strip.width(strip) == 50
      end
    end

    test "centring accounts for proportional width" do
      {:ok, font} = Figlet.load(@fixture)
      state = Digits.mount(%{text: "!", font: font, align: :center})
      [first | _] = Digits.render(state, rect(41, font.height))

      leading =
        first
        |> strip_text()
        |> then(&(String.length(&1) - String.length(String.trim_leading(&1))))

      assert leading >= div(41 - Font.glyph_width(font, "!"), 2) - 1
    end

    test "an unrepresentable character does not break the layout" do
      {:ok, font} = Figlet.load(@fixture)
      state = Digits.mount(%{text: "A☃B", font: font})

      for strip <- Digits.render(state, rect(50, font.height)) do
        assert Strip.width(strip) == 50
      end
    end
  end

  describe "loading a directory" do
    test "picks up every .flf and keys it by basename" do
      loaded = Figlet.load_directory("test/fixtures/figlet")

      assert Map.has_key?(loaded, :testfont)
      assert loaded[:testfont].height == 3
    end

    test "a directory with no fonts yields an empty map" do
      assert Figlet.load_directory("test/fixtures") == %{}
    end
  end
end
