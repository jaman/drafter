defmodule Drafter.Terminal.Reports do
  @moduledoc """
  Replies to the questions a driver asks a terminal at startup, other than the graphics
  and keyboard ones.

  `cell_size_query/0` asks for the size of one cell in pixels; the reply
  `CSI 6 ; height ; width t` parses to `{:cell_size, {width, height}}`.
  """

  @doc "The sequence that asks the terminal how many pixels one cell is."
  @spec cell_size_query() :: String.t()
  def cell_size_query, do: "\e[16t"

  @doc "Parse a report at the head of `buffer`, or `:no_match`."
  @spec parse(binary()) :: {[{:cell_size, {pos_integer(), pos_integer()}}], binary()} | :no_match
  def parse(<<"\e[6;", rest::binary>>) do
    with {height, <<";", after_height::binary>>} <- Integer.parse(rest),
         {width, <<"t", after_report::binary>>} <- Integer.parse(after_height),
         true <- height > 0 and width > 0 do
      {[{:cell_size, {width, height}}], after_report}
    else
      _ -> :no_match
    end
  end

  def parse(_buffer), do: :no_match
end
