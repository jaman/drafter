defmodule Drafter.Style.CSSParser do
  @moduledoc false

  alias Drafter.Style.Stylesheet

  @type parse_result :: {:ok, Stylesheet.t()} | {:error, String.t()}

  @doc """
  Parse CSS content from a string.
  """
  def parse_string(css_content) when is_binary(css_content) do
    css_content
    |> preprocess_css()
    |> extract_css_rules()
    |> Enum.map(&parse_rule/1)
    |> Enum.flat_map(&expand_rule/1)
    |> Enum.reduce({:ok, Stylesheet.new()}, fn
      {:ok, rule}, {:ok, stylesheet} -> {:ok, Stylesheet.add_rule(stylesheet, rule.selector_string, rule.properties)}
      {:error, _} = error, _acc -> error
      _, {:error, _} = error -> error
    end)
  end

  defp expand_rule({:ok, %{selector_strings: selector_strings, properties: properties}}) do
    Enum.map(selector_strings, fn selector_string -> {:ok, %{selector_string: selector_string, properties: properties}} end)
  end

  defp expand_rule({:ok, %{selector: selector, properties: properties}}) when is_list(selector) do
    Enum.map(selector, fn selector_string -> {:ok, %{selector_string: selector_string, properties: properties}} end)
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
        {char, rest} = String.split_at(css_string, 1)
        extract_rules(rest, acc, buffer <> char)
    end
  end

  defp find_matching_brace(str) do
    find_matching_brace(str, 0, 0, "")
  end

  defp find_matching_brace("", _brace_count, _pos, _acc), do: :error

  defp find_matching_brace("{" <> rest, brace_count, pos, acc) do
    find_matching_brace(rest, brace_count + 1, pos + 1, acc <> "{")
  end

  defp find_matching_brace("}" <> rest, 1, pos, acc) do
    rule = String.slice(acc <> "}", 0, pos + 1)
    rest = String.slice(rest, 1, String.length(rest))
    {:ok, rule, rest}
  end

  defp find_matching_brace("}" <> rest, brace_count, pos, acc) do
    find_matching_brace(rest, brace_count - 1, pos + 1, acc <> "}")
  end

  defp find_matching_brace(<<char::utf8, rest::binary>>, brace_count, pos, acc) do
    find_matching_brace(rest, brace_count, pos + 1, acc <> <<char::utf8>>)
  end

  @doc """
  Parse CSS from a file.
  """
  def parse_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> parse_string(content)
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp parse_rule(line) do
    regex = ~r/^(.*?)\s*\{\s*(.*?)\s*\}$/

    case Regex.run(regex, line, [:dotall]) do
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
    String.split(selector_str, ",")
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
    Map.get(@property_key_map, key, String.to_atom(key))
  end

  defp parse_value(value_str) do
    value_str = String.trim(value_str)

    cond do
      value_str == "true" -> true
      value_str == "false" -> false
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
        String.to_atom(value_str)
    end
  end

  @doc """
  Parse a hex color string (e.g., "#ff0000" or "#f00").
  """
  def parse_hex_color("#" <> hex_str) do
    hex_str = String.downcase(hex_str)

    if Regex.match?(~r/^[0-9a-f]+$/, hex_str) do
      case String.length(hex_str) do
        3 ->
          {r, g, b} = {
            String.to_integer(String.slice(hex_str, 0, 1), 16) * 17,
            String.to_integer(String.slice(hex_str, 1, 1), 16) * 17,
            String.to_integer(String.slice(hex_str, 2, 1), 16) * 17
          }
          {:ok, {r, g, b}}

        6 ->
          {r, g, b} = {
            String.to_integer(String.slice(hex_str, 0, 2), 16),
            String.to_integer(String.slice(hex_str, 2, 2), 16),
            String.to_integer(String.slice(hex_str, 4, 2), 16)
          }
          {:ok, {r, g, b}}

        _ ->
          :error
      end
    else
      :error
    end
  end

  def parse_hex_color(_), do: :error

  @doc """
  Parse an RGB color string (e.g., "rgb(255, 0, 0)").
  """
  def parse_rgb_color(str) do
    case Regex.run(~r/^rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i, str) do
      [_, r, g, b] ->
        r = String.to_integer(r)
        g = String.to_integer(g)
        b = String.to_integer(b)

        if r > 255 or g > 255 or b > 255 do
          :error
        else
          {:ok, {r, g, b}}
        end

      _ ->
        :error
    end
  end

  @doc """
  Parse an RGBA color string (e.g., "rgba(255, 0, 0, 0.5)").
  """
  def parse_rgba_color(str) do
    case Regex.run(~r/^rgba\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)$/i, str) do
      [_, r, g, b, a] ->
        r = String.to_integer(r)
        g = String.to_integer(g)
        b = String.to_integer(b)

        if r > 255 or g > 255 or b > 255 do
          :error
        else
          alpha = parse_alpha_value(a)
          rgb = {r, g, b}
          {:ok, {:rgba, rgb, alpha}}
        end

      _ ->
        :error
    end
  end

  defp parse_alpha_value(a) do
    a = String.trim(a)

    cond do
      String.starts_with?(a, ".") ->
        String.to_float("0" <> a)

      String.contains?(a, ".") ->
        String.to_float(a)

      true ->
        a_int = String.to_integer(a)
        a_int / 1.0
    end
  end
end
