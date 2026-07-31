defmodule Drafter.Draw.BoxDrawing do
  @moduledoc """
  Unicode box drawing characters and the rules for combining them.

  Provides character sets for each line type, functions for drawing boxes, lines
  and borders, and the junction character that results when two lines meet.
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

  @doc "Get box character set for given style"
  @spec get_chars(line_type()) :: map()
  def get_chars(style) do
    Map.get(@box_chars, style, @box_chars.light)
  end

  @doc "Get specific box drawing character"
  @spec get_char(line_type(), atom()) :: String.t()
  def get_char(style, char_type) do
    chars = get_chars(style)
    Map.get(chars, char_type, " ")
  end

  @doc "Draw horizontal line"
  @spec horizontal_line(non_neg_integer(), line_type()) :: String.t()
  def horizontal_line(width, style \\ :light) do
    char = get_char(style, :horizontal)
    String.duplicate(char, width)
  end

  @doc "Draw vertical line"
  @spec vertical_line(non_neg_integer(), line_type()) :: [String.t()]
  def vertical_line(height, style \\ :light) do
    char = get_char(style, :vertical)
    List.duplicate(char, height)
  end

  @doc "Draw a complete box"
  @spec draw_box(non_neg_integer(), non_neg_integer(), line_type()) :: [String.t()]
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

  @doc "Draw box with content"
  @spec draw_box_with_content([String.t()], line_type()) :: [String.t()]
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

  @doc "Combine two box characters logically"
  @spec combine_chars(String.t(), String.t()) :: String.t()
  def combine_chars(char1, char2) do
    cond do
      char1 == " " -> char2
      char2 == " " -> char1
      char1 == char2 -> char1
      true -> char2
    end
  end

  @doc "Get border style characters"
  @spec border_style_chars(border_style()) :: map()
  def border_style_chars(:none), do: %{}
  def border_style_chars(:solid), do: get_chars(:light)
  def border_style_chars(:rounded), do: get_chars(:rounded)
  def border_style_chars(:thick), do: get_chars(:heavy)
  def border_style_chars(:double), do: get_chars(:double)

  @doc "Draw border around content with title"
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
