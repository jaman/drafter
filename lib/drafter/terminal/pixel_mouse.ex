defmodule Drafter.Terminal.PixelMouse do
  @moduledoc """
  What a driver writes to turn pixel mouse reporting (SGR-Pixels, DECSET 1016) on and
  off, and when.

  A driver keeps one of three states per terminal:

    * `:off` — mouse reports are in cells.
    * `:waiting` — pixel reports are wanted, but the terminal has not yet said how big a
      cell is, so pixels could not be turned into cells. The driver has asked.
    * `:on` — mode 1016 has been set and the terminal asked whether it took.

  Each function returns the new state and the bytes to write. Reports are read as
  pixels only after the terminal answers `Drafter.Terminal.Reports.pixel_mouse_query/0`
  with `{:pixel_mouse, true}`; a terminal that ignores mode 1016 answers `false`, its
  reports stay in cells, and their payloads carry no `:px`. Every terminal that knows
  mode 1016 answers the query; a terminal that answers neither yes nor no keeps cell
  reading.

      iex> Drafter.Terminal.PixelMouse.enable(:off, nil)
      {:waiting, "\\e[16t"}

      iex> Drafter.Terminal.PixelMouse.after_input(:waiting, {8, 16})
      {:on, "\\e[?1016h\\e[?1016$p"}
  """

  alias Drafter.Terminal.{ANSI, Reports}

  @type t :: :off | :waiting | :on

  @typedoc "The terminal's cell size in pixels, or `nil` when it has not reported one."
  @type cell_size :: {pos_integer(), pos_integer()} | nil

  @doc """
  The state a driver starts in for its `pixel_mouse` setup option. A driver starting
  in `:waiting` must ask for the cell size among its startup queries.

      iex> Drafter.Terminal.PixelMouse.start(true)
      :waiting
  """
  @spec start(boolean()) :: t()
  def start(true), do: :waiting
  def start(false), do: :off

  @doc """
  Ask for pixel reports. Sets mode 1016 at once when the cell size is known, and asks
  for the cell size otherwise.
  """
  @spec enable(t(), cell_size()) :: {t(), iodata()}
  def enable(:off, nil), do: {:waiting, Reports.cell_size_query()}
  def enable(:off, {_, _} = cell_size), do: after_input(:waiting, cell_size)
  def enable(state, _cell_size), do: {state, []}

  @doc """
  Return to cell reports. The terminal's answer to the query that follows turns pixel
  reading off in the parser.
  """
  @spec disable(t()) :: {t(), iodata()}
  def disable(:on), do: {:off, ANSI.disable_pixel_mouse() <> Reports.pixel_mouse_query()}
  def disable(_state), do: {:off, []}

  @doc """
  Call after decoding input, with the cell size now known: a `:waiting` driver sets
  mode 1016 and asks whether it took once the cell size has arrived.
  """
  @spec after_input(t(), cell_size()) :: {t(), iodata()}
  def after_input(:waiting, {_, _}),
    do: {:on, ANSI.enable_pixel_mouse() <> Reports.pixel_mouse_query()}

  def after_input(state, _cell_size), do: {state, []}

  @doc """
  What to write when the terminal is resized: the cell size query while pixel reports
  are on, since a change of font size changes both the grid and the cell.
  """
  @spec resized(t()) :: iodata()
  def resized(:on), do: Reports.cell_size_query()
  def resized(_state), do: []

  @doc "What to write when the terminal is restored: mode 1016 off when it was set."
  @spec cleanup(t()) :: iodata()
  def cleanup(:on), do: ANSI.disable_pixel_mouse()
  def cleanup(_state), do: []
end
