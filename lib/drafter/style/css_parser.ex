defmodule Drafter.Style.CSSParser do
  @moduledoc false

  alias Drafter.Style.Stylesheet

  @type parse_result :: {:ok, Stylesheet.t()} | {:error, String.t()}

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

  def parse_rgb_color(str) do
    case Regex.run(~r/^rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i, str) do
      [_, r, g, b] ->
        parse_rgb_values(String.to_integer(r), String.to_integer(g), String.to_integer(b))

      _ ->
        :error
    end
  end

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
