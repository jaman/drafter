defmodule Drafter.Draw.Segment do
  @moduledoc """
  The fundamental rendering unit: a string of text with a single style applied.

  A `%Segment{}` stores the text content, a style map, and the pre-computed
  display column width (accounting for double-width CJK and emoji codepoints).
  Style keys: `:fg` and `:bg` (RGB 3-tuples or color strings normalised to
  RGB), `:bold`, `:dim`, `:italic`, `:underline`, `:reverse` (booleans).
  Multiple segments are assembled into a `Drafter.Draw.Strip` to form a
  single terminal line.

      iex> Drafter.Draw.Segment.new("hi", %{bold: true})
      %Drafter.Draw.Segment{text: "hi", style: %{bold: true}, width: 2}

  """

  @type style :: %{
          optional(:fg) => {0..255, 0..255, 0..255},
          optional(:bg) => {0..255, 0..255, 0..255},
          optional(:fg_alpha) => float(),
          optional(:bg_alpha) => float(),
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

  @doc """
  A segment of `text` carrying `style`.

  The display width is measured on construction, with ANSI SGR sequences in `text`
  excluded from the count. Colour values in `style` are normalised to RGB triples,
  a translucent colour additionally storing its alpha under `alpha_key/1`.

  `style` defaults to `%{}`.

  ## Examples

      iex> Drafter.Draw.Segment.new("abc")
      %Drafter.Draw.Segment{text: "abc", style: %{}, width: 3}

      iex> Drafter.Draw.Segment.new("日本")
      %Drafter.Draw.Segment{text: "日本", style: %{}, width: 4}

      iex> Drafter.Draw.Segment.new("x", %{fg: "#ff0000"})
      %Drafter.Draw.Segment{text: "x", style: %{fg: {255, 0, 0}}, width: 1}

      iex> Drafter.Draw.Segment.new("x", %{fg: "rgba(255, 0, 0, 0.5)"})
      %Drafter.Draw.Segment{text: "x", style: %{fg: {255, 0, 0}, fg_alpha: 0.5}, width: 1}

  """
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
      color -> put_color(style, key, Drafter.Color.normalize_with_alpha(color))
    end
  end

  defp put_color(style, key, {rgb, alpha}) when alpha >= 1.0 do
    style |> Map.put(key, rgb) |> Map.delete(alpha_key(key))
  end

  defp put_color(style, key, {rgb, alpha}) do
    style |> Map.put(key, rgb) |> Map.put(alpha_key(key), alpha)
  end

  @doc """
  The style key holding the alpha channel for `:fg` or `:bg`.

  A translucent colour is stored as two style keys: the RGB triple under `:fg` or
  `:bg`, and its alpha, a float in `0.0..1.0`, under the key this returns. A style
  with no such key is fully opaque.

  Only the compositor reads these keys. It blends the colour against the cell
  beneath and removes the alpha key, so a style reaching the ANSI encoders never
  carries one.

  ## Examples

      iex> Drafter.Draw.Segment.alpha_key(:fg)
      :fg_alpha

      iex> Drafter.Draw.Segment.alpha_key(:bg)
      :bg_alpha

  """
  @spec alpha_key(:fg | :bg) :: :fg_alpha | :bg_alpha
  def alpha_key(:fg), do: :fg_alpha
  def alpha_key(:bg), do: :bg_alpha

  defp display_width(str) do
    case :binary.match(str, "\e") do
      :nomatch -> Drafter.CharacterWidth.string(str)
      _ -> str |> strip_ansi() |> Drafter.CharacterWidth.string()
    end
  end

  defp strip_ansi(text) do
    String.replace(text, ~r/\e\[[0-9;]*m/, "")
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)

  @doc """
  A segment of `text` with an empty style.

  ## Examples

      iex> Drafter.Draw.Segment.plain("héllo")
      %Drafter.Draw.Segment{text: "héllo", style: %{}, width: 5}

  """
  @spec plain(String.t()) :: t()
  def plain(text) do
    new(text, %{})
  end

  @doc """
  Merge `style` into the segment's own style, `style` winning on shared keys.

  Colour values are not normalised; pass RGB triples.

  ## Examples

      iex> Drafter.Draw.Segment.plain("x") |> Drafter.Draw.Segment.apply_style(%{bold: true})
      %Drafter.Draw.Segment{text: "x", style: %{bold: true}, width: 1}

      iex> segment = Drafter.Draw.Segment.new("x", %{bold: true, italic: true})
      iex> Drafter.Draw.Segment.apply_style(segment, %{bold: false}).style
      %{bold: false, italic: true}

  """
  @spec apply_style(t(), style()) :: t()
  def apply_style(%__MODULE__{} = segment, style) do
    merged_style = Map.merge(segment.style, style)
    %{segment | style: merged_style}
  end

  @doc """
  Cut the segment down to `crop_width` display columns.

  A segment already that narrow is returned unchanged, and a `crop_width` of zero
  or less gives an empty segment. A double-width grapheme that would straddle the
  boundary is dropped whole, so the result can be one column narrower than asked.
  ANSI SGR sequences in the text are preserved and cost no columns.

  ## Examples

      iex> Drafter.Draw.Segment.plain("hello") |> Drafter.Draw.Segment.crop(3)
      %Drafter.Draw.Segment{text: "hel", style: %{}, width: 3}

      iex> Drafter.Draw.Segment.plain("hello") |> Drafter.Draw.Segment.crop(9)
      %Drafter.Draw.Segment{text: "hello", style: %{}, width: 5}

      iex> Drafter.Draw.Segment.plain("hello") |> Drafter.Draw.Segment.crop(0)
      %Drafter.Draw.Segment{text: "", style: %{}, width: 0}

      iex> Drafter.Draw.Segment.plain("日本語") |> Drafter.Draw.Segment.crop(3)
      %Drafter.Draw.Segment{text: "日", style: %{}, width: 2}

  """
  @spec crop(t(), non_neg_integer()) :: t()
  def crop(%__MODULE__{text: text, width: width} = segment, crop_width) do
    cond do
      crop_width >= width ->
        segment

      crop_width <= 0 ->
        %{segment | text: "", width: 0}

      true ->
        {cropped_text, cropped_width} = truncate_to_display_width(text, crop_width)
        %{segment | text: cropped_text, width: cropped_width}
    end
  end

  defp truncate_to_display_width(str, target_width) do
    if plain_ascii?(str) do
      {binary_part(str, 0, target_width), target_width}
    else
      truncate_mixed(str, target_width)
    end
  end

  defp truncate_mixed(str, target_width) do
    ansi_pattern = ~r/\e\[[0-9;]*m/
    parts = Regex.split(ansi_pattern, str, include_captures: true)

    {result, width} =
      Enum.reduce_while(parts, {[], 0}, fn part, {acc, w} ->
        truncate_part(part, acc, w, target_width, ansi_pattern)
      end)

    {IO.iodata_to_binary(result), width}
  end

  defp truncate_part(part, acc, width, target_width, ansi_pattern) do
    if Regex.match?(ansi_pattern, part) do
      {:cont, {[acc, part], width}}
    else
      append_truncated_text(part, acc, width, target_width)
    end
  end

  defp append_truncated_text(text, acc, width, target_width) do
    {chunk, new_width} = truncate_text_part(text, width, target_width)

    if new_width >= target_width and new_width > width do
      {:halt, {[acc, chunk], new_width}}
    else
      {:cont, {[acc, chunk], new_width}}
    end
  end

  defp truncate_text_part(text, current_width, target_width) do
    {chunk, width} =
      text
      |> String.graphemes()
      |> Enum.reduce_while({[], current_width}, fn grapheme, {chunk_acc, w} ->
        new_w = w + char_width(grapheme)

        if new_w <= target_width do
          {:cont, {[chunk_acc, grapheme], new_w}}
        else
          {:halt, {chunk_acc, w}}
        end
      end)

    {IO.iodata_to_binary(chunk), width}
  end

  defp plain_ascii?(str) do
    Drafter.CharacterWidth.printable_ascii?(str)
  end

  @doc """
  Append spaces until the segment is `target_width` columns wide, or return it
  unchanged if it already is.

  ## Examples

      iex> Drafter.Draw.Segment.plain("ab") |> Drafter.Draw.Segment.pad(5)
      %Drafter.Draw.Segment{text: "ab   ", style: %{}, width: 5}

      iex> Drafter.Draw.Segment.plain("abcde") |> Drafter.Draw.Segment.pad(2)
      %Drafter.Draw.Segment{text: "abcde", style: %{}, width: 5}

  """
  @spec pad(t(), non_neg_integer()) :: t()
  def pad(%__MODULE__{text: text, width: width} = segment, target_width) do
    if target_width > width do
      padding = String.duplicate(" ", target_width - width)
      %{segment | text: text <> padding, width: target_width}
    else
      segment
    end
  end

  @doc """
  The segment as SGR codes, its text, and a reset.

  A segment with an empty style returns its text alone, with no codes and no reset.

  ## Examples

      iex> Drafter.Draw.Segment.new("x", %{bold: true}) |> Drafter.Draw.Segment.to_ansi()
      "\\e[1mx\\e[0m"

      iex> Drafter.Draw.Segment.plain("x") |> Drafter.Draw.Segment.to_ansi()
      "x"

  """
  @spec to_ansi(t()) :: String.t()
  def to_ansi(%__MODULE__{text: text, style: style}) do
    style_codes = build_style_codes(style)
    reset_code = if style == %{}, do: "", else: "\e[0m"

    "#{style_codes}#{text}#{reset_code}"
  end

  @doc """
  The segment's width in display columns, measured when it was built.

  ## Examples

      iex> Drafter.Draw.Segment.plain("日本") |> Drafter.Draw.Segment.width()
      4

  """
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{width: width}), do: width

  @doc """
  Whether the segment's text is the empty string.

  ## Examples

      iex> Drafter.Draw.Segment.plain("") |> Drafter.Draw.Segment.empty?()
      true

      iex> Drafter.Draw.Segment.plain(" ") |> Drafter.Draw.Segment.empty?()
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{text: text}), do: text == ""

  @style_flags [bold: "1", dim: "2", italic: "3", underline: "4", reverse: "7"]

  @doc """
  The SGR sequence that turns on `style`.

  Returns the empty string for an empty style, or one that sets nothing. Colours
  are emitted as 24-bit `38;2` and `48;2` codes. Alpha keys emit nothing.

  ## Examples

      iex> Drafter.Draw.Segment.style_codes(%{})
      ""

      iex> Drafter.Draw.Segment.style_codes(%{bold: true})
      "\\e[1m"

      iex> Drafter.Draw.Segment.style_codes(%{fg: {255, 0, 0}})
      "\\e[38;2;255;0;0m"

      iex> Drafter.Draw.Segment.style_codes(%{bold: false})
      ""

  """
  @spec style_codes(style()) :: String.t()
  def style_codes(style), do: build_style_codes(style)

  @doc """
  The style keys that are attribute flags rather than colours.

  ## Examples

      iex> Drafter.Draw.Segment.style_flags()
      [:bold, :dim, :italic, :underline, :reverse]

  """
  @spec style_flags() :: [atom()]
  def style_flags, do: Keyword.keys(@style_flags)

  defp build_style_codes(style) when style == %{}, do: ""

  defp build_style_codes(style) do
    codes =
      Enum.reduce(@style_flags, [], fn {key, code}, acc ->
        if style[key], do: [code | acc], else: acc
      end)

    codes = prepend_color_code(codes, style[:fg], "38;2")
    codes = prepend_color_code(codes, style[:bg], "48;2")

    case codes do
      [] -> ""
      _ -> "\e[" <> Enum.join(Enum.reverse(codes), ";") <> "m"
    end
  end

  defp prepend_color_code(codes, {r, g, b}, prefix), do: ["#{prefix};#{r};#{g};#{b}" | codes]
  defp prepend_color_code(codes, _nil, _prefix), do: codes
end
