defmodule Drafter.Color do
  @moduledoc """
  Color representation and parsing for terminal styling.

  Accepts hex (`"#RGB"`, `"#RRGGBB"`), RGB (`"rgb(r,g,b)"`, `"rgba(r,g,b,a)"`),
  and HSL (`"hsl(h,s%,l%)"`, `"hsla(h,s%,l%,a)"`) strings, as well as
  `{r, g, b}` and `{r, g, b, a}` tuples.

  `parse/1` returns `{:ok, t()}` or `{:error, reason}` and handles strings and
  tuples only. `normalize/1` covers the same inputs plus the named-colour atoms
  listed below, converting any of them to a plain `{r, g, b}` tuple for segment
  styles and falling back to white on anything it does not recognise.

  ## Named colours

  `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`,
  and a `:bright_`-prefixed variant of each. These are the palette values, not the
  terminal's own ANSI colours.

  ## Examples

      iex> Drafter.Color.normalize("#f00")
      {255, 0, 0}

      iex> Drafter.Color.normalize("rgb(10, 20, 30)")
      {10, 20, 30}

      iex> Drafter.Color.normalize(:black)
      {0, 0, 0}

      iex> Drafter.Color.normalize("not a color")
      {255, 255, 255}

      iex> Drafter.Color.parse("nope")
      {:error, :invalid_format}

  """

  defstruct [:r, :g, :b, :a]

  @type t :: %__MODULE__{
          r: 0..255,
          g: 0..255,
          b: 0..255,
          a: float()
        }

  @typedoc "A plain RGB triple, as carried on segment styles."
  @type rgb :: {0..255, 0..255, 0..255}

  @typedoc "Anything `normalize/1` accepts: a colour string, a tuple, a struct, or a named atom."
  @type input :: String.t() | rgb() | {0..255, 0..255, 0..255, number()} | atom()

  @doc """
  Build a colour from channel values.

  Each of `r`, `g` and `b` must be in `0..255`; anything else raises
  `FunctionClauseError`. `a` is clamped into `0.0..1.0` rather than rejected.
  Default: `1.0`.

  ## Examples

      iex> Drafter.Color.new(10, 20, 30)
      %Drafter.Color{r: 10, g: 20, b: 30, a: 1.0}

      iex> Drafter.Color.new(10, 20, 30, 2.5)
      %Drafter.Color{r: 10, g: 20, b: 30, a: 1.0}

  """
  @spec new(0..255, 0..255, 0..255, number()) :: t()
  def new(r, g, b, a \\ 1.0) when r in 0..255 and g in 0..255 and b in 0..255 do
    %__MODULE__{r: r, g: g, b: b, a: clamp(a, 0.0, 1.0)}
  end

  @doc """
  Build a colour from hue in degrees, saturation and lightness in percent.

  Hue wraps, so `-60` and `300` are the same. Saturation and lightness are clamped
  to `0..100`. `a` defaults to `1.0` and is clamped into `0.0..1.0`.

  ## Examples

      iex> Drafter.Color.from_hsl(0, 100, 50)
      %Drafter.Color{r: 255, g: 0, b: 0, a: 1.0}

      iex> Drafter.Color.from_hsl(240, 100, 50)
      %Drafter.Color{r: 0, g: 0, b: 255, a: 1.0}

      iex> Drafter.Color.from_hsl(-240, 100, 50) == Drafter.Color.from_hsl(120, 100, 50)
      true

  """
  @spec from_hsl(number(), number(), number(), number()) :: t()
  def from_hsl(h, s, l, a \\ 1.0) do
    h = normalize_hue(h)
    s = clamp(s / 100, 0.0, 1.0)
    l = clamp(l / 100, 0.0, 1.0)

    {r, g, b} = hsl_to_rgb(h, s, l)
    new(r, g, b, a)
  end

  @doc """
  Hue in degrees, saturation and lightness in percent, for a colour.

  Alpha is dropped. For a fully desaturated colour hue and saturation come back as
  the integer `0`, so compare numerically rather than by pattern match.

  ## Examples

      iex> Drafter.Color.to_hsl(Drafter.Color.new(255, 0, 0))
      {0.0, 100.0, 50.0}

      iex> Drafter.Color.to_hsl(Drafter.Color.new(0, 0, 0))
      {0, 0, 0.0}

  """
  @spec to_hsl(t()) :: {number(), number(), number()}
  def to_hsl(%__MODULE__{r: r, g: g, b: b}) do
    rgb_to_hsl(r, g, b)
  end

  @doc """
  The colour's `{r, g, b}` triple, dropping alpha.

  ## Examples

      iex> Drafter.Color.to_tuple(Drafter.Color.new(1, 2, 3, 0.5))
      {1, 2, 3}

  """
  @spec to_tuple(t()) :: rgb()
  def to_tuple(%__MODULE__{r: r, g: g, b: b}), do: {r, g, b}

  @doc """
  The colour's `{r, g, b, a}` tuple, keeping alpha.

  ## Examples

      iex> Drafter.Color.to_tuple_with_alpha(Drafter.Color.new(1, 2, 3, 0.5))
      {1, 2, 3, 0.5}

  """
  @spec to_tuple_with_alpha(t()) :: {0..255, 0..255, 0..255, float()}
  def to_tuple_with_alpha(%__MODULE__{r: r, g: g, b: b, a: a}), do: {r, g, b, a}

  @doc """
  Parse a colour string or tuple into a `t:t/0`.

  Named-colour atoms are *not* accepted here — use `normalize/1` for those.

  Error reasons are `:invalid_hex`, `:invalid_hex_length`, `:invalid_rgb`,
  `:invalid_hsl`, `:invalid_tuple` (a tuple that is not a valid RGB/RGBA tuple),
  and `:invalid_format` for everything else.

  ## Examples

      iex> Drafter.Color.parse("#abc")
      {:ok, %Drafter.Color{r: 170, g: 187, b: 204, a: 1.0}}

      iex> Drafter.Color.parse("rgba(1,2,3,0.5)")
      {:ok, %Drafter.Color{r: 1, g: 2, b: 3, a: 0.5}}

      iex> Drafter.Color.parse({1, 2, 3})
      {:ok, %Drafter.Color{r: 1, g: 2, b: 3, a: 1.0}}

      iex> Drafter.Color.parse("#gg00zz")
      {:error, :invalid_hex}

      iex> Drafter.Color.parse("#12345")
      {:error, :invalid_hex_length}

      iex> Drafter.Color.parse({1, 2})
      {:error, :invalid_tuple}

      iex> Drafter.Color.parse(:black)
      {:error, :invalid_format}

  """
  @spec parse(term()) ::
          {:ok, t()}
          | {:error,
             :invalid_hex
             | :invalid_hex_length
             | :invalid_rgb
             | :invalid_hsl
             | :invalid_tuple
             | :invalid_format}
  def parse("#" <> _ = color), do: parse_hex(color)
  def parse("rgb" <> _ = color), do: parse_rgb(color)
  def parse("hsl" <> _ = color), do: parse_hsl(color)
  def parse(color) when is_binary(color), do: {:error, :invalid_format}

  def parse({r, g, b}) when r in 0..255 and g in 0..255 and b in 0..255 do
    {:ok, new(r, g, b)}
  end

  def parse({r, g, b, a})
      when r in 0..255 and g in 0..255 and b in 0..255 and is_float(a) and a >= 0.0 and
             a <= 1.0 do
    {:ok, new(r, g, b, a)}
  end

  def parse(t) when is_tuple(t), do: {:error, :invalid_tuple}
  def parse(_), do: {:error, :invalid_format}

  @doc """
  Convert any supported colour input to a plain `{r, g, b}` triple.

  Alpha is dropped. Unrecognised strings, unknown atoms and anything else fall back
  to white, `{255, 255, 255}` — this function never raises and never returns an error
  tuple. Use `parse/1` when a bad colour should be reported rather than substituted.

  ## Examples

      iex> Drafter.Color.normalize("#00ff00")
      {0, 255, 0}

      iex> Drafter.Color.normalize({1, 2, 3, 0.5})
      {1, 2, 3}

      iex> Drafter.Color.normalize(:bright_white)
      {255, 255, 255}

      iex> Drafter.Color.normalize(:no_such_colour)
      {255, 255, 255}

  """
  @spec normalize(input() | term()) :: rgb()
  def normalize(color) when is_binary(color) do
    case parse(color) do
      {:ok, c} -> to_tuple(c)
      {:error, _} -> {255, 255, 255}
    end
  end

  def normalize({r, g, b}) when r in 0..255 and g in 0..255 and b in 0..255 do
    {r, g, b}
  end

  def normalize({r, g, b, _a}) when r in 0..255 and g in 0..255 and b in 0..255 do
    {r, g, b}
  end

  @named_colors %{
    black: {0, 0, 0},
    red: {205, 49, 49},
    green: {13, 188, 121},
    yellow: {229, 229, 16},
    blue: {36, 114, 200},
    magenta: {188, 63, 188},
    cyan: {17, 168, 205},
    white: {229, 229, 229},
    bright_black: {102, 102, 102},
    bright_red: {241, 76, 76},
    bright_green: {35, 209, 139},
    bright_yellow: {245, 245, 67},
    bright_blue: {59, 142, 234},
    bright_magenta: {214, 112, 214},
    bright_cyan: {41, 184, 219},
    bright_white: {255, 255, 255}
  }

  def normalize(name) when is_atom(name) do
    Map.get(@named_colors, name, {255, 255, 255})
  end

  def normalize(_), do: {255, 255, 255}

  @doc """
  Normalize a colour to `{{r, g, b}, alpha}`, keeping the alpha channel.

  Accepts the same inputs as `normalize/1`. `alpha` is a float in `0.0..1.0`;
  a colour with no alpha channel comes back as `1.0`. Use this where the alpha
  is still needed — the compositor blends against the cell beneath — and
  `normalize/1` where a plain RGB triple is wanted.

  ## Examples

      iex> Drafter.Color.normalize_with_alpha("rgba(1,2,3,0.5)")
      {{1, 2, 3}, 0.5}

      iex> Drafter.Color.normalize_with_alpha("#f00")
      {{255, 0, 0}, 1.0}

      iex> Drafter.Color.normalize_with_alpha(:black)
      {{0, 0, 0}, 1.0}

      iex> Drafter.Color.normalize_with_alpha("not a color")
      {{255, 255, 255}, 1.0}

  """
  @spec normalize_with_alpha(term()) :: {rgb(), float()}
  def normalize_with_alpha(color) when is_binary(color) do
    case parse(color) do
      {:ok, parsed} -> {to_tuple(parsed), parsed.a}
      {:error, _reason} -> {{255, 255, 255}, 1.0}
    end
  end

  def normalize_with_alpha({r, g, b, a}) when r in 0..255 and g in 0..255 and b in 0..255 do
    {{r, g, b}, clamp_alpha(a)}
  end

  def normalize_with_alpha(color), do: {normalize(color), 1.0}

  defp clamp_alpha(a) when is_number(a), do: a |> max(0.0) |> min(1.0) |> :erlang.float()
  defp clamp_alpha(_a), do: 1.0

  defp parse_hex("#" <> hex) do
    case String.length(hex) do
      6 ->
        with {r, ""} <- Integer.parse(String.slice(hex, 0..1), 16),
             {g, ""} <- Integer.parse(String.slice(hex, 2..3), 16),
             {b, ""} <- Integer.parse(String.slice(hex, 4..5), 16) do
          {:ok, new(r, g, b)}
        else
          _ -> {:error, :invalid_hex}
        end

      3 ->
        with {r, ""} <- Integer.parse(String.duplicate(String.slice(hex, 0..0), 2), 16),
             {g, ""} <- Integer.parse(String.duplicate(String.slice(hex, 1..1), 2), 16),
             {b, ""} <- Integer.parse(String.duplicate(String.slice(hex, 2..2), 2), 16) do
          {:ok, new(r, g, b)}
        else
          _ -> {:error, :invalid_hex}
        end

      _ ->
        {:error, :invalid_hex_length}
    end
  end

  defp parse_rgb(color) do
    pattern = ~r/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)/

    case Regex.run(pattern, color) do
      [_, r, g, b] ->
        {:ok, new(String.to_integer(r), String.to_integer(g), String.to_integer(b))}

      [_, r, g, b, a] ->
        {:ok,
         new(String.to_integer(r), String.to_integer(g), String.to_integer(b), String.to_float(a))}

      _ ->
        {:error, :invalid_rgb}
    end
  end

  defp parse_hsl(color) do
    pattern = ~r/hsla?\(\s*([\d.-]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)/

    case Regex.run(pattern, color) do
      [_, h, s, l] ->
        {h_val, _} = Float.parse(h)
        {s_val, _} = Float.parse(s)
        {l_val, _} = Float.parse(l)
        {:ok, from_hsl(h_val, s_val, l_val)}

      [_, h, s, l, a] ->
        {h_val, _} = Float.parse(h)
        {s_val, _} = Float.parse(s)
        {l_val, _} = Float.parse(l)
        {a_val, _} = Float.parse(a)
        {:ok, from_hsl(h_val, s_val, l_val, a_val)}

      _ ->
        {:error, :invalid_hsl}
    end
  end

  defp normalize_hue(h) when h < 0, do: normalize_hue(h + 360)
  defp normalize_hue(h) when h >= 360, do: normalize_hue(h - 360)
  defp normalize_hue(h), do: h / 360

  defp hsl_to_rgb(h, s, l) do
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs(:math.fmod(h * 6, 2) - 1))
    m = l - c / 2

    {r1, g1, b1} =
      cond do
        h < 1 / 6 -> {c, x, 0}
        h < 2 / 6 -> {x, c, 0}
        h < 3 / 6 -> {0, c, x}
        h < 4 / 6 -> {0, x, c}
        h < 5 / 6 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {
      round((r1 + m) * 255),
      round((g1 + m) * 255),
      round((b1 + m) * 255)
    }
  end

  defp rgb_to_hsl(r, g, b) do
    r_norm = r / 255
    g_norm = g / 255
    b_norm = b / 255

    max_c = max(max(r_norm, g_norm), b_norm)
    min_c = min(min(r_norm, g_norm), b_norm)
    delta = max_c - min_c

    l = (max_c + min_c) / 2

    s =
      if delta == 0 do
        0
      else
        delta / (1 - abs(2 * l - 1))
      end

    h =
      cond do
        delta == 0 ->
          0

        max_c == r_norm ->
          60 * :math.fmod((g_norm - b_norm) / delta, 6)

        max_c == g_norm ->
          60 * ((b_norm - r_norm) / delta + 2)

        true ->
          60 * ((r_norm - g_norm) / delta + 4)
      end

    h = if h < 0, do: h + 360, else: h

    {h, s * 100, l * 100}
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end
end
