defmodule Drafter.Draw.Strip do
  @moduledoc """
  A horizontal line of `Drafter.Draw.Segment` structs representing one terminal row.

  Strips are the unit passed between widgets and the compositor. They track total
  display column width and a hash-based `cache_key` to skip redundant re-renders.
  Common operations include `crop/2`, `pad/2`, `combine/2`, `divide/2`, `slice/3`,
  `center/2`, and ANSI serialisation via `to_ansi/1`.
  """

  alias Drafter.Draw.Segment

  @type t :: %__MODULE__{
          segments: [Segment.t()],
          width: non_neg_integer(),
          cache_key: term()
        }

  defstruct segments: [], width: 0, cache_key: nil

  @doc "Create a new strip from segments"
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

  @doc "Create an empty strip"
  @spec empty() :: t()
  def empty(), do: %__MODULE__{}

  @doc "Create strip from plain text"
  @spec from_text(String.t()) :: t()
  def from_text(text) do
    segment = Segment.plain(text)
    new([segment])
  end

  @doc "Crop strip to specified width"
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

  @doc "Pad strip to specified width with spaces"
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

  @doc "Combine two strips"
  @spec combine(t(), t()) :: t()
  def combine(%__MODULE__{segments: segments1}, %__MODULE__{segments: segments2}) do
    new(segments1 ++ segments2)
  end

  @doc "Apply style to all segments in strip"
  @spec apply_style(t(), Segment.style()) :: t()
  def apply_style(%__MODULE__{segments: segments}, style) do
    styled_segments = Enum.map(segments, &Segment.apply_style(&1, style))
    new(styled_segments)
  end

  @doc "Convert strip to ANSI string for terminal output"
  @spec to_ansi(t()) :: String.t()
  def to_ansi(%__MODULE__{segments: segments}) do
    Enum.map_join(segments, &Segment.to_ansi/1)
  end

  @doc "Get display width of strip"
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{width: width}), do: width

  @doc "Check if strip is empty"
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{segments: []}), do: true

  def empty?(%__MODULE__{segments: segments}) do
    Enum.all?(segments, &Segment.empty?/1)
  end

  @doc "Divide strip into two parts at specified position"
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

  @doc "Get slice of strip from start to end position"
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: t()
  def slice(strip, start, length) do
    strip
    |> divide(start)
    |> elem(1)
    |> crop(length)
  end

  @doc "Center strip within specified width"
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

  @doc "Prepend a segment to the strip"
  @spec prepend(t(), Segment.t()) :: t()
  def prepend(%__MODULE__{segments: segments}, segment) do
    new([segment | segments])
  end

  @doc "Append a segment to the strip"
  @spec append(t(), Segment.t()) :: t()
  def append(%__MODULE__{segments: segments}, segment) do
    new(segments ++ [segment])
  end

  @doc "Convert strip to plain text without styling"
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

  defp make_cache_key(segments) do
    segments
    |> Enum.map(fn %Segment{text: text, style: style} -> {text, style} end)
    |> :erlang.phash2()
  end

  defp skip_display_width(str, columns_to_skip) do
    ansi_pattern = ~r/\e\[[0-9;]*m/
    parts = Regex.split(ansi_pattern, str, include_captures: true)

    {_, result} =
      Enum.reduce(parts, {0, ""}, fn part, {skipped, acc} ->
        skip_part(part, skipped, acc, columns_to_skip, ansi_pattern)
      end)

    result
  end

  defp skip_part(part, skipped, acc, columns_to_skip, ansi_pattern) do
    cond do
      Regex.match?(ansi_pattern, part) and skipped >= columns_to_skip -> {skipped, acc <> part}
      Regex.match?(ansi_pattern, part) -> {skipped, acc}
      true -> skip_graphemes(part, skipped, acc, columns_to_skip)
    end
  end

  defp skip_graphemes(text, skipped, acc, columns_to_skip) do
    text
    |> String.graphemes()
    |> Enum.reduce({skipped, acc}, fn grapheme, {w, a} ->
      gw = char_width(grapheme)
      if w >= columns_to_skip, do: {w + gw, a <> grapheme}, else: {w + gw, a}
    end)
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)
end
