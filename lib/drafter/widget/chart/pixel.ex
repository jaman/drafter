defmodule Drafter.Widget.Chart.Pixel do
  @moduledoc """
  Draws a chart as a terminal image, braille or block characters, all from one
  drawing of the chart.

  A chart `spec` (its type, data and drawing options) is described as shapes in cell
  coordinates and painted at the resolution of the output: the terminal's own pixels
  per cell for an image sent with kitty, iTerm2 or sixel (`picture/3`), two by four
  dots per cell for braille (`braille_strips/2`), or the sub-cell grid of one of
  `FrenchCurve.Backend.Cells`' glyph sets (`cells_strips/3`). `mode/2` picks the
  output for a renderer setting.
  """

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Session.Context
  alias Drafter.Widget.Chart.{Paint, Scene}
  alias FrenchCurve.Backend.Cells
  alias FrenchCurve.{Capability, Raster}

  @pixel_protocols [:iterm2, :kitty, :sixel]
  @cell_sets [:half, :quad, :sextant, :octant]
  @modes [:auto, :pixel, :kitty, :iterm2, :sixel, :braille, :text | @cell_sets]
  @supported [
    :line,
    :braille,
    :step,
    :area,
    :braille_area,
    :stacked_area,
    :bar,
    :clustered_bar,
    :stacked_bar,
    :range_bar,
    :histogram,
    :scatter,
    :bubble,
    :candlestick,
    :heatmap,
    :pie,
    :gauge
  ]

  @spec supported() :: [atom()]
  def supported, do: @supported

  @doc """
  The list of mode atoms accepted by `:renderer`, `DRAFTER_MODE`, and the `mode:`
  run option: `#{inspect(@modes)}`.
  """
  @spec modes() :: [atom()]
  def modes, do: @modes

  @typedoc "How a chart or slider draws: an image, braille, block characters of a glyph set, or text."
  @type drawing :: :pixel | :braille | {:cells, FrenchCurve.Backend.Cells.set()} | :text

  @doc "The glyph sets accepted as modes, each drawing through `cells_strips/3`."
  @spec cell_sets() :: [atom()]
  def cell_sets, do: @cell_sets

  @spec mode(atom() | nil, atom()) :: drawing()
  def mode(renderer, type), do: to_mode(resolve(renderer), type)

  defp to_mode(_effective, type) when type not in @supported, do: :text
  defp to_mode(:text, _type), do: :text
  defp to_mode(:braille, _type), do: :braille
  defp to_mode(set, _type) when set in @cell_sets, do: {:cells, set}

  defp to_mode(effective, _type) when effective in [:auto, :pixel] do
    if detect(), do: :pixel, else: :braille
  end

  defp to_mode(proto, _type) when proto in @pixel_protocols, do: :pixel

  @doc """
  The graphics protocol to draw with, or `nil` when the terminal has none.

  A `renderer` naming a protocol (`:kitty`, `:iterm2`, `:sixel`) is used as given;
  any mode that is not `:auto` or `:pixel` has no protocol and returns `nil`.

  `:auto` and `:pixel` take what the terminal answered when it was probed at
  startup — see `Drafter.Terminal.Probe`. A terminal that was never probed, or
  that answered the probe without naming a protocol, is guessed at from its
  environment instead, through `FrenchCurve.Capability.detect/1`.

  Either way the terminal in question is the one this session is attached to, which
  for a session served over ssh or telnet is the connecting client's rather than
  the host's.
  """
  @spec protocol(atom() | nil) :: atom() | nil
  def protocol(renderer), do: protocol_for(resolve(renderer))

  defp protocol_for(effective) when effective in [:auto, :pixel], do: detect()
  defp protocol_for(proto) when proto in @pixel_protocols, do: proto
  defp protocol_for(_effective), do: nil

  @doc """
  Resolve an effective mode from precedence: the `DRAFTER_MODE` env var forces and
  wins over everything; otherwise an explicit per-widget `renderer` (any mode atom),
  then the runtime `:drafter` `:render_mode` application env, then `:text`.
  """
  @spec resolve(atom() | nil) :: atom()
  def resolve(renderer), do: env_mode() || widget_mode(renderer) || runtime_mode() || :text

  defp widget_mode(renderer) when renderer in @modes, do: renderer
  defp widget_mode(_renderer), do: nil

  defp env_mode do
    case System.get_env("DRAFTER_MODE") do
      blank when blank in [nil, ""] -> legacy_mode()
      value -> parse_mode(value)
    end
  end

  defp legacy_mode do
    if System.get_env("DRAFTER_NO_PIXEL") not in [nil, ""], do: :text
  end

  defp runtime_mode do
    case Application.get_env(:drafter, :render_mode) do
      mode when mode in @modes -> mode
      _ -> nil
    end
  end

  @mode_names Map.new(@modes, &{Atom.to_string(&1), &1})

  defp parse_mode(value), do: Map.get(@mode_names, value |> String.trim() |> String.downcase())

  @doc """
  The graphics protocol of this session's terminal, whatever mode is in force.

  What the terminal answered when it was probed at startup, or, when it was never
  probed or named no protocol, what its environment suggests through
  `FrenchCurve.Capability.detect/1`. `nil` when neither names one. An iTerm2 session is
  always judged by its environment, whatever it answered: `:iterm2`, or `:kitty` when
  `FRENCH_CURVE_ITERM2=kitty` is set (see `FrenchCurve.Capability`).
  """
  @spec terminal() :: atom() | nil
  def terminal, do: detect()

  defp detect do
    case Context.terminal_protocol() do
      {:ok, probed} when not is_nil(probed) -> unless_iterm2(probed)
      _unprobed_or_unnamed -> detect_from_env()
    end
  end

  defp unless_iterm2(probed) do
    if Capability.iterm2?(Context.terminal_env()), do: detect_from_env(), else: probed
  end

  defp detect_from_env do
    case Capability.detect(Context.terminal_env()) do
      :braille -> nil
      protocol -> protocol
    end
  end

  @default_image_scale 4

  @doc """
  Draws `spec` as a `Drafter.Render.Picture` filling a `cols` by `rows` cell box at the
  widget's top left, to be drawn with `protocol`.

  The image has the terminal's own pixel size per cell: `:cell_size` in `spec`, else
  the size the session's terminal reported (`Drafter.Session.Context.cell_size/0`),
  else `:scale` pixels across (default `4`) and twice that down. `:overlay` cells in
  `spec`, `{col, row, text, fg, bg}`, are drawn over the chart, and `:marker`, a
  `{col, color}` pair, shades that column behind it. Returns `nil` when `protocol`
  is `nil` or the chart cannot be drawn.
  """
  @spec picture(map(), atom() | nil, {pos_integer(), pos_integer()}) ::
          Drafter.Render.Picture.t() | nil
  def picture(_spec, nil, _cells), do: nil

  def picture(spec, protocol, {cols, rows}) do
    {sx, sy} = pixels_per_cell(spec)
    grid = %{cols: cols, rows: rows, sx: sx, sy: sy}

    case Scene.build(spec, grid) do
      nil ->
        nil

      scene ->
        raster =
          scene
          |> with_marker(Map.get(spec, :marker), grid)
          |> Paint.raster(grid)
          |> Paint.cells(label_cells(scene.labels) ++ Map.get(spec, :overlay, []), grid)

        %{
          raster: Raster.finalize(raster),
          protocol: protocol,
          dx: 0,
          dy: 0,
          cols: cols,
          rows: rows
        }
    end
  end

  @doc """
  The value range `spec` is drawn against in a `cols` by `rows` box, `{low, high}`, or
  `nil` when it cannot be drawn. Axis labels read it.
  """
  @spec value_range(map(), {pos_integer(), pos_integer()}) :: {number(), number()} | nil
  def value_range(spec, {cols, rows}) do
    case Scene.build(spec, %{cols: cols, rows: rows, sx: 2, sy: 4}) do
      nil -> nil
      scene -> scene.range
    end
  end

  @doc """
  Renders `spec` as `rows` strips of `cols` braille cells, or `nil` when it cannot be
  drawn. Labels the chart places in cells are written over the braille.
  """
  @spec braille_strips(map(), {pos_integer(), pos_integer()}) :: [Strip.t()] | nil
  def braille_strips(spec, {cols, rows}) do
    grid = %{cols: cols, rows: rows, sx: 2, sy: 4}

    case Scene.build(spec, grid) do
      nil ->
        nil

      scene ->
        scene
        |> Paint.raster(grid)
        |> FrenchCurve.render(:braille, [])
        |> rows_to_strips()
        |> fit_rows(rows, cols)
        |> put_labels(scene.labels)
    end
  end

  @doc """
  Renders `spec` as `rows` strips of `cols` cells in the glyph set `set`, or `nil` when
  it cannot be drawn. Labels the chart places in cells are written over the glyphs.
  """
  @spec cells_strips(map(), {pos_integer(), pos_integer()}, FrenchCurve.Backend.Cells.set()) ::
          [Strip.t()] | nil
  def cells_strips(spec, {cols, rows}, set) do
    {sx, sy} = Cells.subpixels(set)
    grid = %{cols: cols, rows: rows, sx: sx, sy: sy}

    case Scene.build(spec, grid) do
      nil ->
        nil

      scene ->
        scene
        |> Paint.raster(grid)
        |> FrenchCurve.render(:cells, set: set)
        |> cells_to_strips()
        |> fit_rows(rows, cols)
        |> put_labels(scene.labels)
    end
  end

  defp pixels_per_cell(spec) do
    case Map.get(spec, :cell_size) || Context.cell_size() do
      {width, height} when width > 0 and height > 0 ->
        {width, height}

      _unknown ->
        scale = Map.get(spec, :scale) || @default_image_scale
        {scale, scale * 2}
    end
  end

  defp with_marker(scene, {col, color}, grid)
       when is_integer(col) and col >= 0 and col < grid.cols,
       do: %{
         scene
         | shapes: [{:rects, [{col, 0, col + 1, grid.rows}], Scene.rgba(color)} | scene.shapes]
       }

  defp with_marker(scene, _marker, _grid), do: scene

  defp label_cells(labels) do
    for {col, row, text, color} <- labels,
        {char, offset} <- Enum.with_index(String.graphemes(text)),
        do: {col + offset, row, char, color, nil}
  end

  defp put_labels(strips, []), do: strips

  defp put_labels(strips, labels) do
    by_row = Enum.group_by(labels, &elem(&1, 1))

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, row} ->
      Enum.reduce(Map.get(by_row, row, []), strip, fn {col, _row, text, color}, acc ->
        overlay_text(acc, col, text, color)
      end)
    end)
  end

  defp overlay_text(strip, col, text, {r, g, b, _a}) do
    {before, rest} = Strip.divide(strip, col)
    {_covered, after_text} = Strip.divide(rest, String.length(text))

    before
    |> Strip.combine(Strip.new([Segment.new(text, %{fg: {r, g, b}})]))
    |> Strip.combine(after_text)
  end

  defp rows_to_strips(rows) do
    Enum.map(rows, fn row ->
      Strip.new(
        Enum.map(row, fn
          {glyph, nil} -> Segment.new(glyph)
          {glyph, {r, g, b}} -> Segment.new(glyph, %{fg: {r, g, b}})
        end)
      )
    end)
  end

  defp cells_to_strips(rows), do: Enum.map(rows, &Strip.from_cells/1)

  defp fit_rows(strips, rows, cols) do
    sized = Enum.map(strips, &Strip.fit_to_width(&1, cols))
    blank = Strip.new([Segment.new(String.duplicate(" ", cols))])

    if length(sized) >= rows do
      Enum.take(sized, rows)
    else
      sized ++ List.duplicate(blank, rows - length(sized))
    end
  end
end
