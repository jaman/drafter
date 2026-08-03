defmodule Drafter.CharacterWidthTest do
  use ExUnit.Case, async: true

  alias Drafter.CharacterWidth

  doctest Drafter.CharacterWidth
  doctest Drafter.CharacterWidth.Default

  describe "ascii" do
    test "printable ascii is one column" do
      for cp <- ?\s..?~ do
        assert CharacterWidth.grapheme(<<cp::utf8>>) == 1
      end
    end

    test "string/1 of pure ascii equals byte size" do
      text = "the quick brown fox jumps over the lazy dog 0123456789"
      assert CharacterWidth.string(text) == byte_size(text)
    end

    test "control characters occupy no columns" do
      assert CharacterWidth.string("\a\b\e\0") == 0
      assert CharacterWidth.string("a\eb") == 2
    end
  end

  describe "east asian wide" do
    test "japanese kana and kanji are two columns" do
      assert CharacterWidth.grapheme("あ") == 2
      assert CharacterWidth.grapheme("ア") == 2
      assert CharacterWidth.grapheme("漢") == 2
      assert CharacterWidth.string("こんにちは") == 10
    end

    test "hangul is two columns" do
      assert CharacterWidth.grapheme("한") == 2
      assert CharacterWidth.string("한국어") == 6
    end

    test "cjk punctuation and ideographic space are two columns" do
      assert CharacterWidth.grapheme("、") == 2
      assert CharacterWidth.grapheme("　") == 2
      assert CharacterWidth.grapheme("《") == 2
    end

    test "fullwidth forms are two columns" do
      assert CharacterWidth.grapheme("Ａ") == 2
      assert CharacterWidth.grapheme("￥") == 2
    end

    test "halfwidth katakana is one column" do
      assert CharacterWidth.grapheme("ｱ") == 1
      assert CharacterWidth.string("ｱｲｳ") == 3
    end

    test "cjk extension planes are two columns" do
      assert CharacterWidth.grapheme(<<0x20000::utf8>>) == 2
      assert CharacterWidth.grapheme(<<0x2A700::utf8>>) == 2
      assert CharacterWidth.grapheme(<<0x1B000::utf8>>) == 2
    end
  end

  describe "hebrew" do
    test "base letters are one column" do
      assert CharacterWidth.grapheme("א") == 1
      assert CharacterWidth.string("שלום") == 4
    end

    test "niqqud are zero width when standalone" do
      assert CharacterWidth.grapheme(<<0x05B4::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0x05C7::utf8>>) == 0
    end

    test "pointed text measures only its base letters" do
      assert CharacterWidth.string("שָׁלוֹם") == 4
    end
  end

  describe "arabic" do
    test "base letters are one column" do
      assert CharacterWidth.grapheme("ا") == 1
      assert CharacterWidth.string("سلام") == 4
    end

    test "harakat are zero width when standalone" do
      assert CharacterWidth.grapheme(<<0x064E::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0x0651::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0x0670::utf8>>) == 0
    end

    test "vocalised text measures only its base letters" do
      assert length(String.graphemes("مَرْحَبًا")) == 5
      assert CharacterWidth.string("مَرْحَبًا") == 5
    end

    test "presentation forms are one column" do
      assert CharacterWidth.grapheme(<<0xFEF3::utf8>>) == 1
    end

    test "tatweel is one column" do
      assert CharacterWidth.grapheme(<<0x0640::utf8>>) == 1
    end
  end

  describe "combining marks" do
    test "standalone latin combining marks are zero width" do
      assert CharacterWidth.grapheme(<<0x0301::utf8>>) == 0
    end

    test "decomposed latin measures as its base" do
      assert CharacterWidth.string("é") == 1
      assert CharacterWidth.string("café") == 4
    end

    test "precomposed latin is one column" do
      assert CharacterWidth.string("café") == 4
    end

    test "devanagari and thai marks are zero width" do
      assert CharacterWidth.grapheme(<<0x093C::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0x0E31::utf8>>) == 0
    end
  end

  describe "emoji" do
    test "emoji presentation symbols below the astral planes are two columns" do
      assert CharacterWidth.grapheme("✅") == 2
      assert CharacterWidth.grapheme("❌") == 2
      assert CharacterWidth.grapheme("⌚") == 2
      assert CharacterWidth.grapheme("⭐") == 2
      assert CharacterWidth.grapheme("⬛") == 2
    end

    test "astral emoji are two columns" do
      assert CharacterWidth.grapheme("🚀") == 2
      assert CharacterWidth.grapheme("😀") == 2
      assert CharacterWidth.grapheme("🩺") == 2
      assert CharacterWidth.grapheme("🫠") == 2
    end

    test "text presentation symbols stay one column" do
      assert CharacterWidth.grapheme("→") == 1
      assert CharacterWidth.grapheme("✓") == 1
      assert CharacterWidth.grapheme("⚠") == 1
    end

    test "variation selector 16 promotes to emoji presentation" do
      assert CharacterWidth.grapheme("⚠️") == 2
      assert CharacterWidth.grapheme("✓️") == 2
    end

    test "variation selector 15 keeps text presentation" do
      assert CharacterWidth.grapheme("✅︎") == 1
    end

    test "zwj sequences occupy a single emoji cell" do
      assert CharacterWidth.string("👨‍👩‍👧") == 2
      assert CharacterWidth.string("👩‍💻") == 2
    end

    test "flag sequences occupy a single emoji cell" do
      assert CharacterWidth.string("🇯🇵") == 2
    end

    test "skin tone modifiers do not add columns" do
      assert CharacterWidth.string("👍🏽") == 2
    end
  end

  describe "box drawing and blocks" do
    test "box drawing is one column" do
      assert CharacterWidth.string("╭─╮│╰╯") == 6
      assert CharacterWidth.grapheme("█") == 1
      assert CharacterWidth.grapheme("▁") == 1
    end

    test "braille is one column" do
      assert CharacterWidth.grapheme("⣿") == 1
    end
  end

  describe "zero width formatting" do
    test "zero width space and joiner and bom take no columns" do
      assert CharacterWidth.grapheme(<<0x200B::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0xFEFF::utf8>>) == 0
      assert CharacterWidth.grapheme(<<0x2060::utf8>>) == 0
    end
  end

  describe "degenerate input" do
    test "empty string is zero" do
      assert CharacterWidth.grapheme("") == 0
      assert CharacterWidth.string("") == 0
    end
  end
end
