defmodule Drafter.Text do
  @moduledoc """
  Unicode-aware text layout for terminal rendering.

  Wrapping, truncation, ellipsis, display-width measurement, and padding, all
  handling multi-byte graphemes and double-width CJK characters. Widths are in
  terminal display columns, not bytes or codepoints.

  ## Examples

      iex> Drafter.Text.display_width("漢字")
      4

      iex> Drafter.Text.wrap("the quick brown fox", 9, :word)
      ["the quick", "brown fox"]

      iex> Drafter.Text.truncate("abcdef", 3)
      "abc"

      iex> Drafter.Text.ellipsize("abcdef", 4)
      "abc…"

      iex> Drafter.Text.pad_center("hi", 6, ".")
      "..hi.."

  """

  @type wrap_mode :: :none | :char | :word

  @spec wrap(String.t(), non_neg_integer(), wrap_mode()) :: [String.t()]
  def wrap(text, width, mode \\ :word)

  def wrap(text, width, _mode) when width <= 0, do: [text]
  def wrap("", _width, _mode), do: [""]

  def wrap(text, width, :none) do
    text
    |> String.split("\n")
    |> Enum.map(&truncate(&1, width))
  end

  def wrap(text, width, :char) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line_char(&1, width))
  end

  def wrap(text, width, :word) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line_word(&1, width))
  end

  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(_text, width) when width <= 0, do: ""

  def truncate(text, width) do
    if display_width(text) <= width do
      text
    else
      text
      |> String.graphemes()
      |> truncate_graphemes(width, [])
      |> Enum.reverse()
      |> Enum.join()
    end
  end

  @spec ellipsize(String.t(), non_neg_integer(), String.t()) :: String.t()
  def ellipsize(text, width, ellipsis \\ "…")

  def ellipsize(_text, width, _ellipsis) when width <= 0, do: ""

  def ellipsize(text, width, ellipsis) do
    if display_width(text) <= width do
      text
    else
      ellipsis_width = display_width(ellipsis)
      content_width = max(0, width - ellipsis_width)
      truncate(text, content_width) <> ellipsis
    end
  end

  @spec display_width(String.t()) :: non_neg_integer()
  def display_width(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, acc ->
      acc + grapheme_width(grapheme)
    end)
  end

  @spec pad_right(String.t(), non_neg_integer(), String.t()) :: String.t()
  def pad_right(text, width, pad_char \\ " ") do
    current = display_width(text)

    if current >= width do
      text
    else
      text <> String.duplicate(pad_char, width - current)
    end
  end

  @spec pad_left(String.t(), non_neg_integer(), String.t()) :: String.t()
  def pad_left(text, width, pad_char \\ " ") do
    current = display_width(text)

    if current >= width do
      text
    else
      String.duplicate(pad_char, width - current) <> text
    end
  end

  @spec pad_center(String.t(), non_neg_integer(), String.t()) :: String.t()
  def pad_center(text, width, pad_char \\ " ") do
    current = display_width(text)

    if current >= width do
      text
    else
      total_pad = width - current
      left_pad = div(total_pad, 2)
      right_pad = total_pad - left_pad
      String.duplicate(pad_char, left_pad) <> text <> String.duplicate(pad_char, right_pad)
    end
  end

  defp wrap_line_char("", _width), do: [""]

  defp wrap_line_char(line, width) do
    if fits?(line, width) do
      [line]
    else
      line
      |> String.graphemes()
      |> chunk_by_width(width)
    end
  end

  defp wrap_line_word("", _width), do: [""]

  defp wrap_line_word(line, width) do
    if fits?(line, width) do
      [line]
    else
      line
      |> split_into_words()
      |> wrap_words(width, [], "")
    end
  end

  defp fits?(line, width), do: display_width(line) <= width

  defp split_into_words(line) do
    ~r/(\s+|\S+)/
    |> Regex.scan(line)
    |> Enum.map(&List.first/1)
  end

  defp wrap_words([], _width, lines, current) do
    Enum.reverse([current | lines])
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> [""]
      result -> result
    end
  end

  defp wrap_words([word | rest], width, lines, current) do
    word_width = display_width(word)
    current_width = display_width(current)
    is_whitespace = String.trim(word) == ""

    cond do
      current == "" and is_whitespace ->
        wrap_words(rest, width, lines, current)

      current == "" ->
        if word_width > width do
          wrapped = wrap_long_word(word, width)
          {complete, [last]} = Enum.split(wrapped, -1)
          wrap_words(rest, width, Enum.reverse(complete) ++ lines, last)
        else
          wrap_words(rest, width, lines, word)
        end

      current_width + word_width <= width ->
        wrap_words(rest, width, lines, current <> word)

      is_whitespace ->
        wrap_words(rest, width, [String.trim_trailing(current) | lines], "")

      true ->
        if word_width > width do
          wrapped = wrap_long_word(word, width)
          {complete, [last]} = Enum.split(wrapped, -1)

          wrap_words(
            rest,
            width,
            Enum.reverse(complete) ++ [String.trim_trailing(current) | lines],
            last
          )
        else
          wrap_words(rest, width, [String.trim_trailing(current) | lines], word)
        end
    end
  end

  defp wrap_long_word(word, width) do
    word
    |> String.graphemes()
    |> chunk_by_width(width)
  end

  defp chunk_by_width(graphemes, width) do
    chunk_by_width(graphemes, width, [], [], 0)
  end

  defp chunk_by_width([], _width, chunks, current, _current_width) do
    current_str = current |> Enum.reverse() |> Enum.join()

    Enum.reverse([current_str | chunks])
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> [""]
      result -> result
    end
  end

  defp chunk_by_width([g | rest], width, chunks, current, current_width) do
    g_width = grapheme_width(g)

    if current_width + g_width > width and current != [] do
      current_str = current |> Enum.reverse() |> Enum.join()
      chunk_by_width([g | rest], width, [current_str | chunks], [], 0)
    else
      chunk_by_width(rest, width, chunks, [g | current], current_width + g_width)
    end
  end

  defp truncate_graphemes([], _width, acc), do: acc

  defp truncate_graphemes([g | rest], width, acc) do
    g_width = grapheme_width(g)

    if g_width > width do
      acc
    else
      truncate_graphemes(rest, width - g_width, [g | acc])
    end
  end

  defp grapheme_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)
end
