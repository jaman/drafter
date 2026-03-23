defmodule Drafter.SyntaxHighlighter do
  @moduledoc false

  def highlight(lines, language) when is_list(lines) do
    Enum.map(lines, fn line -> highlight_line(line, language) end)
  end

  def highlight(content, language) when is_binary(content) do
    content
    |> String.split("\n")
    |> highlight(language)
    |> Enum.join("\n")
  end

  defp highlight_line(line, :elixir) do
    cond do
      String.trim_leading(line) |> String.starts_with?("#") ->
        "\e[90m#{line}\e[0m"

      String.match?(line, ~r/\b(defmodule|def|defp|use|import|alias|do|end|if|else|case|when|try|rescue|catch|raise)\b/) ->
        String.replace(line, ~r/\b(defmodule|def|defp|use|import|alias|do|end|if|else|case|when|try|rescue|catch|raise)\b/, "\e[35m\\1\e[0m")

      String.contains?(line, ~s(")) ->
        String.replace(line, ~r/"([^"]*)"/, "\e[32m\"\\1\"\e[0m")

      String.match?(line, ~r/:\w+/) ->
        String.replace(line, ~r/(:\w+)/, "\e[36m\\1\e[0m")

      true ->
        line
    end
  end

  defp highlight_line(line, :python) do
    cond do
      String.trim_leading(line) |> String.starts_with?("#") ->
        "\e[90m#{line}\e[0m"

      String.match?(line, ~r/\b(def|class|import|from|return|if|else|elif|for|while|try|except|with|as)\b/) ->
        String.replace(line, ~r/\b(def|class|import|from|return|if|else|elif|for|while|try|except|with|as)\b/, "\e[35m\\1\e[0m")

      String.contains?(line, ~s(")) or String.contains?(line, ~s(')) ->
        line
        |> String.replace(~r/"([^"]*)"/, "\e[32m\"\\1\"\e[0m")
        |> String.replace(~r/'([^']*)'/, "\e[32m'\\1'\e[0m")

      true ->
        line
    end
  end

  defp highlight_line(line, :javascript) do
    cond do
      String.contains?(line, "//") ->
        parts = String.split(line, "//", parts: 2)
        "#{Enum.at(parts, 0)}\e[90m//#{Enum.at(parts, 1)}\e[0m"

      String.match?(line, ~r/\b(function|const|let|var|return|if|else|for|while|class|async|await)\b/) ->
        String.replace(line, ~r/\b(function|const|let|var|return|if|else|for|while|class|async|await)\b/, "\e[35m\\1\e[0m")

      true ->
        line
    end
  end

  defp highlight_line(line, :erlang) do
    if String.trim_leading(line) |> String.starts_with?("%") do
      "\e[90m#{line}\e[0m"
    else
      line
    end
  end

  defp highlight_line(line, _language) do
    line
  end
end
