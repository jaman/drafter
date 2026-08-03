defmodule Drafter.Widget.Scrollbar do
  @moduledoc false

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}

  @doc """
  The inclusive range of viewport rows the thumb occupies, or `nil` when the content
  fits and no scrollbar is needed.

  The thumb is `viewport_height²/total` rows, rounded, with a floor of one row, and
  slides over a track of `viewport_height - thumb_size` rows.

      iex> Drafter.Widget.Scrollbar.thumb_rows(0, 20, 10)
      0..4

      iex> Drafter.Widget.Scrollbar.thumb_rows(10, 20, 10)
      5..9

      iex> Drafter.Widget.Scrollbar.thumb_rows(0, 10, 10)
      nil
  """
  @spec thumb_rows(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: Range.t() | nil
  def thumb_rows(scroll_offset, total, viewport_height)
      when viewport_height > 0 and total > viewport_height do
    thumb_size = max(1, min(viewport_height, round(viewport_height * viewport_height / total)))
    max_offset = total - viewport_height
    track = viewport_height - thumb_size
    pos = if max_offset > 0, do: round(scroll_offset / max_offset * track), else: 0
    pos = pos |> max(0) |> min(track)
    pos..(pos + thumb_size - 1)
  end

  def thumb_rows(_scroll_offset, _total, _viewport_height), do: nil

  @doc """
  The scroll offset that places the thumb's top at a given viewport row.

  The inverse of `thumb_rows/3`. The row is clamped to the track, and the result
  is clamped to `0..(total - viewport_height)`. Returns `0` when the content fits.

      iex> Drafter.Widget.Scrollbar.offset_from_row(0, 20, 10)
      0

      iex> Drafter.Widget.Scrollbar.offset_from_row(5, 20, 10)
      10

      iex> Drafter.Widget.Scrollbar.offset_from_row(99, 20, 10)
      10

      iex> Drafter.Widget.Scrollbar.offset_from_row(3, 10, 10)
      0
  """
  @spec offset_from_row(integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def offset_from_row(row, total, viewport_height)
      when viewport_height > 0 and total > viewport_height do
    thumb_size = max(1, min(viewport_height, round(viewport_height * viewport_height / total)))
    track = viewport_height - thumb_size
    max_offset = total - viewport_height

    if track <= 0 do
      clamp(row, 0, max_offset)
    else
      row
      |> clamp(0, track)
      |> Kernel./(track)
      |> Kernel.*(max_offset)
      |> round()
      |> clamp(0, max_offset)
    end
  end

  def offset_from_row(_row, _total, _viewport_height), do: 0

  @doc """
  The distance from the thumb's top to the pressed row.

  Returns `0` when the press lands on the track rather than the thumb, or when
  no scrollbar is drawn. Pass the result to `offset_from_drag/4`.

      iex> Drafter.Widget.Scrollbar.grab_offset(2, 0, 20, 10)
      2

      iex> Drafter.Widget.Scrollbar.grab_offset(8, 0, 20, 10)
      0
  """
  @spec grab_offset(integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def grab_offset(row, scroll_offset, total, viewport_height) do
    case thumb_rows(scroll_offset, total, viewport_height) do
      nil -> 0
      thumb -> if row in thumb, do: row - thumb.first, else: 0
    end
  end

  @doc """
  The scroll offset for a drag, holding the grabbed point under the pointer.

  Equivalent to `offset_from_row(row - grab_offset, total, viewport_height)`.

      iex> Drafter.Widget.Scrollbar.offset_from_drag(7, 2, 20, 10)
      10

      iex> Drafter.Widget.Scrollbar.offset_from_drag(2, 2, 20, 10)
      0
  """
  @spec offset_from_drag(integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def offset_from_drag(row, grab_offset, total, viewport_height) do
    offset_from_row(row - grab_offset, total, viewport_height)
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  @doc """
  Thumb/track styles matching `ScrollableContainer`, derived from the theme.

  Reads `:primary`, `:text_muted` and `:surface` from `theme`.

      iex> Drafter.Widget.Scrollbar.styles(%{primary: {1, 2, 3}, text_muted: {4, 5, 6}, surface: {7, 8, 9}})
      %{thumb: %{fg: {1, 2, 3}, bg: {1, 2, 3}}, track: %{fg: {4, 5, 6}, bg: {7, 8, 9}}}
  """
  @spec styles(map()) :: %{thumb: Segment.style(), track: Segment.style()}
  def styles(theme) do
    %{
      thumb: %{fg: theme.primary, bg: theme.primary},
      track: %{fg: theme.text_muted, bg: theme.surface}
    }
  end

  @doc "The scrollbar cell (glyph + style) for a viewport row, using the active skin's glyphs."
  @spec segment(non_neg_integer(), Range.t() | nil, %{
          thumb: Segment.style(),
          track: Segment.style()
        }) ::
          Segment.t()
  def segment(row, thumb, styles) do
    if thumb && row in thumb do
      Segment.new(CharacterSet.scroll(:thumb), styles.thumb)
    else
      Segment.new(CharacterSet.scroll(:track), styles.track)
    end
  end

  @doc "Append a one-column scrollbar cell for the given viewport row to a strip."
  @spec append(Strip.t(), non_neg_integer(), Range.t() | nil, map()) :: Strip.t()
  def append(strip, _row, nil, _styles), do: strip

  def append(strip, row, thumb, styles) do
    Strip.combine(strip, Strip.new([segment(row, thumb, styles)]))
  end
end
