defmodule Drafter.Widget.Digits.Figlet do
  @moduledoc """
  Reads FIGlet fonts (`.flf`) into the glyph maps `Drafter.Widget.Digits.Font`
  serves.

  A parsed font behaves like a built-in one once registered:

      {:ok, font} = Figlet.load("/usr/share/figlet/slant.flf")
      Font.register(:slant, font)
      digits("Vellum", font: :slant)

  Glyphs are laid out full width — characters placed side by side with no
  kerning or smushing. Hardblanks are rendered as plain spaces.

  ## Format

  The header names a hardblank character, the glyph height, and how many comment
  lines follow. Glyphs for the printable ASCII range then appear in code order,
  each one `height` lines long, every line closed by a repeated endmark
  character.

  See the [large text guide](large_text.md) for the layout rules Drafter
  applies.
  """

  alias Drafter.Widget.Digits.Font

  @first_codepoint 32
  @last_codepoint 126
  @required_header_fields 6

  @doc """
  Reads and parses a `.flf` file.

  Returns `{:ok, font}`, `{:error, {:unreadable, reason}}` when the file cannot
  be read, or `{:error, {:malformed, detail}}` when its header or glyph data is
  not FIGlet.
  """
  @spec load(Path.t()) :: {:ok, Font.font()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, contents} -> parse(contents)
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  @doc """
  Same as `load/1`, but raises `ArgumentError` if the font cannot be loaded.
  """
  @spec load!(Path.t()) :: Font.font()
  def load!(path) do
    case load(path) do
      {:ok, font} ->
        font

      {:error, reason} ->
        raise ArgumentError, "cannot load FIGlet font #{path}: #{inspect(reason)}"
    end
  end

  @doc "Parse the contents of a `.flf` file."
  @spec parse(binary()) :: {:ok, Font.font()} | {:error, term()}
  def parse(contents) do
    with {:ok, header, body} <- split_header(contents),
         {:ok, hardblank, height, comment_lines} <- parse_header(header),
         {:ok, glyph_lines} <- skip_comments(body, comment_lines) do
      build(glyph_lines, hardblank, height)
    end
  end

  @doc "The directory of FIGlet fonts shipped with Drafter."
  @spec bundled_directory() :: Path.t()
  def bundled_directory, do: Path.join([:code.priv_dir(:drafter), "fonts", "figlet"])

  @doc "Parse every bundled font, keyed by name."
  @spec bundled() :: %{atom() => Font.font()}
  def bundled, do: load_directory(bundled_directory())

  @doc """
  Parses every bundled font and registers it under its own name.

  Returns the sorted list of names registered, each then usable as
  `digits(text, font: name)`.
  """
  @spec register_bundled() :: [atom()]
  def register_bundled do
    bundled()
    |> Enum.map(fn {name, font} ->
      Font.register(name, font)
      name
    end)
    |> Enum.sort()
  end

  @doc """
  Every `.flf` file in a directory, parsed and keyed by its basename.

  Files that fail to parse are omitted.
  """
  @spec load_directory(Path.t()) :: %{atom() => Font.font()}
  def load_directory(directory) do
    directory
    |> Path.join("*.flf")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, loaded ->
      case load(path) do
        {:ok, font} -> Map.put(loaded, font_name(path), font)
        {:error, _reason} -> loaded
      end
    end)
  end

  defp font_name(path), do: path |> Path.basename(".flf") |> String.to_atom()

  defp split_header(contents) do
    case String.split(contents, ~r/\r?\n/, parts: 2) do
      [header, body] -> {:ok, header, body}
      _ -> {:error, {:malformed, :no_header}}
    end
  end

  defp parse_header(header) do
    case String.split(header, " ", trim: true) do
      [signature | rest] when length(rest) >= @required_header_fields - 1 ->
        read_signature(signature, rest)

      _ ->
        {:error, {:malformed, :short_header}}
    end
  end

  defp read_signature(<<"flf2a", hardblank::utf8>>, [
         height,
         _baseline,
         _max_length,
         _old_layout,
         comments | _
       ]) do
    with {:ok, height} <- positive_integer(height, :height),
         {:ok, comments} <- non_negative_integer(comments, :comment_lines) do
      {:ok, <<hardblank::utf8>>, height, comments}
    end
  end

  defp read_signature(_signature, _rest), do: {:error, {:malformed, :not_flf2a}}

  defp positive_integer(text, field) do
    case Integer.parse(text) do
      {value, _} when value > 0 -> {:ok, value}
      _ -> {:error, {:malformed, field}}
    end
  end

  defp non_negative_integer(text, field) do
    case Integer.parse(text) do
      {value, _} when value >= 0 -> {:ok, value}
      _ -> {:error, {:malformed, field}}
    end
  end

  defp skip_comments(body, comment_lines) do
    lines = String.split(body, ~r/\r?\n/)

    if length(lines) > comment_lines do
      {:ok, Enum.drop(lines, comment_lines)}
    else
      {:error, {:malformed, :truncated_comments}}
    end
  end

  defp build(lines, hardblank, height) do
    case take_glyphs(lines, height, @first_codepoint, %{}) do
      glyphs when map_size(glyphs) == 0 -> {:error, {:malformed, :no_glyphs}}
      glyphs -> {:ok, finish(glyphs, hardblank, height)}
    end
  end

  defp take_glyphs(_lines, _height, codepoint, glyphs) when codepoint > @last_codepoint,
    do: glyphs

  defp take_glyphs(lines, height, codepoint, glyphs) do
    {glyph, rest} = Enum.split(lines, height)

    if length(glyph) < height do
      glyphs
    else
      character = <<codepoint::utf8>>
      take_glyphs(rest, height, codepoint + 1, Map.put(glyphs, character, glyph))
    end
  end

  defp finish(glyphs, hardblank, height) do
    cleaned = Map.new(glyphs, fn {character, rows} -> {character, clean(rows, hardblank)} end)
    squared = Map.new(cleaned, fn {character, rows} -> {character, square(rows)} end)

    %{
      height: height,
      width: squared |> Map.values() |> Enum.map(&row_width/1) |> Enum.max(fn -> 1 end),
      glyphs: squared
    }
  end

  defp clean(rows, hardblank) do
    Enum.map(rows, fn row ->
      row
      |> strip_endmark()
      |> String.replace(hardblank, " ")
    end)
  end

  defp strip_endmark(""), do: ""

  defp strip_endmark(row) do
    endmark = String.last(row)
    String.replace_trailing(row, endmark, "") |> pad_if_wholly_endmark(row, endmark)
  end

  defp pad_if_wholly_endmark("", row, endmark) do
    if String.trim(row, endmark) == "", do: "", else: row
  end

  defp pad_if_wholly_endmark(stripped, _row, _endmark), do: stripped

  defp square(rows) do
    width = rows |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    Enum.map(rows, &String.pad_trailing(&1, width))
  end

  defp row_width([]), do: 0
  defp row_width([row | _]), do: String.length(row)
end
