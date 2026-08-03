defmodule Drafter.Draw.Strip do
  @moduledoc """
  A horizontal line of `Drafter.Draw.Segment` structs representing one terminal row.

  Strips are the unit passed between widgets and the compositor. They track total
  display column width and a hash-based `cache_key` to skip redundant re-renders.
  Common operations include `crop/2`, `pad/2`, `combine/2`, `divide/2`, `slice/3`,
  `center/2`, and ANSI serialisation via `to_ansi/1`.

      iex> alias Drafter.Draw.{Segment, Strip}
      iex> strip = Strip.new([Segment.plain("ab"), Segment.new("cd", %{bold: true})])
      iex> Strip.width(strip)
      4
      iex> Strip.to_ansi(strip)
      "ab\\e[1mcd\\e[0m"

  """

  alias Drafter.Draw.Segment

  @type t :: %__MODULE__{
          segments: [Segment.t()],
          width: non_neg_integer(),
          cache_key: term()
        }

  defstruct segments: [], width: 0, cache_key: nil

  @doc """
  A strip holding `segments` in order.

  The strip's width is the sum of the segment widths, and its `cache_key` a hash
  of the segments.

  ## Examples

      iex> strip = Drafter.Draw.Strip.new([Drafter.Draw.Segment.plain("日本")])
      iex> strip.width
      4

  """
  @spec new([Segment.t()]) :: t()
  def new(segments) when is_list(segments) do
    width =
      Enum.reduce(segments, 0, fn segment, acc ->
        acc + Segment.width(segment)
      end)

    %__MODULE__{
      segments: segments,
      width: width,
      cache_key: make_cache_key(segments)
    }
  end

  @doc """
  A strip with no segments and zero width.

  ## Examples

      iex> Drafter.Draw.Strip.empty()
      %Drafter.Draw.Strip{segments: [], width: 0, cache_key: nil}

  """
  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @doc """
  A strip of one unstyled segment holding `text`.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("hi").segments
      [%Drafter.Draw.Segment{text: "hi", style: %{}, width: 2}]

  """
  @spec from_text(String.t()) :: t()
  def from_text(text) do
    segment = Segment.plain(text)
    new([segment])
  end

  @doc """
  Cut the strip down to `crop_width` display columns.

  A strip already that narrow is returned unchanged, and a `crop_width` of zero or
  less gives an empty strip. The segment straddling the boundary is cropped and
  the segments past it are dropped.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.crop(3)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hel"

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.crop(0)
      ...> |> Drafter.Draw.Strip.width()
      0

  """
  @spec crop(t(), non_neg_integer()) :: t()
  def crop(%__MODULE__{segments: segments, width: width} = strip, crop_width) do
    cond do
      crop_width >= width ->
        strip

      crop_width <= 0 ->
        empty()

      true ->
        {cropped_segments, _remaining_width} = crop_segments(segments, crop_width)
        new(cropped_segments)
    end
  end

  @doc """
  Narrow a strip to `width`.

  `mode` defaults to `:clip`, which cuts at the boundary. `:ellipsis` cuts at
  `width - 1` and appends `…` in the trailing segment's style. A strip already
  within `width` is returned unchanged, and a `width` of zero or less clips
  whatever the mode.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.overflow(3)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hel"

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.overflow(3, :ellipsis)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "he…"

      iex> Drafter.Draw.Strip.from_text("hi")
      ...> |> Drafter.Draw.Strip.overflow(5, :ellipsis)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hi"

  """
  @spec overflow(t(), non_neg_integer(), :clip | :ellipsis) :: t()
  def overflow(strip, width, mode \\ :clip)

  def overflow(%__MODULE__{} = strip, width, :ellipsis) when width > 0 do
    if strip.width <= width do
      strip
    else
      ellipsis = Segment.new("…", trailing_style(strip))
      strip |> crop(max(0, width - 1)) |> append(ellipsis)
    end
  end

  def overflow(%__MODULE__{} = strip, width, _mode), do: crop(strip, width)

  defp trailing_style(%__MODULE__{segments: []}), do: %{}
  defp trailing_style(%__MODULE__{segments: segments}), do: List.last(segments).style

  @doc """
  The strip at exactly `target_width` columns, cropped or space-padded on the right.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.fit_to_width(3)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hel"

      iex> Drafter.Draw.Strip.from_text("hi")
      ...> |> Drafter.Draw.Strip.fit_to_width(4)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hi  "

  """
  @spec fit_to_width(t(), non_neg_integer()) :: t()
  def fit_to_width(strip, target_width) do
    strip |> crop(target_width) |> pad(target_width)
  end

  @doc """
  Append an unstyled run of spaces until the strip is `target_width` columns wide,
  or return it unchanged if it already is.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("ab")
      ...> |> Drafter.Draw.Strip.pad(5)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "ab   "

  """
  @spec pad(t(), non_neg_integer()) :: t()
  def pad(%__MODULE__{segments: segments, width: width} = strip, target_width) do
    if target_width > width do
      padding_width = target_width - width
      padding_segment = Segment.new(String.duplicate(" ", padding_width))
      new(segments ++ [padding_segment])
    else
      strip
    end
  end

  @doc """
  A strip whose segments are the first strip's followed by the second's.

  Segments are never merged, even when their styles are equal.

  ## Examples

      iex> left = Drafter.Draw.Strip.from_text("ab")
      iex> right = Drafter.Draw.Strip.from_text("cd")
      iex> combined = Drafter.Draw.Strip.combine(left, right)
      iex> {Drafter.Draw.Strip.to_plain_text(combined), length(combined.segments)}
      {"abcd", 2}

  """
  @spec combine(t(), t()) :: t()
  def combine(%__MODULE__{segments: segments1}, %__MODULE__{segments: segments2}) do
    new(segments1 ++ segments2)
  end

  @doc """
  Merge `style` into every segment's style, `style` winning on shared keys.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("ab")
      ...> |> Drafter.Draw.Strip.apply_style(%{bold: true})
      ...> |> Map.fetch!(:segments)
      [%Drafter.Draw.Segment{text: "ab", style: %{bold: true}, width: 2}]

  """
  @spec apply_style(t(), Segment.style()) :: t()
  def apply_style(%__MODULE__{segments: segments}, style) do
    styled_segments = Enum.map(segments, &Segment.apply_style(&1, style))
    new(styled_segments)
  end

  @doc """
  The row as one ANSI string.

  Style codes carry across segments: a segment whose style equals the previous
  one's emits only its text, and a segment that adds keys emits only the codes for
  those keys. A full reset (`\\e[0m`) is emitted before a segment that drops a key
  the previous segment had set, and once more at the end of the row unless the last
  segment is unstyled.

  ## Examples

      iex> alias Drafter.Draw.{Segment, Strip}
      iex> Strip.new([Segment.plain("ab"), Segment.new("cd", %{bold: true})])
      ...> |> Strip.to_ansi()
      "ab\\e[1mcd\\e[0m"

      iex> alias Drafter.Draw.{Segment, Strip}
      iex> Strip.new([
      ...>   Segment.new("A", %{bold: true}),
      ...>   Segment.new("B", %{bold: true, italic: true}),
      ...>   Segment.plain("C")
      ...> ])
      ...> |> Strip.to_ansi()
      "\\e[1mA\\e[3mB\\e[0mC"

  """
  @spec to_ansi(t()) :: String.t()
  def to_ansi(%__MODULE__{segments: segments}) do
    {parts, last_style} =
      Enum.reduce(segments, {[], %{}}, fn %{text: text, style: style}, {acc, previous} ->
        {[[transition(previous, style), text] | acc], style}
      end)

    parts
    |> Enum.reverse()
    |> then(&IO.iodata_to_binary([&1, trailing_reset(last_style)]))
  end

  defp trailing_reset(style) when style == %{}, do: ""
  defp trailing_reset(_style), do: "\e[0m"

  defp transition(previous, style) when previous == style, do: ""

  defp transition(previous, style) do
    if needs_reset?(previous, style) do
      ["\e[0m", Segment.style_codes(style)]
    else
      Segment.style_codes(newly_set(previous, style))
    end
  end

  defp needs_reset?(previous, style) do
    Enum.any?(previous, fn {key, value} ->
      set?(value) and not set?(Map.get(style, key))
    end)
  end

  defp newly_set(previous, style) do
    for {key, value} <- style, Map.get(previous, key) != value, into: %{}, do: {key, value}
  end

  defp set?(false), do: false
  defp set?(nil), do: false
  defp set?(_value), do: true

  @doc """
  The strip's width in display columns.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("日本") |> Drafter.Draw.Strip.width()
      4

  """
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{width: width}), do: width

  @doc """
  Whether the strip has no segments, or every segment has empty text.

  ## Examples

      iex> Drafter.Draw.Strip.empty() |> Drafter.Draw.Strip.empty?()
      true

      iex> Drafter.Draw.Strip.from_text("") |> Drafter.Draw.Strip.empty?()
      true

      iex> Drafter.Draw.Strip.from_text(" ") |> Drafter.Draw.Strip.empty?()
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{segments: []}), do: true

  def empty?(%__MODULE__{segments: segments}) do
    Enum.all?(segments, &Segment.empty?/1)
  end

  @doc """
  Split the strip into `{left, right}` at display column `position`.

  `left` is `position` columns wide. A `position` of zero or less puts everything
  in `right`; a `position` at or past the strip's width puts everything in `left`.
  A segment straddling the split is divided between the two, both halves keeping
  its style.

  ## Examples

      iex> {left, right} = Drafter.Draw.Strip.divide(Drafter.Draw.Strip.from_text("hello"), 2)
      iex> {Drafter.Draw.Strip.to_plain_text(left), Drafter.Draw.Strip.to_plain_text(right)}
      {"he", "llo"}

      iex> {left, right} = Drafter.Draw.Strip.divide(Drafter.Draw.Strip.from_text("hello"), 0)
      iex> {Drafter.Draw.Strip.to_plain_text(left), Drafter.Draw.Strip.to_plain_text(right)}
      {"", "hello"}

      iex> {left, right} = Drafter.Draw.Strip.divide(Drafter.Draw.Strip.from_text("hello"), 9)
      iex> {Drafter.Draw.Strip.to_plain_text(left), Drafter.Draw.Strip.to_plain_text(right)}
      {"hello", ""}

  """
  @spec divide(t(), non_neg_integer()) :: {t(), t()}
  def divide(%__MODULE__{segments: segments} = strip, position) do
    cond do
      position <= 0 ->
        {empty(), strip}

      position >= strip.width ->
        {strip, empty()}

      true ->
        {left_segments, right_segments} = divide_segments(segments, position)
        {new(left_segments), new(right_segments)}
    end
  end

  @doc """
  The `length` columns of the strip beginning at display column `start`.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.slice(1, 3)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "ell"

  """
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: t()
  def slice(strip, start, length) do
    strip
    |> divide(start)
    |> elem(1)
    |> crop(length)
  end

  @doc """
  The strip centred in `target_width` columns between unstyled space padding.

  An odd remainder puts the extra column on the right. A strip at least as wide as
  `target_width` is cropped to it instead.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("ab")
      ...> |> Drafter.Draw.Strip.center(7)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "  ab   "

      iex> Drafter.Draw.Strip.from_text("hello")
      ...> |> Drafter.Draw.Strip.center(3)
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "hel"

  """
  @spec center(t(), non_neg_integer()) :: t()
  def center(%__MODULE__{width: width} = strip, target_width) do
    if target_width <= width do
      crop(strip, target_width)
    else
      padding = target_width - width
      left_padding = div(padding, 2)
      right_padding = padding - left_padding

      left_pad = Segment.new(String.duplicate(" ", left_padding))
      right_pad = Segment.new(String.duplicate(" ", right_padding))

      new([left_pad] ++ strip.segments ++ [right_pad])
    end
  end

  @doc """
  A strip with `segment` before the existing segments.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("bc")
      ...> |> Drafter.Draw.Strip.prepend(Drafter.Draw.Segment.plain("a"))
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "abc"

  """
  @spec prepend(t(), Segment.t()) :: t()
  def prepend(%__MODULE__{segments: segments}, segment) do
    new([segment | segments])
  end

  @doc """
  A strip with `segment` after the existing segments.

  ## Examples

      iex> Drafter.Draw.Strip.from_text("ab")
      ...> |> Drafter.Draw.Strip.append(Drafter.Draw.Segment.plain("c"))
      ...> |> Drafter.Draw.Strip.to_plain_text()
      "abc"

  """
  @spec append(t(), Segment.t()) :: t()
  def append(%__MODULE__{segments: segments}, segment) do
    new(segments ++ [segment])
  end

  @doc """
  The strip's segment text joined, with no style codes added.

  Any ANSI sequences already embedded in a segment's text are kept.

  ## Examples

      iex> alias Drafter.Draw.{Segment, Strip}
      iex> Strip.new([Segment.plain("ab"), Segment.new("cd", %{bold: true})])
      ...> |> Strip.to_plain_text()
      "abcd"

  """
  @spec to_plain_text(t()) :: String.t()
  def to_plain_text(%__MODULE__{segments: segments}) do
    Enum.map_join(segments, fn %Segment{text: text} -> text end)
  end

  defp crop_segments(segments, remaining_width, acc \\ [])

  defp crop_segments([], remaining_width, acc) do
    {Enum.reverse(acc), remaining_width}
  end

  defp crop_segments([segment | rest], remaining_width, acc) do
    segment_width = Segment.width(segment)

    cond do
      segment_width <= remaining_width ->
        crop_segments(rest, remaining_width - segment_width, [segment | acc])

      remaining_width > 0 ->
        cropped_segment = Segment.crop(segment, remaining_width)
        {Enum.reverse([cropped_segment | acc]), 0}

      true ->
        {Enum.reverse(acc), 0}
    end
  end

  defp divide_segments(segments, position, left_acc \\ [])

  defp divide_segments([], _position, left_acc) do
    {Enum.reverse(left_acc), []}
  end

  defp divide_segments([segment | rest] = segments, position, left_acc) do
    segment_width = Segment.width(segment)

    cond do
      segment_width < position ->
        divide_segments(rest, position - segment_width, [segment | left_acc])

      segment_width == position ->
        {Enum.reverse([segment | left_acc]), rest}

      position > 0 ->
        left_part = Segment.crop(segment, position)
        right_text = skip_display_width(segment.text, position)
        right_part = Segment.new(right_text, segment.style)

        {Enum.reverse([left_part | left_acc]), [right_part | rest]}

      true ->
        {Enum.reverse(left_acc), segments}
    end
  end

  defp make_cache_key(segments), do: :erlang.phash2(segments)

  defp skip_display_width(str, columns_to_skip) do
    if Drafter.CharacterWidth.printable_ascii?(str) do
      binary_part(str, columns_to_skip, byte_size(str) - columns_to_skip)
    else
      skip_mixed(str, columns_to_skip)
    end
  end

  defp skip_mixed(str, columns_to_skip) do
    ansi_pattern = ~r/\e\[[0-9;]*m/
    parts = Regex.split(ansi_pattern, str, include_captures: true)

    {_, result} =
      Enum.reduce(parts, {0, []}, fn part, {skipped, acc} ->
        skip_part(part, skipped, acc, columns_to_skip, ansi_pattern)
      end)

    IO.iodata_to_binary(result)
  end

  defp skip_part(part, skipped, acc, columns_to_skip, ansi_pattern) do
    cond do
      Regex.match?(ansi_pattern, part) and skipped >= columns_to_skip -> {skipped, [acc, part]}
      Regex.match?(ansi_pattern, part) -> {skipped, acc}
      true -> skip_graphemes(part, skipped, acc, columns_to_skip)
    end
  end

  defp skip_graphemes(text, skipped, acc, columns_to_skip) do
    text
    |> String.graphemes()
    |> Enum.reduce({skipped, acc}, fn grapheme, {w, a} ->
      gw = char_width(grapheme)
      if w >= columns_to_skip, do: {w + gw, [a, grapheme]}, else: {w + gw, a}
    end)
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)
end
