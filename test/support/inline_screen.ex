defmodule Drafter.TestSupport.InlineScreen do
  @moduledoc """
  A terminal of fixed height that understands what `Drafter.Prompt.Region` writes:
  text, carriage return, line feed with scrolling, cursor up, down and right, and
  erasing to the end of the line and of the screen.

      screen = InlineScreen.new(4, 3)
      screen = InlineScreen.write(screen, "one\\r\\ntwo")
      InlineScreen.lines(screen)
      #=> ["", "", "one", "two"]
  """

  defstruct height: 24, grid: %{}, row: 0, column: 0

  @type t :: %__MODULE__{
          height: pos_integer(),
          grid: %{{non_neg_integer(), non_neg_integer()} => String.t()},
          row: non_neg_integer(),
          column: non_neg_integer()
        }

  @doc "An empty screen `height` rows tall with the cursor at the start of `row`."
  @spec new(pos_integer(), non_neg_integer()) :: t()
  def new(height, row \\ 0), do: %__MODULE__{height: height, row: row}

  @doc "Apply `bytes` to the screen."
  @spec write(t(), iodata()) :: t()
  def write(%__MODULE__{} = screen, bytes), do: step(IO.iodata_to_binary(bytes), screen)

  @doc "The text of every row, top to bottom, trailing blanks trimmed."
  @spec lines(t()) :: [String.t()]
  def lines(%__MODULE__{height: height} = screen),
    do: Enum.map(0..(height - 1), &line(screen, &1))

  @doc "The cursor as `{row, column}`."
  @spec cursor(t()) :: {non_neg_integer(), non_neg_integer()}
  def cursor(%__MODULE__{row: row, column: column}), do: {row, column}

  defp line(screen, row) do
    case for({{^row, column}, _character} <- screen.grid, do: column) do
      [] ->
        ""

      columns ->
        0..Enum.max(columns)
        |> Enum.map_join(&Map.get(screen.grid, {row, &1}, " "))
        |> String.trim_trailing()
    end
  end

  defp step("", screen), do: screen

  defp step("\e[" <> rest, screen) do
    {parameter, <<final, rest::binary>>} = parameter(rest, "")
    step(rest, control(final, parameter, screen))
  end

  defp step("\r" <> rest, screen), do: step(rest, %{screen | column: 0})
  defp step("\n" <> rest, screen), do: step(rest, line_feed(screen))

  defp step(<<character::utf8, rest::binary>>, screen) do
    grid = Map.put(screen.grid, {screen.row, screen.column}, <<character::utf8>>)
    step(rest, %{screen | grid: grid, column: screen.column + 1})
  end

  defp parameter(<<character, rest::binary>>, acc)
       when character in ?0..?9 or character in ~c";?",
       do: parameter(rest, acc <> <<character>>)

  defp parameter(rest, acc), do: {acc, rest}

  defp control(?A, count, screen), do: %{screen | row: max(screen.row - count(count), 0)}

  defp control(?B, count, screen),
    do: %{screen | row: min(screen.row + count(count), screen.height - 1)}

  defp control(?C, count, screen), do: %{screen | column: screen.column + count(count)}
  defp control(?K, _mode, screen), do: erase(screen, &(&1 == screen.row and &2 >= screen.column))

  defp control(?J, _mode, screen),
    do: erase(screen, &(&1 > screen.row or (&1 == screen.row and &2 >= screen.column)))

  defp control(_final, _parameter, screen), do: screen

  defp count(""), do: 1
  defp count(digits), do: String.to_integer(digits)

  defp erase(screen, erased?) do
    grid =
      for {{row, column}, character} <- screen.grid,
          not erased?.(row, column),
          into: %{},
          do: {{row, column}, character}

    %{screen | grid: grid}
  end

  defp line_feed(%__MODULE__{row: row, height: height} = screen) when row < height - 1,
    do: %{screen | row: row + 1}

  defp line_feed(screen) do
    grid =
      for {{row, column}, character} <- screen.grid,
          row > 0,
          into: %{},
          do: {{row - 1, column}, character}

    %{screen | grid: grid}
  end
end
