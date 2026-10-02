defmodule Drafter.TestSupport.ScreenModel do
  @moduledoc """
  Replays terminal writes onto a grid of characters so a test can read what is on
  screen rather than what any one write carried.

      writes |> ScreenModel.apply() |> ScreenModel.row(0)
  """

  @type screen :: %{{non_neg_integer(), non_neg_integer()} => String.t()}

  @doc "Apply a list of writes, in order, starting from an empty screen with the cursor at the top left."
  @spec apply([binary()], screen()) :: screen()
  def apply(writes, screen \\ %{}) do
    {screen, _cursor} =
      Enum.reduce(writes, {screen, {0, 0}}, fn write, {screen, cursor} ->
        step(write, screen, cursor)
      end)

    screen
  end

  @doc "Whether any row shows `text`."
  @spec shows?(screen(), String.t()) :: boolean()
  def shows?(screen, text) do
    rows = for {{row, _column}, _} <- screen, uniq: true, do: row
    Enum.any?(rows, &String.contains?(row(screen, &1), text))
  end

  @doc "The text of `row` (zero-based), trailing blanks trimmed."
  @spec row(screen(), non_neg_integer()) :: String.t()
  def row(screen, row) do
    columns = for {{^row, column}, _} <- screen, do: column

    case columns do
      [] ->
        ""

      _ ->
        0..Enum.max(columns)
        |> Enum.map_join(&Map.get(screen, {row, &1}, " "))
        |> String.trim_trailing()
    end
  end

  defp step("", screen, cursor), do: {screen, cursor}

  defp step("\e[" <> rest, screen, cursor) do
    {parameters, rest} = parameters(rest)
    <<final::utf8, rest::binary>> = rest
    step(rest, screen, control(final, parameters, cursor))
  end

  defp step("\e]" <> rest, screen, cursor) do
    [_osc, rest] = String.split(rest, "\e\\", parts: 2)
    step(rest, screen, cursor)
  end

  defp step(<<?\e, _char, rest::binary>>, screen, cursor), do: step(rest, screen, cursor)

  defp step(<<char::utf8, rest::binary>>, screen, {row, column}) do
    step(rest, Map.put(screen, {row, column}, <<char::utf8>>), {row, column + 1})
  end

  defp step(<<_byte, rest::binary>>, screen, cursor), do: step(rest, screen, cursor)

  defp parameters(binary) do
    {parameters, rest} = take_while_parameter(binary, "")
    {String.split(parameters, ";", trim: true), rest}
  end

  defp take_while_parameter(<<char, rest::binary>>, acc)
       when char in ?0..?9 or char in [?;, ??, ?>, ?=, ?<] do
    take_while_parameter(rest, acc <> <<char>>)
  end

  defp take_while_parameter(rest, acc), do: {acc, rest}

  defp control(?H, [row, column], _cursor),
    do: {String.to_integer(row) - 1, String.to_integer(column) - 1}

  defp control(?H, [], _cursor), do: {0, 0}
  defp control(_final, _parameters, cursor), do: cursor
end
