defmodule Drafter.Draw.Segment do
  @moduledoc """
  The fundamental rendering unit: a string of text with a single style applied.

  A `%Segment{}` stores the text content, a style map, and the pre-computed
  display column width (accounting for double-width CJK and emoji codepoints).
  Style keys: `:fg` and `:bg` (RGB 3-tuples or color strings normalised to
  RGB), `:bold`, `:dim`, `:italic`, `:underline`, `:reverse` (booleans).
  Multiple segments are assembled into a `Drafter.Draw.Strip` to form a
  single terminal line.
  """

  @type style :: %{
          optional(:fg) => {0..255, 0..255, 0..255},
          optional(:bg) => {0..255, 0..255, 0..255},
          optional(:bold) => boolean(),
          optional(:dim) => boolean(),
          optional(:italic) => boolean(),
          optional(:underline) => boolean(),
          optional(:reverse) => boolean()
        }

  @type t :: %__MODULE__{
          text: String.t(),
          style: style(),
          width: non_neg_integer()
        }

  defstruct [:text, :style, :width]

  @doc "Create a new segment with text and optional style"
  @spec new(String.t(), style()) :: t()
  def new(text, style \\ %{}) do
    width = display_width(text)
    normalized_style = normalize_style(style)

    %__MODULE__{
      text: text,
      style: normalized_style,
      width: width
    }
  end

  defp normalize_style(style) when is_map(style) do
    style
    |> normalize_color(:fg)
    |> normalize_color(:bg)
  end

  defp normalize_color(style, key) do
    case Map.get(style, key) do
      nil -> style
      color -> Map.put(style, key, Drafter.Color.normalize(color))
    end
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)

  defp display_width(str) do
    str |> strip_ansi() |> Drafter.CharacterWidth.string()
  end

  defp strip_ansi(text) do
    String.replace(text, ~r/\e\[[0-9;]*m/, "")
  end

  @doc "Create a segment with plain text (no styling)"
  @spec plain(String.t()) :: t()
  def plain(text) do
    new(text, %{})
  end

  @doc "Apply style to existing segment"
  @spec apply_style(t(), style()) :: t()
  def apply_style(%__MODULE__{} = segment, style) do
    merged_style = Map.merge(segment.style, style)
    %{segment | style: merged_style}
  end

  @doc "Crop segment to specified width"
  @spec crop(t(), non_neg_integer()) :: t()
  def crop(%__MODULE__{text: text, width: width} = segment, crop_width) do
    cond do
      crop_width >= width ->
        segment

      crop_width <= 0 ->
        %{segment | text: "", width: 0}

      true ->
        cropped_text = truncate_to_display_width(text, crop_width)
        %{segment | text: cropped_text, width: display_width(cropped_text)}
    end
  end

  defp truncate_to_display_width(str, target_width) do
    ansi_pattern = ~r/\e\[[0-9;]*m/
    parts = Regex.split(ansi_pattern, str, include_captures: true)

    {result, _width} =
      Enum.reduce_while(parts, {"", 0}, fn part, {acc, width} ->
        truncate_part(part, acc, width, target_width, ansi_pattern)
      end)

    result
  end

  defp truncate_part(part, acc, width, target_width, ansi_pattern) do
    if Regex.match?(ansi_pattern, part) do
      {:cont, {acc <> part, width}}
    else
      {chunk, new_width} = truncate_graphemes_to_width(part, width, target_width)

      if new_width >= target_width and new_width > width do
        {:halt, {acc <> chunk, new_width}}
      else
        {:cont, {acc <> chunk, new_width}}
      end
    end
  end

  defp truncate_graphemes_to_width(text, starting_width, target_width) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({"", starting_width}, fn grapheme, {chunk_acc, w} ->
      new_w = w + char_width(grapheme)

      if new_w <= target_width do
        {:cont, {chunk_acc <> grapheme, new_w}}
      else
        {:halt, {chunk_acc, w}}
      end
    end)
  end

  @doc "Pad segment to specified width with spaces"
  @spec pad(t(), non_neg_integer()) :: t()
  def pad(%__MODULE__{text: text, width: width} = segment, target_width) do
    if target_width > width do
      padding = String.duplicate(" ", target_width - width)
      %{segment | text: text <> padding, width: target_width}
    else
      segment
    end
  end

  @doc "Convert segment to ANSI string for terminal output"
  @spec to_ansi(t()) :: String.t()
  def to_ansi(%__MODULE__{text: text, style: style}) do
    style_codes = build_style_codes(style)
    reset_code = if style == %{}, do: "", else: "\e[0m"

    "#{style_codes}#{text}#{reset_code}"
  end

  @doc "Get display width of segment"
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{width: width}), do: width

  @doc "Check if segment is empty"
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{text: text}), do: text == ""

  @style_flag_codes [
    {:bold, "1"},
    {:dim, "2"},
    {:italic, "3"},
    {:underline, "4"},
    {:reverse, "7"}
  ]

  defp build_style_codes(style) when style == %{}, do: ""

  defp build_style_codes(style) do
    codes =
      Enum.reduce(@style_flag_codes, [], fn {key, code}, acc ->
        if style[key], do: [code | acc], else: acc
      end)

    codes = add_color_code(codes, "38", style[:fg])
    codes = add_color_code(codes, "48", style[:bg])

    if codes == [] do
      ""
    else
      "\e[" <> Enum.join(Enum.reverse(codes), ";") <> "m"
    end
  end

  defp add_color_code(codes, _prefix, nil), do: codes
  defp add_color_code(codes, prefix, {r, g, b}), do: ["#{prefix};2;#{r};#{g};#{b}" | codes]
end
