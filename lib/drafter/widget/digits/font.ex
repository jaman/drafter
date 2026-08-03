defmodule Drafter.Widget.Digits.Font do
  @moduledoc """
  The font catalogue for `Drafter.Widget.Digits`.

  Built-in fonts are monospaced and share one repertoire: digits, upper and
  lower case, and common punctuation. Lower case falls back to the upper-case
  glyph, and a character the font cannot draw renders as blanks of the font's
  widest glyph rather than raising.

  ## Built-in fonts

  | Name | Cell | Built from |
  |---|---|---|
  | `:block` | 7×5 | Box-drawing outlines. The default. |
  | `:compact` | 5×3 | The same outlines at half the height. |
  | `:tall` | 8×4 | Half blocks — 1×2 pixels a cell. |
  | `:pixel` | 4×4 | Quadrant blocks — 2×2 pixels a cell. |
  | `:braille` | 4×4 | Braille — 2×4 pixels a cell. |

  `:tall`, `:pixel` and `:braille` are rasterised at compile time from the 8×16
  bitmaps in `Drafter.Widget.Digits.Bitmap` by `Drafter.Widget.Digits.Raster`.
  See the [large text guide](large_text.md) for how to choose between them.

  ## FIGlet fonts

  `Drafter.Widget.Digits.Figlet` reads `.flf` files. Register one and it is used
  like any other font:

      {:ok, font} = Drafter.Widget.Digits.Figlet.load("fonts/slant.flf")
      Drafter.Widget.Digits.Font.register(:slant, font)
      digits("Vellum", font: :slant)

  FIGlet fonts are proportional, so `width/1` reports the widest glyph rather
  than a fixed cell. Measure a string with `text_width/2`.

  ## Examples

      iex> Drafter.Widget.Digits.Font.builtin_names()
      [:block, :braille, :compact, :pixel, :tall]

      iex> Drafter.Widget.Digits.Font.height(:block)
      5

      iex> Drafter.Widget.Digits.Font.glyph_width(:compact, "7")
      5

      iex> Drafter.Widget.Digits.Font.text_width(:compact, "42%")
      15

      iex> Drafter.Widget.Digits.Font.supports?(:block, "a")
      true

  """

  alias Drafter.Widget.Digits.Raster

  @space5 "     "
  @space7 "       "

  @block %{
    height: 5,
    width: 7,
    glyphs: %{
      "0" => ["╭─────╮", "│     │", "│     │", "│     │", "╰─────╯"],
      "1" => ["   ╭╴  ", "   │   ", "   │   ", "   │   ", " ──┴── "],
      "2" => ["╭─────╮", "      │", "╭─────╯", "│      ", "╰─────╴"],
      "3" => ["╭─────╮", "      │", " ─────┤", "      │", "╰─────╯"],
      "4" => ["╷     ╷", "│     │", "╰─────┤", "      │", "      ╵"],
      "5" => ["╭─────╴", "│      ", "╰─────╮", "      │", "╰─────╯"],
      "6" => ["╭─────╴", "│      ", "├─────╮", "│     │", "╰─────╯"],
      "7" => ["╶─────╮", "      │", "      │", "      │", "      ╵"],
      "8" => ["╭─────╮", "│     │", "├─────┤", "│     │", "╰─────╯"],
      "9" => ["╭─────╮", "│     │", "╰─────┤", "      │", "╶─────╯"],
      "A" => ["╭─────╮", "│     │", "├─────┤", "│     │", "╵     ╵"],
      "B" => ["├─────╮", "│     │", "├─────┤", "│     │", "├─────╯"],
      "C" => ["╭─────╴", "│      ", "│      ", "│      ", "╰─────╴"],
      "D" => ["├─────╮", "│     │", "│     │", "│     │", "├─────╯"],
      "E" => ["├─────╴", "│      ", "├─────╴", "│      ", "╰─────╴"],
      "F" => ["├─────╴", "│      ", "├─────╴", "│      ", "╵      "],
      "G" => ["╭─────╴", "│      ", "│   ──╮", "│     │", "╰─────╯"],
      "H" => ["╷     ╷", "│     │", "├─────┤", "│     │", "╵     ╵"],
      "I" => ["╶──┬──╴", "   │   ", "   │   ", "   │   ", "╶──┴──╴"],
      "J" => ["╶──┬──╴", "   │   ", "   │   ", "╷  │   ", "╰──╯   "],
      "K" => ["╷    ╱ ", "│   ╱  ", "├──┤   ", "│   ╲  ", "╵    ╲ "],
      "L" => ["╷      ", "│      ", "│      ", "│      ", "╰─────╴"],
      "M" => ["╭╮   ╭╮", "│╰╮ ╭╯│", "│ ╰─╯ │", "│     │", "╵     ╵"],
      "N" => ["╭╮    ╷", "│╰╮   │", "│ ╰╮  │", "│  ╰╮ │", "╵   ╰─╵"],
      "O" => ["╭─────╮", "│     │", "│     │", "│     │", "╰─────╯"],
      "P" => ["├─────╮", "│     │", "├─────╯", "│      ", "╵      "],
      "Q" => ["╭─────╮", "│     │", "│     │", "│   ╲ │", "╰─────╲"],
      "R" => ["├─────╮", "│     │", "├─────╯", "│   ╲  ", "╵    ╲ "],
      "S" => ["╭─────╴", "│      ", "╰─────╮", "      │", "╰─────╯"],
      "T" => ["╶──┬──╴", "   │   ", "   │   ", "   │   ", "   ╵   "],
      "U" => ["╷     ╷", "│     │", "│     │", "│     │", "╰─────╯"],
      "V" => ["╷     ╷", "╲     ╱", " ╲   ╱ ", "  ╲ ╱  ", "   ╵   "],
      "W" => ["╷     ╷", "│     │", "│ ╭─╮ │", "│╭╯ ╰╮│", "╰╯   ╰╯"],
      "X" => ["╲     ╱", " ╲   ╱ ", "  ╳    ", " ╱   ╲ ", "╱     ╲"],
      "Y" => ["╲     ╱", " ╲   ╱ ", "  ╰┬╯  ", "   │   ", "   ╵   "],
      "Z" => ["╶─────╮", "    ╱  ", "   ╱   ", "  ╱    ", "╰─────╴"],
      "." => ["       ", "       ", "       ", "       ", "   ▄   "],
      "," => ["       ", "       ", "       ", "   ▄   ", "  ╱    "],
      ":" => ["       ", "   ▄   ", "       ", "   ▄   ", "       "],
      ";" => ["       ", "   ▄   ", "       ", "   ▄   ", "  ╱    "],
      "-" => ["       ", "       ", " ───── ", "       ", "       "],
      "+" => ["       ", "   │   ", " ──┼── ", "   │   ", "       "],
      "=" => ["       ", " ───── ", "       ", " ───── ", "       "],
      "/" => ["      ╱", "     ╱ ", "   ╱   ", "  ╱    ", "╱      "],
      "\\" => ["╲      ", " ╲     ", "   ╲   ", "     ╲ ", "      ╲"],
      "*" => ["       ", " ╲ │ ╱ ", " ──┼── ", " ╱ │ ╲ ", "       "],
      "%" => ["╭╮   ╱ ", "╰╯  ╱  ", "   ╱   ", "  ╱ ╭╮ ", " ╱  ╰╯ "],
      "$" => ["  ╭──╴ ", "  ├──╮ ", " ─┼─  │", "  ╰──╯ ", "   ╵   "],
      "£" => [" ╭───╴ ", " │     ", "─┼──   ", " │     ", "╰────╴ "],
      "€" => [" ╭────╴", "─┼──   ", " │     ", "─┼──   ", " ╰────╴"],
      "¥" => ["╲     ╱", " ╲   ╱ ", "  ╰┬╯  ", " ──┼── ", " ──┼── "],
      "(" => ["   ╭─╴ ", "  ╱    ", "  │    ", "  ╲    ", "   ╰─╴ "],
      ")" => [" ╶─╮   ", "    ╲  ", "    │  ", "    ╱  ", " ╶─╯   "],
      "[" => ["  ╭──╴ ", "  │    ", "  │    ", "  │    ", "  ╰──╴ "],
      "]" => [" ╶──╮  ", "    │  ", "    │  ", "    │  ", " ╶──╯  "],
      "<" => ["     ╱ ", "   ╱   ", " ╱     ", "   ╲   ", "     ╲ "],
      ">" => [" ╲     ", "   ╲   ", "     ╱ ", "   ╱   ", " ╱     "],
      "!" => ["   │   ", "   │   ", "   │   ", "       ", "   ▄   "],
      "?" => ["╭─────╮", "      │", "   ╭──╯", "       ", "   ▄   "],
      "#" => [" ╷ ╷   ", "─┼─┼──╴", " │ │   ", "─┼─┼──╴", " ╵ ╵   "],
      "@" => ["╭─────╮", "│ ╭─╮ │", "│ │ │ │", "│ ╰───╯", "╰─────╴"],
      "'" => ["   │   ", "       ", "       ", "       ", "       "],
      "\"" => ["  │ │  ", "       ", "       ", "       ", "       "],
      "_" => ["       ", "       ", "       ", "       ", "╶─────╴"],
      "°" => ["  ╭─╮  ", "  ╰─╯  ", "       ", "       ", "       "],
      " " => [@space7, @space7, @space7, @space7, @space7]
    }
  }

  @compact %{
    height: 3,
    width: 5,
    glyphs: %{
      "0" => ["╭───╮", "│   │", "╰───╯"],
      "1" => ["  ╭╴ ", "  │  ", " ─┴─ "],
      "2" => ["╭───╮", "╭───╯", "╰───╴"],
      "3" => ["╭───╮", " ───┤", "╰───╯"],
      "4" => ["╷   ╷", "╰───┤", "    ╵"],
      "5" => ["╭───╴", "╰───╮", "╰───╯"],
      "6" => ["╭───╴", "├───╮", "╰───╯"],
      "7" => ["╶───╮", "    │", "    ╵"],
      "8" => ["╭───╮", "├───┤", "╰───╯"],
      "9" => ["╭───╮", "╰───┤", "╶───╯"],
      "A" => ["╭───╮", "├───┤", "╵   ╵"],
      "B" => ["├───╮", "├───┤", "├───╯"],
      "C" => ["╭───╴", "│    ", "╰───╴"],
      "D" => ["├───╮", "│   │", "├───╯"],
      "E" => ["├───╴", "├──╴ ", "╰───╴"],
      "F" => ["├───╴", "├──╴ ", "╵    "],
      "G" => ["╭───╴", "│ ──╮", "╰───╯"],
      "H" => ["╷   ╷", "├───┤", "╵   ╵"],
      "I" => ["╶─┬─╴", "  │  ", "╶─┴─╴"],
      "J" => ["╶─┬─╴", "  │  ", "╰─╯  "],
      "K" => ["╷  ╱ ", "├─┤  ", "╵  ╲ "],
      "L" => ["╷    ", "│    ", "╰───╴"],
      "M" => ["╭╮ ╭╮", "│╰─╯│", "╵   ╵"],
      "N" => ["╭╮  ╷", "│╰╮ │", "╵ ╰─╵"],
      "O" => ["╭───╮", "│   │", "╰───╯"],
      "P" => ["├───╮", "├───╯", "╵    "],
      "Q" => ["╭───╮", "│  ╲│", "╰───╲"],
      "R" => ["├───╮", "├──╯ ", "╵  ╲ "],
      "S" => ["╭───╴", "╰───╮", "╰───╯"],
      "T" => ["╶─┬─╴", "  │  ", "  ╵  "],
      "U" => ["╷   ╷", "│   │", "╰───╯"],
      "V" => ["╷   ╷", "╲  ╱ ", "  ╵  "],
      "W" => ["╷   ╷", "│╭─╮│", "╰╯ ╰╯"],
      "X" => ["╲  ╱ ", " ╳   ", "╱  ╲ "],
      "Y" => ["╲  ╱ ", " ╰┬╯ ", "  ╵  "],
      "Z" => ["╶───╮", "  ╱  ", "╰───╴"],
      "." => ["     ", "     ", "  ▄  "],
      "," => ["     ", "  ▄  ", " ╱   "],
      ":" => ["  ▄  ", "     ", "  ▄  "],
      ";" => ["  ▄  ", "     ", " ╱   "],
      "-" => ["     ", " ─── ", "     "],
      "+" => ["  │  ", "─┼─  ", "  │  "],
      "=" => [" ─── ", "     ", " ─── "],
      "/" => ["    ╱", "  ╱  ", "╱    "],
      "\\" => ["╲    ", "  ╲  ", "    ╲"],
      "*" => [" ╲│╱ ", " ─┼─ ", " ╱│╲ "],
      "%" => ["╭╮ ╱ ", "  ╱  ", " ╱ ╰╯"],
      "$" => [" ╭─╴ ", "─┼─╮ ", " ╰─╯ "],
      "£" => [" ╭──╴", "─┼─  ", "╰───╴"],
      "€" => [" ╭──╴", "═╪═  ", " ╰──╴"],
      "¥" => ["╲  ╱ ", "═╪═  ", "═╪═  "],
      "(" => ["  ╭╴ ", "  │  ", "  ╰╴ "],
      ")" => [" ╶╮  ", "  │  ", " ╶╯  "],
      "[" => [" ╭──╴", " │   ", " ╰──╴"],
      "]" => ["╶──╮ ", "   │ ", "╶──╯ "],
      "<" => ["   ╱ ", " ╱   ", "   ╲ "],
      ">" => [" ╲   ", "   ╱ ", " ╱   "],
      "!" => ["  │  ", "  │  ", "  ▄  "],
      "?" => ["╭───╮", "  ╭─╯", "  ▄  "],
      "#" => ["─┼┼─╴", " ││  ", "─┼┼─╴"],
      "@" => ["╭───╮", "│╭╮ │", "╰──╴ "],
      "'" => ["  │  ", "     ", "     "],
      "\"" => [" │ │ ", "     ", "     "],
      "_" => ["     ", "     ", "╶───╴"],
      "°" => [" ╭─╮ ", " ╰─╯ ", "     "],
      " " => [@space5, @space5, @space5]
    }
  }

  @braille Raster.font(:braille)
  @pixel Raster.font(:quadrant)
  @tall Raster.font(:half)

  @builtin %{
    block: @block,
    compact: @compact,
    braille: @braille,
    pixel: @pixel,
    tall: @tall
  }

  @registry {__MODULE__, :registered}

  @type name :: :block | :compact | :braille | :pixel | :tall | atom()
  @type font :: %{
          height: pos_integer(),
          width: pos_integer(),
          glyphs: %{String.t() => [String.t()]}
        }

  @doc "Every font name available, built in and registered."
  @spec names() :: [name()]
  def names, do: (Map.keys(@builtin) ++ Map.keys(registered())) |> Enum.uniq() |> Enum.sort()

  @doc "The names of the fonts compiled into the library."
  @spec builtin_names() :: [name()]
  def builtin_names, do: @builtin |> Map.keys() |> Enum.sort()

  @doc """
  Adds a font under `name`, making it available as `digits(text, font: name)`.

  Registered fonts live for the life of the node. A registered name takes
  precedence over a built-in one of the same name.
  """
  @spec register(atom(), font()) :: :ok
  def register(name, %{height: _, width: _, glyphs: _} = font) when is_atom(name) do
    :persistent_term.put(@registry, Map.put(registered(), name, font))
  end

  @doc "Removes a registered font. Built-in fonts are unaffected."
  @spec unregister(atom()) :: :ok
  def unregister(name) do
    :persistent_term.put(@registry, Map.delete(registered(), name))
  end

  @doc "Every registered font, keyed by name."
  @spec registered() :: %{atom() => font()}
  def registered, do: :persistent_term.get(@registry, %{})

  @doc """
  Looks up a font by name, falling back to `:block` for an unknown name.

  A font map is returned as given, so one loaded by
  `Drafter.Widget.Digits.Figlet.load/1` may be passed straight through without
  registering it.
  """
  @spec get(name() | font() | term()) :: font()
  def get(%{height: _, width: _, glyphs: _} = font), do: font
  def get(name), do: Map.get(registered(), name) || Map.get(@builtin, name) || @block

  @doc "Row height of a font's glyphs."
  @spec height(name() | font()) :: pos_integer()
  def height(name), do: get(name).height

  @doc """
  Column width of the widest glyph in a font.

  FIGlet fonts are proportional; use `glyph_width/2` or `text_width/2` to
  measure what will actually be drawn.
  """
  @spec width(name() | font()) :: pos_integer()
  def width(name), do: get(name).width

  @doc """
  The rows of one character, upper-casing when a font has no lower-case form.

  A character the font cannot draw yields blanks of the font's widest glyph.
  """
  @spec glyph(name() | font(), String.t()) :: [String.t()]
  def glyph(name, character) do
    font = get(name)

    Map.get(font.glyphs, character) ||
      Map.get(font.glyphs, String.upcase(character)) ||
      blank(font)
  end

  @doc "Columns one character occupies in a font."
  @spec glyph_width(name() | font(), String.t()) :: non_neg_integer()
  def glyph_width(name, character) do
    case glyph(name, character) do
      [] -> 0
      [row | _] -> String.length(row)
    end
  end

  @doc "Columns a whole string occupies in a font."
  @spec text_width(name() | font(), String.t()) :: non_neg_integer()
  def text_width(name, text) do
    font = get(name)

    text
    |> String.graphemes()
    |> Enum.reduce(0, &(&2 + glyph_width(font, &1)))
  end

  @doc "Whether a font can draw a character in some form."
  @spec supports?(name() | font(), String.t()) :: boolean()
  def supports?(name, character) do
    font = get(name)
    Map.has_key?(font.glyphs, character) or Map.has_key?(font.glyphs, String.upcase(character))
  end

  @doc "Every character a font can draw, sorted."
  @spec repertoire(name() | font()) :: [String.t()]
  def repertoire(name), do: get(name).glyphs |> Map.keys() |> Enum.sort()

  defp blank(font), do: List.duplicate(String.duplicate(" ", font.width), font.height)
end
