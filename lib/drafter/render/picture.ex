defmodule Drafter.Render.Picture do
  @moduledoc """
  Encodes a widget's picture into the bytes and region `Drafter.Compositor.put_image/4`
  takes.

  A widget exporting `image_raster/2` returns a `t:t/0`: a `FrenchCurve.Raster` covering a box
  of cells, the protocol to draw it with, and where the box sits in the widget. The
  widget server encodes it with `encode/3`.

  On a kitty terminal that keeps images under an id, the whole raster is stored once and
  the region carries `:crop`. The compositor then moves the image and shows any part of
  it with placements alone, so neither a move nor a scroll re-encodes it.

  Every other protocol sends the pixels themselves. Only the part of the box inside the
  visible window is encoded, and the region is reduced to that part, so a change of
  window needs a new encoding. `window_dependent?/1` says which case a picture is in.

      picture = %{raster: raster, protocol: :kitty, dx: 0, dy: 0, cols: 40, rows: 6}
      {paint, clear, region} = Drafter.Render.Picture.encode(picture, :my_chart, nil)

  Two optional keys change how a stored kitty image is sent, each on its own:

    * `format: :png` sends it as a PNG — a palette one when it has at most 256 colours —
      instead of deflated raw pixels (`FrenchCurve.Backend.Kitty.encode/2`), usually far
      smaller for flat-coloured pictures
    * `swap: true` keeps it under two image ids, a new frame stored under the one not on
      screen, placed, and only then the old one deleted, the whole sent as one
      synchronized update, so the terminal never shows the region empty between frames
  """

  alias Drafter.Session.Context
  alias FrenchCurve.Backend.Kitty
  alias FrenchCurve.{Capability, Raster}

  @typedoc """
  A widget's picture: `raster` drawn with `protocol` into the `cols` by `rows` cell box
  whose top left is `dx`, `dy` cells from the widget's top left.
  """
  @type t :: %{
          required(:raster) => Raster.t(),
          required(:protocol) => atom(),
          required(:dx) => non_neg_integer(),
          required(:dy) => non_neg_integer(),
          required(:cols) => pos_integer(),
          required(:rows) => pos_integer(),
          optional(:format) => :rgba | :png,
          optional(:swap) => boolean()
        }

  @typedoc "A rectangle of cells, relative to the widget's top left."
  @type window :: %{
          x: integer(),
          y: integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @typedoc """
  The stored kitty image a region shows: its kitty `image` id and its size in pixels. A
  picture sent with `swap: true` also has a `spare` id and its `encoded` pixels, which the
  compositor stores under whichever of the two is not on screen, after the region's own
  bytes.
  """
  @type crop :: %{
          required(:image) => pos_integer(),
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          optional(:spare) => pos_integer(),
          optional(:encoded) => Kitty.encoded()
        }

  @doc """
  Encodes `picture` for the image region `id`, showing the part inside `window`.

  `window` is the widget's visible cells relative to its top left, or `nil` when all of
  it is visible. It is ignored when the terminal keeps kitty images under an id.

  Returns `{paint, clear, region}`, or `nil` when no part of the picture is inside
  `window` or the protocol cannot draw it. With `:crop` in `region`, `paint` stores the
  image without drawing it, and the compositor places it.
  """
  @spec encode(t(), term(), window() | nil) :: {iodata(), iodata(), map()} | nil
  def encode(picture, id, window) do
    if placements?(picture.protocol),
      do: stored(picture, id),
      else: cropped(picture, id, visible_cells(picture, window))
  end

  @doc """
  Whether the encoding of `picture` depends on the visible window.

  False when the terminal keeps kitty images under an id, where the compositor crops
  the stored image; true for every other protocol.
  """
  @spec window_dependent?(t()) :: boolean()
  def window_dependent?(picture), do: not placements?(picture.protocol)

  @doc """
  The pixel rectangle `{x, y, width, height}` of a `width` by `height` pixel image drawn
  into `cols` by `rows` cells that covers the cells `{col, row, visible_cols,
  visible_rows}`, counted from the image's top left cell.

  Cell edges are mapped to pixels by rounding down, so adjacent cell ranges share their
  boundary pixel row and column exactly.

      iex> Drafter.Render.Picture.source({160, 48}, {40, 6}, {0, 2, 40, 3})
      {0, 16, 160, 24}
  """
  @spec source(
          {pos_integer(), pos_integer()},
          {pos_integer(), pos_integer()},
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}
        ) :: {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}
  def source({width, height}, {cols, rows}, {col, row, visible_cols, visible_rows}) do
    left = div(col * width, cols)
    top = div(row * height, rows)
    right = div((col + visible_cols) * width, cols)
    bottom = div((row + visible_rows) * height, rows)
    {left, top, max(1, right - left), max(1, bottom - top)}
  end

  @doc """
  The cells of `picture`'s box inside `window`, as `{col, row, cols, rows}` counted from
  the box's top left, or `nil` when none are. A `nil` window is the whole box.

      iex> picture = %{dx: 0, dy: 1, cols: 10, rows: 6}
      iex> Drafter.Render.Picture.visible_cells(picture, %{x: 0, y: 3, width: 10, height: 20})
      {0, 2, 10, 4}
  """
  @spec visible_cells(map(), window() | nil) ::
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()} | nil
  def visible_cells(picture, nil), do: {0, 0, picture.cols, picture.rows}

  def visible_cells(picture, window) do
    left = max(picture.dx, window.x)
    top = max(picture.dy, window.y)
    right = min(picture.dx + picture.cols, window.x + window.width)
    bottom = min(picture.dy + picture.rows, window.y + window.height)

    if right > left and bottom > top,
      do: {left - picture.dx, top - picture.dy, right - left, bottom - top},
      else: nil
  end

  defp placements?(:kitty), do: Capability.placements?(Context.terminal_env())
  defp placements?(_protocol), do: false

  defp stored(picture, id) do
    image = FrenchCurve.image_id(id)
    {width, height} = Raster.dimensions(picture.raster)

    encoded =
      Kitty.encode(picture.raster, format: Map.get(picture, :format, :rgba), compress: true)

    crop = %{image: image, width: width, height: height}
    region = %{dx: picture.dx, dy: picture.dy, cols: picture.cols, rows: picture.rows}

    if Map.get(picture, :swap, false) do
      spare = FrenchCurve.image_id({id, :spare})
      clear = [Kitty.delete(id: image), Kitty.delete(id: spare)]
      swapped = Map.merge(crop, %{spare: spare, encoded: encoded})
      {[], clear, Map.put(region, :crop, swapped)}
    else
      clear = Kitty.delete(id: image, placement: 1)
      {[clear, Kitty.transmit_encoded(encoded, image)], clear, Map.put(region, :crop, crop)}
    end
  end

  defp cropped(_picture, _id, nil), do: nil

  defp cropped(picture, id, {col, row, cols, rows} = cells) do
    raster = crop_raster(picture, cells)

    case FrenchCurve.frame(raster, id,
           fit: {cols, rows},
           protocol: picture.protocol,
           placements: false
         ) do
      nil ->
        nil

      {paint, clear, _place} ->
        {paint, clear, %{dx: picture.dx + col, dy: picture.dy + row, cols: cols, rows: rows}}
    end
  end

  defp crop_raster(%{cols: cols, rows: rows} = picture, {0, 0, cols, rows}), do: picture.raster

  defp crop_raster(picture, cells) do
    size = Raster.dimensions(picture.raster)
    {x, y, width, height} = source(size, {picture.cols, picture.rows}, cells)
    Raster.crop(picture.raster, {x, y}, {width, height})
  end
end
