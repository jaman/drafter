defmodule Drafter.Style.CSSParser do
  @moduledoc """
  Parses a CSS-like stylesheet into a `Drafter.Style.Stylesheet`.

  The grammar is a subset of CSS: a sequence of `selector { property: value; ... }`
  rules, with `/* */` and `//` comments removed first. Selectors are handed to
  `Drafter.Style.Selector.parse/1`; a comma-separated selector list becomes one
  rule per selector, each holding a copy of the same properties.

      iex> {:ok, sheet} = Drafter.Style.CSSParser.parse_string("button { color: red; bold: true; }")
      iex> Drafter.Style.Stylesheet.compute_style(sheet, %{widget_type: :button})
      %{bold: true, color: :red}

  ## Property names

  A property name is mapped to a style key. `background-color` and `background` both
  give `:background`; `text-align` and `text_align` both give `:text_align`. Any
  other name becomes an atom of that exact spelling through
  `Drafter.Util.normalize_class/1`, so an unknown property is a key rather than an
  error. `Drafter.Style.new/1` then drops the keys that are not style properties
  when the rule is added to the stylesheet.

  ## Property values

  Recognised in this order:

  - `true` and `false` — booleans
  - `#rgb` and `#rrggbb` — an RGB triple. Other hex lengths are not colours.
  - `rgb(r, g, b)` — an RGB triple, provided each component is at most 255
  - `rgba(r, g, b, a)` — an `{:rgba, {r, g, b}, alpha}` triple, `alpha` a float
  - a run of digits — an integer
  - digits, a dot and digits — a float
  - anything else — `Drafter.Util.normalize_class/1`, giving an atom

  A value that is not a colour but looks like one, such as `#ff00`, falls through to
  the atom case rather than failing.

  ## Errors

  Both `parse_string/1` and `parse_file/1` stop at the first bad rule or property and
  return `{:error, message}`, discarding the rules parsed so far.
  """

  alias Drafter.Style.Stylesheet

  @typedoc "A parsed stylesheet, or the message describing why parsing stopped."
  @type parse_result :: {:ok, Stylesheet.t()} | {:error, String.t()}

  @typedoc """
  A colour parse, `:error` rather than an error tuple when the string is not of
  that form.
  """
  @type color_result :: {:ok, Drafter.Style.rgb()} | :error

  @doc """
  Parse a CSS string into a stylesheet.

  Returns `{:ok, stylesheet}`, or `{:error, message}` naming the first rule or
  property that could not be parsed. An empty string, or one holding only comments,
  gives an empty stylesheet.

  ## Examples

      iex> {:ok, sheet} = Drafter.Style.CSSParser.parse_string("a, b { color: red; }")
      iex> length(sheet.rules)
      2

      iex> Drafter.Style.CSSParser.parse_string("")
      {:ok, %Drafter.Style.Stylesheet{rules: []}}

      iex> Drafter.Style.CSSParser.parse_string("button { bogus }")
      {:error, "Invalid property: bogus"}

      iex> Drafter.Style.CSSParser.parse_string("oops")
      {:error, "Invalid CSS rule: oops"}

  """
  @spec parse_string(String.t()) :: parse_result()
  def parse_string(css_content) when is_binary(css_content) do
    css_content
    |> preprocess_css()
    |> extract_css_rules()
    |> Enum.map(&parse_rule/1)
    |> Enum.flat_map(&expand_rule/1)
    |> Enum.reduce({:ok, Stylesheet.new()}, fn
      {:ok, rule}, {:ok, stylesheet} ->
        {:ok, Stylesheet.add_rule(stylesheet, rule.selector_string, rule.properties)}

      {:error, _} = error, _acc ->
        error

      _, {:error, _} = error ->
        error
    end)
  end

  defp expand_rule({:ok, %{selector_strings: selector_strings, properties: properties}}) do
    Enum.map(selector_strings, fn selector_string ->
      {:ok, %{selector_string: selector_string, properties: properties}}
    end)
  end

  defp expand_rule({:ok, %{selector: selector, properties: properties}}) when is_list(selector) do
    Enum.map(selector, fn selector_string ->
      {:ok, %{selector_string: selector_string, properties: properties}}
    end)
  end

  defp expand_rule({:ok, rule}), do: [{:ok, rule}]
  defp expand_rule({:error, _} = error), do: [error]

  defp preprocess_css(css_content) do
    css_content
    |> remove_block_comments()
    |> remove_line_comments()
    |> String.replace(~r/\n\r?/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp remove_block_comments(css_content) do
    Regex.replace(~r/\/\*[\s\S]*?\*\//, css_content, "")
  end

  defp remove_line_comments(css_content) do
    Regex.replace(~r{//.*}, css_content, "")
  end

  defp extract_css_rules(css_string) do
    extract_rules(css_string, [], "")
  end

  defp extract_rules("", acc, buffer) do
    if String.trim(buffer) == "" do
      Enum.reverse(acc)
    else
      Enum.reverse([buffer | acc])
    end
  end

  defp extract_rules(css_string, acc, buffer) do
    case find_matching_brace(css_string) do
      {:ok, rule, rest} ->
        rule = String.trim(buffer <> " " <> rule)
        extract_rules(rest, [rule | acc], "")

      :error ->
        <<byte, rest::binary>> = css_string
        extract_rules(rest, acc, buffer <> <<byte>>)
    end
  end

  defp find_matching_brace(str), do: find_matching_brace(str, 0, <<>>)

  defp find_matching_brace(<<>>, _depth, _acc), do: :error

  defp find_matching_brace(<<?\", rest::binary>>, depth, acc) do
    case skip_string(rest, ?\", <<?\">>) do
      {:ok, string_content, remaining} ->
        find_matching_brace(remaining, depth, acc <> string_content)

      :error ->
        :error
    end
  end

  defp find_matching_brace(<<?', rest::binary>>, depth, acc) do
    case skip_string(rest, ?', <<?'>>) do
      {:ok, string_content, remaining} ->
        find_matching_brace(remaining, depth, acc <> string_content)

      :error ->
        :error
    end
  end

  defp find_matching_brace(<<?{, rest::binary>>, depth, acc) do
    find_matching_brace(rest, depth + 1, acc <> "{")
  end

  defp find_matching_brace(<<?}, rest::binary>>, 1, acc) do
    {:ok, acc <> "}", rest}
  end

  defp find_matching_brace(<<?}, rest::binary>>, depth, acc) do
    find_matching_brace(rest, depth - 1, acc <> "}")
  end

  defp find_matching_brace(<<byte, rest::binary>>, depth, acc) do
    find_matching_brace(rest, depth, acc <> <<byte>>)
  end

  defp skip_string(<<>>, _quote, _acc), do: :error

  defp skip_string(<<?\\, escaped, rest::binary>>, quote, acc) do
    skip_string(rest, quote, acc <> <<?\\, escaped>>)
  end

  defp skip_string(<<quote, rest::binary>>, quote, acc) do
    {:ok, acc <> <<quote>>, rest}
  end

  defp skip_string(<<byte, rest::binary>>, quote, acc) do
    skip_string(rest, quote, acc <> <<byte>>)
  end

  @doc """
  Parse the CSS file at `file_path` into a stylesheet.

  Returns `{:error, "Failed to read file: " <> inspect(reason)}` when the file
  cannot be read, and otherwise whatever `parse_string/1` makes of its contents.

  ## Examples

      iex> Drafter.Style.CSSParser.parse_file("/no/such/file.css")
      {:error, "Failed to read file: :enoent"}

  """
  @spec parse_file(Path.t()) :: parse_result()
  def parse_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> parse_string(content)
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp parse_rule(line) do
    regex = ~r/^(.*?)\s*\{\s*(.*?)\s*\}$/s

    case Regex.run(regex, line) do
      [_, selector_str, properties_str] ->
        selector_strings = parse_selector_string(selector_str)

        with {:ok, properties} <- parse_properties(properties_str) do
          {:ok, %{selector_strings: selector_strings, properties: properties}}
        end

      _ ->
        {:error, "Invalid CSS rule: #{String.slice(line, 0, 100)}"}
    end
  end

  defp parse_selector_string(selector_str) do
    selector_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_properties(properties_str) do
    properties_str
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_property/1)
    |> Enum.reduce({:ok, %{}}, fn
      {:ok, {key, value}}, {:ok, acc} -> {:ok, Map.put(acc, key, value)}
      {:error, _} = error, _acc -> error
      _, {:error, _} = error -> error
    end)
  end

  defp parse_property(property_str) do
    case Regex.run(~r/^([a-z_-]+)\s*:\s*(.*)$/i, property_str) do
      [_, key, value_str] ->
        key = normalize_property_key(key)
        value = parse_value(value_str)
        {:ok, {key, value}}

      _ ->
        {:error, "Invalid property: #{property_str}"}
    end
  end

  @property_key_map %{
    "color" => :color,
    "background" => :background,
    "background-color" => :background,
    "border-color" => :border_color,
    "bold" => :bold,
    "dim" => :dim,
    "italic" => :italic,
    "underline" => :underline,
    "reverse" => :reverse,
    "width" => :width,
    "height" => :height,
    "padding" => :padding,
    "margin" => :margin,
    "border" => :border,
    "text-align" => :text_align,
    "text_align" => :text_align,
    "opacity" => :opacity
  }

  defp normalize_property_key(key) do
    Map.get(@property_key_map, key) || Drafter.Util.normalize_class(key)
  end

  defp parse_value(value_str) do
    value_str = String.trim(value_str)

    cond do
      value_str == "true" ->
        true

      value_str == "false" ->
        false

      match?({:ok, _}, parse_hex_color(value_str)) ->
        {:ok, color} = parse_hex_color(value_str)
        color

      match?({:ok, _}, parse_rgb_color(value_str)) ->
        {:ok, color} = parse_rgb_color(value_str)
        color

      match?({:ok, _}, parse_rgba_color(value_str)) ->
        {:ok, color} = parse_rgba_color(value_str)
        color

      String.match?(value_str, ~r/^\d+$/) ->
        String.to_integer(value_str)

      String.match?(value_str, ~r/^\d+\.\d+$/) ->
        String.to_float(value_str)

      true ->
        Drafter.Util.normalize_class(value_str)
    end
  end

  @doc """
  Parse a `#rgb` or `#rrggbb` string into an RGB triple.

  Each digit of the three-digit form is doubled, so `#f00` and `#ff0000` are the
  same colour. Case is ignored. Returns `:error` for any other length, for a string
  with a non-hex digit, and for a string that does not start with `#`.

  ## Examples

      iex> Drafter.Style.CSSParser.parse_hex_color("#f00")
      {:ok, {255, 0, 0}}

      iex> Drafter.Style.CSSParser.parse_hex_color("#FF0000")
      {:ok, {255, 0, 0}}

      iex> Drafter.Style.CSSParser.parse_hex_color("#ff00")
      :error

      iex> Drafter.Style.CSSParser.parse_hex_color("red")
      :error

  """
  @spec parse_hex_color(term()) :: color_result()
  def parse_hex_color(<<"#", hex_str::binary>>) do
    hex_str = String.downcase(hex_str)

    if Regex.match?(~r/^[0-9a-f]+$/, hex_str) do
      parse_hex_digits(hex_str)
    else
      :error
    end
  end

  def parse_hex_color(_), do: :error

  defp parse_hex_digits(<<r, g, b>> = _hex) when byte_size(<<r, g, b>>) == 3 do
    {:ok,
     {String.to_integer(<<r>>, 16) * 17, String.to_integer(<<g>>, 16) * 17,
      String.to_integer(<<b>>, 16) * 17}}
  end

  defp parse_hex_digits(<<r1, r2, g1, g2, b1, b2>> = _hex)
       when byte_size(<<r1, r2, g1, g2, b1, b2>>) == 6 do
    {:ok,
     {String.to_integer(<<r1, r2>>, 16), String.to_integer(<<g1, g2>>, 16),
      String.to_integer(<<b1, b2>>, 16)}}
  end

  defp parse_hex_digits(_), do: :error

  @doc """
  Parse an `rgb(r, g, b)` string into an RGB triple.

  Whitespace around the components is ignored and the function name is matched
  case-insensitively. Returns `:error` when the string is not of that form, and
  also when any component is above 255.

  ## Examples

      iex> Drafter.Style.CSSParser.parse_rgb_color("rgb(1, 2, 3)")
      {:ok, {1, 2, 3}}

      iex> Drafter.Style.CSSParser.parse_rgb_color("rgb(300, 0, 0)")
      :error

      iex> Drafter.Style.CSSParser.parse_rgb_color("rgb(1, 2)")
      :error

  """
  @spec parse_rgb_color(String.t()) :: color_result()
  def parse_rgb_color(str) do
    case Regex.run(~r/^rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i, str) do
      [_, r, g, b] ->
        parse_rgb_values(String.to_integer(r), String.to_integer(g), String.to_integer(b))

      _ ->
        :error
    end
  end

  @doc """
  Parse an `rgba(r, g, b, a)` string into `{:ok, {:rgba, {r, g, b}, alpha}}`.

  `alpha` is always a float: a leading-dot form such as `.5` and a whole number such
  as `1` are both converted. Returns `:error` when the string is not of that form,
  and also when any of `r`, `g` or `b` is above 255. `alpha` is not range-checked.

  ## Examples

      iex> Drafter.Style.CSSParser.parse_rgba_color("rgba(1, 2, 3, 0.5)")
      {:ok, {:rgba, {1, 2, 3}, 0.5}}

      iex> Drafter.Style.CSSParser.parse_rgba_color("rgba(1,2,3,.5)")
      {:ok, {:rgba, {1, 2, 3}, 0.5}}

      iex> Drafter.Style.CSSParser.parse_rgba_color("rgba(1, 2, 3, 1)")
      {:ok, {:rgba, {1, 2, 3}, 1.0}}

      iex> Drafter.Style.CSSParser.parse_rgba_color("rgb(1, 2, 3)")
      :error

  """
  @spec parse_rgba_color(String.t()) :: {:ok, Drafter.Style.rgba()} | :error
  def parse_rgba_color(str) do
    case Regex.run(~r/^rgba\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)$/i, str) do
      [_, r, g, b, a] ->
        ri = String.to_integer(r)
        gi = String.to_integer(g)
        bi = String.to_integer(b)

        if ri > 255 or gi > 255 or bi > 255 do
          :error
        else
          {:ok, {:rgba, {ri, gi, bi}, parse_alpha_value(a)}}
        end

      _ ->
        :error
    end
  end

  defp parse_rgb_values(r, g, b) when r > 255 or g > 255 or b > 255, do: :error
  defp parse_rgb_values(r, g, b), do: {:ok, {r, g, b}}

  defp parse_alpha_value(a) do
    a = String.trim(a)

    cond do
      String.starts_with?(a, ".") ->
        String.to_float("0" <> a)

      String.contains?(a, ".") ->
        String.to_float(a)

      true ->
        String.to_integer(a) / 1.0
    end
  end
end
