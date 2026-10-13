defmodule Drafter.Terminal.Reports do
  @moduledoc """
  Replies to the questions a driver asks a terminal at startup, other than the graphics
  and keyboard ones.

  `cell_size_query/0` asks for the size of one cell in pixels; `size_queries/0` asks
  for that in both the standard form and iTerm2's own (`OSC 1337 ; ReportCellSize`),
  the text area's size in pixels and its size in cells. The replies parse to `{:cell_size, {width, height}}`
  (`CSI 6 ; height ; width t`), `{:window_pixels, {width, height}}`
  (`CSI 4 ; height ; width t`) and `{:text_cells, {cols, rows}}`
  (`CSI 8 ; rows ; cols t`); iTerm2's `OSC 1337 ; ReportCellSize = height ; width ;
  scale` reply, sizes in points, parses to `{:cell_size, {width × scale, height ×
  scale}}` in pixels. A terminal may answer some and not others.

      iex> Drafter.Terminal.Reports.parse("\\e]1337;ReportCellSize=13.0;6.0;2.0\\e\\\\")
      {[{:cell_size, {12, 26}}], ""}

      iex> Drafter.Terminal.Reports.parse("\\e[4;745;1353t\\e[8;59;221t")
      {[{:window_pixels, {1353, 745}}], "\\e[8;59;221t"}

  `pixel_mouse_query/0` asks whether pixel mouse reporting (mode 1016) is set; the reply
  `CSI ? 1016 ; status $ y` parses to `{:pixel_mouse, true}` when the status is `1`
  (set) or `3` (permanently set), and `{:pixel_mouse, false}` for any other status,
  including `0` from a terminal that does not know the mode.

      iex> Drafter.Terminal.Reports.parse("\\e[?1016;1$y")
      {[{:pixel_mouse, true}], ""}

      iex> Drafter.Terminal.Reports.parse("\\e[?1016;0$y")
      {[{:pixel_mouse, false}], ""}
  """

  @typedoc "An event a report parses to."
  @type report ::
          {:cell_size, {pos_integer(), pos_integer()}}
          | {:window_pixels, {pos_integer(), pos_integer()}}
          | {:text_cells, {pos_integer(), pos_integer()}}
          | {:pixel_mouse, boolean()}

  @doc "The sequence that asks the terminal how many pixels one cell is."
  @spec cell_size_query() :: String.t()
  def cell_size_query, do: "\e[16t"

  @doc """
  The sequences that ask the terminal how many pixels one cell is, how many pixels its
  text area is, and how many cells, for terminals that answer only some of them.
  """
  @spec size_queries() :: String.t()
  def size_queries, do: cell_size_query() <> "\e]1337;ReportCellSize\a\e[14t\e[18t"

  @doc "The sequence that asks the terminal whether pixel mouse reporting is set."
  @spec pixel_mouse_query() :: String.t()
  def pixel_mouse_query, do: "\e[?1016$p"

  @doc "Parse a report at the head of `buffer`, or `:no_match`."
  @spec parse(binary()) :: {[report()], binary()} | :no_match
  def parse(<<"\e[6;", rest::binary>>), do: size_report(rest, :cell_size)
  def parse(<<"\e[4;", rest::binary>>), do: size_report(rest, :window_pixels)
  def parse(<<"\e[8;", rest::binary>>), do: size_report(rest, :text_cells)

  def parse(<<"\e[?1016;", rest::binary>>) do
    case Integer.parse(rest) do
      {status, <<"$y", after_report::binary>>} ->
        {[{:pixel_mouse, status in [1, 3]}], after_report}

      _ ->
        :no_match
    end
  end

  def parse(<<"\e]1337;ReportCellSize=", rest::binary>>) do
    with {:ok, body, after_report} <- string_body(rest),
         [height, width | scale] <- String.split(body, ";"),
         {cell_height, ""} <- Float.parse(height),
         {cell_width, ""} <- Float.parse(width),
         {factor, ""} <- Float.parse(List.first(scale, "1")),
         true <- cell_height > 0 and cell_width > 0 and factor > 0 do
      {[{:cell_size, {round(cell_width * factor), round(cell_height * factor)}}], after_report}
    else
      _ -> :no_match
    end
  end

  def parse(_buffer), do: :no_match

  defp string_body(rest) do
    case :binary.match(rest, ["\e\\", "\a"]) do
      {index, length} ->
        {:ok, binary_part(rest, 0, index),
         binary_part(rest, index + length, byte_size(rest) - index - length)}

      :nomatch ->
        :incomplete
    end
  end

  defp size_report(rest, kind) do
    with {first, <<";", after_first::binary>>} <- Integer.parse(rest),
         {second, <<"t", after_report::binary>>} <- Integer.parse(after_first),
         true <- first > 0 and second > 0 do
      {[{kind, {second, first}}], after_report}
    else
      _ -> :no_match
    end
  end
end
