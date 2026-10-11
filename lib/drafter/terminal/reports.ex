defmodule Drafter.Terminal.Reports do
  @moduledoc """
  Replies to the questions a driver asks a terminal at startup, other than the graphics
  and keyboard ones.

  `cell_size_query/0` asks for the size of one cell in pixels; the reply
  `CSI 6 ; height ; width t` parses to `{:cell_size, {width, height}}`.

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
  @type report :: {:cell_size, {pos_integer(), pos_integer()}} | {:pixel_mouse, boolean()}

  @doc "The sequence that asks the terminal how many pixels one cell is."
  @spec cell_size_query() :: String.t()
  def cell_size_query, do: "\e[16t"

  @doc "The sequence that asks the terminal whether pixel mouse reporting is set."
  @spec pixel_mouse_query() :: String.t()
  def pixel_mouse_query, do: "\e[?1016$p"

  @doc "Parse a report at the head of `buffer`, or `:no_match`."
  @spec parse(binary()) :: {[report()], binary()} | :no_match
  def parse(<<"\e[6;", rest::binary>>) do
    with {height, <<";", after_height::binary>>} <- Integer.parse(rest),
         {width, <<"t", after_report::binary>>} <- Integer.parse(after_height),
         true <- height > 0 and width > 0 do
      {[{:cell_size, {width, height}}], after_report}
    else
      _ -> :no_match
    end
  end

  def parse(<<"\e[?1016;", rest::binary>>) do
    case Integer.parse(rest) do
      {status, <<"$y", after_report::binary>>} ->
        {[{:pixel_mouse, status in [1, 3]}], after_report}

      _ ->
        :no_match
    end
  end

  def parse(_buffer), do: :no_match
end
