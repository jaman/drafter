defmodule Drafter.Widget.DigitsFontTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Digits
  alias Drafter.Widget.Digits.Font

  doctest Drafter.Widget.Digits.Font

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp strip_text(strip), do: Enum.map_join(strip.segments, & &1.text)

  describe "catalogue geometry" do
    test "every glyph of every font is exactly the font's height" do
      for name <- Font.names(), {character, rows} <- Font.get(name).glyphs do
        assert length(rows) == Font.height(name),
               "#{name} #{inspect(character)} has #{length(rows)} rows"
      end
    end

    test "every glyph row of every font is exactly the font's width" do
      for name <- Font.names(),
          {character, rows} <- Font.get(name).glyphs,
          row <- rows do
        assert String.length(row) == Font.width(name),
               "#{name} #{inspect(character)} row #{inspect(row)} is #{String.length(row)} wide"
      end
    end
  end

  describe "repertoire" do
    test "every font covers the same characters" do
      [first | rest] = Enum.map(Font.names(), &Font.repertoire/1)
      for other <- rest, do: assert(other == first)
    end

    test "digits, the alphabet and a space are covered by every font" do
      required = Enum.map(?0..?9, &<<&1>>) ++ Enum.map(?A..?Z, &<<&1>>) ++ [" "]

      for name <- Font.names(), character <- required do
        assert Font.supports?(name, character), "#{name} cannot draw #{inspect(character)}"
      end
    end

    test "lower case falls back to the upper-case glyph" do
      for name <- Font.names() do
        assert Font.glyph(name, "a") == Font.glyph(name, "A")
        assert Font.supports?(name, "z")
      end
    end
  end

  describe "unknown characters" do
    test "render as blanks of the font's own width rather than raising" do
      for name <- Font.names() do
        rows = Font.glyph(name, "☃")

        assert length(rows) == Font.height(name)
        assert Enum.all?(rows, &(&1 == String.duplicate(" ", Font.width(name))))
      end
    end

    test "an unknown font name falls back to :block" do
      assert Font.get(:no_such_font) == Font.get(:block)
      assert Font.height(:no_such_font) == Font.height(:block)
    end
  end

  describe "font selection in the widget" do
    test "size: :small still selects the compact font" do
      state = Digits.mount(%{text: "8", size: :small})
      assert length(Digits.render(state, rect(20, 3))) == Font.height(:compact)
    end

    test "size: :large still selects the block font" do
      state = Digits.mount(%{text: "8", size: :large})
      assert length(Digits.render(state, rect(20, 5))) == Font.height(:block)
    end

    test "font: overrides size:" do
      state = Digits.mount(%{text: "8", size: :large, font: :braille})
      strips = Digits.render(state, rect(20, Font.height(:braille)))

      assert length(strips) == Font.height(:braille)
    end

    test "every font renders a full row of the rect's width" do
      for name <- Font.names() do
        state = Digits.mount(%{text: "42", font: name})

        for strip <- Digits.render(state, rect(40, Font.height(name))) do
          assert Strip.width(strip) == 40
        end
      end
    end

    test "each character occupies exactly the font's width" do
      for name <- Font.names() do
        state = Digits.mount(%{text: "123", font: name})
        [first | _] = Digits.render(state, rect(80, Font.height(name)))

        assert first |> strip_text() |> String.trim_trailing() |> String.length() <=
                 3 * Font.width(name)
      end
    end

    test "preferred_height follows the chosen font" do
      for name <- Font.names() do
        assert Digits.preferred_height("42", font: name) == Font.height(name)
      end

      assert Digits.preferred_height("42", size: :small) == Font.height(:compact)
      assert Digits.preferred_height("42", []) == Font.height(:block)
    end

    test "a font chosen through the component API reaches the widget state" do
      props = Digits.from_component_opts(1234, font: :tall)
      state = Digits.mount(props)

      assert length(Digits.render(state, rect(40, Font.height(:tall)))) == Font.height(:tall)
    end

    test "the font survives a re-mount of the same component" do
      mount_props = Digits.from_component_opts(99, font: :braille)
      existing = Digits.mount(Digits.from_component_opts(99, font: :block))

      assert %{font: :braille} = Digits.update_props_from_mount(mount_props, existing, [])
    end
  end

  describe "rendering unrepresentable text" do
    test "a snowman renders blanks without raising" do
      state = Digits.mount(%{text: "4☃2"})
      strips = Digits.render(state, rect(40, 5))

      assert length(strips) == 5
      assert Enum.all?(strips, &(Strip.width(&1) == 40))
    end

    test "lower case renders the same shapes as upper case" do
      lower = Digits.mount(%{text: "cpu"}) |> Digits.render(rect(40, 5))
      upper = Digits.mount(%{text: "CPU"}) |> Digits.render(rect(40, 5))

      assert Enum.map(lower, &strip_text/1) == Enum.map(upper, &strip_text/1)
    end
  end
end
