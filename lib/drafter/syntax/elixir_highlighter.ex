defmodule Drafter.Syntax.ElixirHighlighter do
  @moduledoc false

  @behaviour Drafter.Syntax.Highlighter

  @keyword_identifiers ~w(def defp defmodule defmacro defmacrop defguard defguardp defprotocol defimpl defstruct use import alias require)a

  @impl true
  @spec highlight(String.t(), atom()) :: [Drafter.Syntax.Highlighter.capture()]
  def highlight(source, :elixir), do: tokenize(source)
  def highlight(source, :exs), do: tokenize(source)
  def highlight(_source, _language), do: []

  defp tokenize(source) do
    case :elixir.string_to_tokens(String.to_charlist(source), 1, 1, "nofile", []) do
      {:ok, tokens} -> Enum.flat_map(tokens, &token_to_capture/1)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp token_to_capture({:identifier, {line, col, raw}, value})
       when value in @keyword_identifiers do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "keyword"}]
  end

  defp token_to_capture({:identifier, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "variable"}]
  end

  defp token_to_capture({:alias, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "type"}]
  end

  defp token_to_capture({:atom, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value) + 1, "string.special"}]
  end

  defp token_to_capture({:atom_quoted, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value) + 3, "string.special"}]
  end

  defp token_to_capture({:bin_string, {line, col, _raw}, parts}) do
    sc = col - 1
    len = estimate_string_length(parts)
    [{line, sc, line, sc + len + 2, "string"}]
  end

  defp token_to_capture({:list_string, {line, col, _raw}, parts}) do
    sc = col - 1
    len = estimate_string_length(parts)
    [{line, sc, line, sc + len + 2, "string"}]
  end

  defp token_to_capture({:int, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "number"}]
  end

  defp token_to_capture({:flt, {line, col, raw}, value}) do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "number"}]
  end

  defp token_to_capture({op, {line, col, raw}, value})
       when op in [:and_op, :or_op, :comp_op, :dual_op, :operator_identifier] do
    sc = col - 1
    [{line, sc, line, sc + raw_length(raw, value), "operator"}]
  end

  defp token_to_capture({:do, {line, col, _}}),
    do: [{line, col - 1, line, col + 1, "keyword.builtin"}]

  defp token_to_capture({:end, {line, col, _}}),
    do: [{line, col - 1, line, col + 2, "keyword.builtin"}]

  defp token_to_capture({true, {line, col, _}}),
    do: [{line, col - 1, line, col + 3, "keyword.builtin"}]

  defp token_to_capture({false, {line, col, _}}),
    do: [{line, col - 1, line, col + 4, "keyword.builtin"}]

  defp token_to_capture({nil, {line, col, _}}),
    do: [{line, col - 1, line, col + 2, "keyword.builtin"}]

  defp token_to_capture({:sigil, {line, col, _}, _name, _parts, _mods, _delim}) do
    sc = col - 1
    [{line, sc, line, sc + 3, "string.special"}]
  end

  defp token_to_capture(_), do: []

  defp raw_length(raw, _value) when is_list(raw) and raw != [], do: length(raw)
  defp raw_length(_raw, value) when is_atom(value), do: value |> Atom.to_string() |> byte_size()
  defp raw_length(_raw, value) when is_binary(value), do: byte_size(value)

  defp raw_length(_raw, value) when is_integer(value),
    do: value |> Integer.to_string() |> byte_size()

  defp raw_length(_raw, value) when is_float(value), do: value |> Float.to_string() |> byte_size()
  defp raw_length(_raw, _value), do: 1

  defp estimate_string_length(parts) when is_list(parts) do
    Enum.reduce(parts, 0, fn
      bin, acc when is_binary(bin) -> acc + byte_size(bin)
      _other, acc -> acc + 4
    end)
  end

  defp estimate_string_length(_), do: 0
end
