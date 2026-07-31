defmodule Drafter.Color do
  @moduledoc """
  Color representation and parsing for terminal styling.

  Accepts hex (`"#RGB"`, `"#RRGGBB"`), RGB (`"rgb(r,g,b)"`, `"rgba(r,g,b,a)"`),
  and HSL (`"hsl(h,s%,l%)"`, `"hsla(h,s%,l%,a)"`) strings, as well as
  `{r, g, b}` and `{r, g, b, a}` tuples and named-color atoms.

  `parse/1` returns `{:ok, t()}` or `{:error, reason}`. `normalize/1` converts
  any supported format to a plain `{r, g, b}` tuple for segment styles, falling
  back to white on anything it does not recognise.

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

  def new(r, g, b, a \\ 1.0) when r in 0..255 and g in 0..255 and b in 0..255 do
    %__MODULE__{r: r, g: g, b: b, a: clamp(a, 0.0, 1.0)}
  end

  def from_hsl(h, s, l, a \\ 1.0) do
    h = normalize_hue(h)
    s = clamp(s / 100, 0.0, 1.0)
    l = clamp(l / 100, 0.0, 1.0)

    {r, g, b} = hsl_to_rgb(h, s, l)
    new(r, g, b, a)
  end

  def to_hsl(%__MODULE__{r: r, g: g, b: b}) do
    rgb_to_hsl(r, g, b)
  end

  def to_tuple(%__MODULE__{r: r, g: g, b: b}), do: {r, g, b}

  def to_tuple_with_alpha(%__MODULE__{r: r, g: g, b: b, a: a}), do: {r, g, b, a}

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

  `normalize/1` flattens to the RGB triple every style, segment and SGR encoder in
  the tree expects. This keeps the alpha alongside it so the compositor can blend the
  colour against whatever is beneath before that flattening happens. Colours with no
  alpha channel come back as `1.0`.
  """
  @spec normalize_with_alpha(term()) :: {{0..255, 0..255, 0..255}, float()}
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
