defmodule Drafter.Draw.BoxDrawing do
  @moduledoc """
  Unicode box drawing characters, and functions that assemble them into lines,
  boxes and borders.

  A *line type* selects a character set: `:light`, `:heavy` and `:double` have
  their own sets, and `:rounded` is available through `get_chars/1` and
  `border_style_chars/1`. Any other line type falls back to `:light`.

  Each set is a map keyed by `:horizontal`, `:vertical`, `:top_left`,
  `:top_right`, `:bottom_left`, `:bottom_right`, `:cross`, `:tee_up`,
  `:tee_down`, `:tee_left` and `:tee_right`.

      iex> Drafter.Draw.BoxDrawing.draw_box(3, 3, :heavy)
      ["┏━┓", "┃ ┃", "┗━┛"]
  """

  @type line_type :: :light | :heavy | :double | :dotted | :dashed
  @type border_style :: :none | :solid | :rounded | :thick | :double

  @box_chars %{
    light: %{
      horizontal: "─",
      vertical: "│",
      top_left: "┌",
      top_right: "┐",
      bottom_left: "└",
      bottom_right: "┘",
      cross: "┼",
      tee_up: "┴",
      tee_down: "┬",
      tee_left: "┤",
      tee_right: "├"
    },
    heavy: %{
      horizontal: "━",
      vertical: "┃",
      top_left: "┏",
      top_right: "┓",
      bottom_left: "┗",
      bottom_right: "┛",
      cross: "╋",
      tee_up: "┻",
      tee_down: "┳",
      tee_left: "┫",
      tee_right: "┣"
    },
    double: %{
      horizontal: "═",
      vertical: "║",
      top_left: "╔",
      top_right: "╗",
      bottom_left: "╚",
      bottom_right: "╝",
      cross: "╬",
      tee_up: "╩",
      tee_down: "╦",
      tee_left: "╣",
      tee_right: "╠"
    },
    rounded: %{
      horizontal: "─",
      vertical: "│",
      top_left: "╭",
      top_right: "╮",
      bottom_left: "╰",
      bottom_right: "╯",
      cross: "┼",
      tee_up: "┴",
      tee_down: "┬",
      tee_left: "┤",
      tee_right: "├"
    }
  }

  @doc """
  The character set for a line type.

  Returns the `:light` set for any line type that has no set of its own, which is
  the case for `:dotted` and `:dashed`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.get_chars(:double).cross
      "╬"

      iex> Drafter.Draw.BoxDrawing.get_chars(:dotted).top_left
      "┌"

  """
  @spec get_chars(line_type() | :rounded) :: map()
  def get_chars(style) do
    Map.get(@box_chars, style, @box_chars.light)
  end

  @doc """
  One character from a line type's set, named by `char_type`.

  Returns a single space when the set has no such key.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.get_char(:heavy, :vertical)
      "┃"

      iex> Drafter.Draw.BoxDrawing.get_char(:light, :diagonal)
      " "

  """
  @spec get_char(line_type() | :rounded, atom()) :: String.t()
  def get_char(style, char_type) do
    chars = get_chars(style)
    Map.get(chars, char_type, " ")
  end

  @doc """
  A string of `width` horizontal line characters in `style`, which defaults to `:light`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.horizontal_line(4)
      "────"

      iex> Drafter.Draw.BoxDrawing.horizontal_line(4, :double)
      "════"

  """
  @spec horizontal_line(non_neg_integer(), line_type() | :rounded) :: String.t()
  def horizontal_line(width, style \\ :light) do
    char = get_char(style, :horizontal)
    String.duplicate(char, width)
  end

  @doc """
  A list of `height` vertical line characters in `style`, one per row.

  `style` defaults to `:light`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.vertical_line(2, :heavy)
      ["┃", "┃"]

  """
  @spec vertical_line(non_neg_integer(), line_type() | :rounded) :: [String.t()]
  def vertical_line(height, style \\ :light) do
    char = get_char(style, :vertical)
    List.duplicate(char, height)
  end

  @doc """
  An empty box `width` columns wide and `height` rows tall, one string per row.

  The interior is filled with spaces. `style` defaults to `:light`. `width` and
  `height` must both be at least 2; a smaller value raises `FunctionClauseError`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.draw_box(4, 3)
      ["┌──┐", "│  │", "└──┘"]

      iex> Drafter.Draw.BoxDrawing.draw_box(2, 2, :rounded)
      ["╭╮", "╰╯"]

  """
  @spec draw_box(non_neg_integer(), non_neg_integer(), line_type() | :rounded) :: [String.t()]
  def draw_box(width, height, style \\ :light) when width >= 2 and height >= 2 do
    chars = get_chars(style)

    top_line =
      chars.top_left <>
        String.duplicate(chars.horizontal, width - 2) <>
        chars.top_right

    middle_line =
      chars.vertical <>
        String.duplicate(" ", width - 2) <>
        chars.vertical

    middle_lines = List.duplicate(middle_line, height - 2)

    bottom_line =
      chars.bottom_left <>
        String.duplicate(chars.horizontal, width - 2) <>
        chars.bottom_right

    [top_line] ++ middle_lines ++ [bottom_line]
  end

  @doc """
  A box drawn around `content_lines`, one string per row.

  The box is as wide as the longest line, which is measured with
  `String.length/1` and so counts double-width characters as one column. Shorter
  lines are padded on the right. An empty list gives a 2x2 empty box. `style`
  defaults to `:light`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.draw_box_with_content(["hi", "there"])
      ["┌─────┐", "│hi   │", "│there│", "└─────┘"]

      iex> Drafter.Draw.BoxDrawing.draw_box_with_content([])
      ["┌┐", "└┘"]

  """
  @spec draw_box_with_content([String.t()], line_type() | :rounded) :: [String.t()]
  def draw_box_with_content(content_lines, style \\ :light) do
    if Enum.empty?(content_lines) do
      draw_box(2, 2, style)
    else
      max_width = content_lines |> Enum.map(&String.length/1) |> Enum.max()
      chars = get_chars(style)

      top_line =
        chars.top_left <>
          String.duplicate(chars.horizontal, max_width) <>
          chars.top_right

      padded_content =
        Enum.map(content_lines, fn line ->
          padding = max_width - String.length(line)
          chars.vertical <> line <> String.duplicate(" ", padding) <> chars.vertical
        end)

      bottom_line =
        chars.bottom_left <>
          String.duplicate(chars.horizontal, max_width) <>
          chars.bottom_right

      [top_line] ++ padded_content ++ [bottom_line]
    end
  end

  @doc """
  The character to draw where `char2` is written over `char1`.

  A space on either side yields the other character, and two equal characters
  yield that character. Any other pair yields `char2`; no junction character is
  derived from the two line segments.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.combine_chars(" ", "│")
      "│"

      iex> Drafter.Draw.BoxDrawing.combine_chars("─", " ")
      "─"

      iex> Drafter.Draw.BoxDrawing.combine_chars("─", "│")
      "│"

  """
  @spec combine_chars(String.t(), String.t()) :: String.t()
  def combine_chars(char1, char2) do
    cond do
      char1 == " " -> char2
      char2 == " " -> char1
      char1 == char2 -> char1
      true -> char2
    end
  end

  @doc """
  The character set for a border style.

  `:none` gives an empty map; `:solid`, `:rounded`, `:thick` and `:double` give
  the `:light`, `:rounded`, `:heavy` and `:double` line-type sets. Any other value
  raises `FunctionClauseError`.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.border_style_chars(:none)
      %{}

      iex> Drafter.Draw.BoxDrawing.border_style_chars(:rounded).top_left
      "╭"

      iex> Drafter.Draw.BoxDrawing.border_style_chars(:thick).vertical
      "┃"

  """
  @spec border_style_chars(border_style()) :: map()
  def border_style_chars(:none), do: %{}
  def border_style_chars(:solid), do: get_chars(:light)
  def border_style_chars(:rounded), do: get_chars(:rounded)
  def border_style_chars(:thick), do: get_chars(:heavy)
  def border_style_chars(:double), do: get_chars(:double)

  @doc """
  A box drawn around `content_lines` with `title` centred on the top edge.

  The box is as wide as the longer of the longest content line and `title` plus
  two, so a title always has a line character on either side. An odd remainder puts
  the extra line character on the right of the title. A `:none` border style returns
  `content_lines` unchanged and ignores `title`. An empty `content_lines` gives one
  blank interior row.

  ## Examples

      iex> Drafter.Draw.BoxDrawing.draw_border_with_title(["ab"], "T", :solid)
      ["┌─T─┐", "│ab │", "└───┘"]

      iex> Drafter.Draw.BoxDrawing.draw_border_with_title(["abcdef"], "T", :solid)
      ["┌──T───┐", "│abcdef│", "└──────┘"]

      iex> Drafter.Draw.BoxDrawing.draw_border_with_title(["ab"], "T", :none)
      ["ab"]

  """
  @spec draw_border_with_title([String.t()], String.t(), border_style()) :: [String.t()]
  def draw_border_with_title(content_lines, _title, :none), do: content_lines

  def draw_border_with_title(content_lines, title, style) do
    chars = border_style_chars(style)
    max_width = content_max_width(content_lines)
    title_width = String.length(title)
    box_content_width = max(max_width, title_width + 2)

    top_line = build_title_top_line(chars, title, box_content_width, title_width)
    padded_content = pad_content_lines(content_lines, chars, box_content_width)

    bottom_line =
      chars.bottom_left <>
        String.duplicate(chars.horizontal, box_content_width) <>
        chars.bottom_right

    [top_line] ++ padded_content ++ [bottom_line]
  end

  defp content_max_width([]), do: 0

  defp content_max_width(content_lines) do
    content_lines |> Enum.map(&String.length/1) |> Enum.max()
  end

  defp build_title_top_line(chars, title, box_content_width, title_width) do
    title_padding = max(0, box_content_width - title_width - 2)
    left_title_pad = div(title_padding, 2)
    right_title_pad = title_padding - left_title_pad

    chars.top_left <>
      String.duplicate(chars.horizontal, left_title_pad + 1) <>
      title <>
      String.duplicate(chars.horizontal, right_title_pad + 1) <>
      chars.top_right
  end

  defp pad_content_lines([], chars, box_content_width) do
    [chars.vertical <> String.duplicate(" ", box_content_width) <> chars.vertical]
  end

  defp pad_content_lines(content_lines, chars, box_content_width) do
    Enum.map(content_lines, fn line ->
      padding = box_content_width - String.length(line)
      chars.vertical <> line <> String.duplicate(" ", padding) <> chars.vertical
    end)
  end
end
