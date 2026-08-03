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

  @typedoc """
  How `wrap/3` breaks a line that is wider than the target width.

    * `:none` - do not wrap; each input line is truncated to the width instead
    * `:char` - break anywhere, at grapheme boundaries
    * `:word` - break at whitespace, falling back to `:char` for a single word
      wider than the width
  """
  @type wrap_mode :: :none | :char | :word

  @doc """
  Break `text` into lines no wider than `width` display columns.

  Embedded newlines always start a new line, whatever the mode. `mode` defaults to
  `:word`. A `width` of `0` or less returns `[text]` unwrapped, and an empty string
  returns `[""]`. Trailing whitespace is trimmed from every wrapped line but leading
  whitespace on the first line is kept.

  ## Examples

      iex> Drafter.Text.wrap("the quick brown fox", 9, :word)
      ["the quick", "brown fox"]

      iex> Drafter.Text.wrap("the quick brown fox", 9)
      ["the quick", "brown fox"]

      iex> Drafter.Text.wrap("abcdefgh", 3, :char)
      ["abc", "def", "gh"]

      iex> Drafter.Text.wrap("abcdefgh", 3, :none)
      ["abc"]

      iex> Drafter.Text.wrap("one\\ntwo", 10, :word)
      ["one", "two"]

      iex> Drafter.Text.wrap("anything", 0, :word)
      ["anything"]

      iex> Drafter.Text.wrap("", 10, :word)
      [""]

  """
  @spec wrap(String.t(), integer(), wrap_mode()) :: [String.t()]
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

  @doc """
  Cut `text` down to at most `width` display columns.

  Nothing is appended. A double-width grapheme that would straddle the limit is
  dropped rather than half-drawn, so the result can be one column narrower than
  `width`. A `width` of `0` or less returns `""`.

  ## Examples

      iex> Drafter.Text.truncate("abcdef", 3)
      "abc"

      iex> Drafter.Text.truncate("abc", 10)
      "abc"

      iex> Drafter.Text.truncate("漢字", 3)
      "漢"

      iex> Drafter.Text.truncate("abc", 0)
      ""

  """
  @spec truncate(String.t(), integer()) :: String.t()
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

  @doc """
  Truncate `text` to `width` display columns, marking the cut with `ellipsis`.

  `ellipsis` defaults to `"…"` and its own display width counts towards `width`, so
  the result is never wider than `width`. Text that already fits is returned
  unchanged, with no ellipsis. A `width` of `0` or less returns `""`; a `width`
  smaller than the ellipsis itself returns just the ellipsis.

  ## Examples

      iex> Drafter.Text.ellipsize("abcdef", 4)
      "abc…"

      iex> Drafter.Text.ellipsize("abcd", 4)
      "abcd"

      iex> Drafter.Text.ellipsize("abcdef", 5, "...")
      "ab..."

      iex> Drafter.Text.ellipsize("abcdef", 1)
      "…"

  """
  @spec ellipsize(String.t(), integer(), String.t()) :: String.t()
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

  @doc """
  Width of `text` in terminal display columns.

  Measured per grapheme through `Drafter.CharacterWidth`, so a CJK ideograph counts
  two, a combining mark counts zero, and an emoji with a variation selector counts as
  a single cluster.

  ## Examples

      iex> Drafter.Text.display_width("abc")
      3

      iex> Drafter.Text.display_width("漢字")
      4

      iex> Drafter.Text.display_width("")
      0

  """
  @spec display_width(String.t()) :: non_neg_integer()
  def display_width(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, acc ->
      acc + grapheme_width(grapheme)
    end)
  end

  @doc """
  Pad `text` on the right to `width` display columns.

  `pad_char` defaults to `" "` and is repeated once per missing *column*, so a
  multi-column pad character overshoots. Text already at or over `width` is returned
  unchanged — this pads, it does not truncate.

  ## Examples

      iex> Drafter.Text.pad_right("hi", 5)
      "hi   "

      iex> Drafter.Text.pad_right("hi", 5, ".")
      "hi..."

      iex> Drafter.Text.pad_right("hello", 3)
      "hello"

  """
  @spec pad_right(String.t(), non_neg_integer(), String.t()) :: String.t()
  def pad_right(text, width, pad_char \\ " ") do
    current = display_width(text)

    if current >= width do
      text
    else
      text <> String.duplicate(pad_char, width - current)
    end
  end

  @doc """
  Pad `text` on the left to `width` display columns.

  `pad_char` defaults to `" "`. Text already at or over `width` is returned unchanged.

  ## Examples

      iex> Drafter.Text.pad_left("hi", 5)
      "   hi"

      iex> Drafter.Text.pad_left("42", 5, "0")
      "00042"

      iex> Drafter.Text.pad_left("hello", 3)
      "hello"

  """
  @spec pad_left(String.t(), non_neg_integer(), String.t()) :: String.t()
  def pad_left(text, width, pad_char \\ " ") do
    current = display_width(text)

    if current >= width do
      text
    else
      String.duplicate(pad_char, width - current) <> text
    end
  end

  @doc """
  Centre `text` within `width` display columns.

  `pad_char` defaults to `" "`. An odd amount of padding puts the extra column on the
  right. Text already at or over `width` is returned unchanged.

  ## Examples

      iex> Drafter.Text.pad_center("hi", 6, ".")
      "..hi.."

      iex> Drafter.Text.pad_center("hi", 5, ".")
      ".hi.."

      iex> Drafter.Text.pad_center("hello", 3)
      "hello"

  """
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
