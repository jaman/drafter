defmodule Drafter.Widget.Scrollbar do
  @moduledoc false

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}

  @doc """
  The inclusive range of viewport rows the thumb occupies, or `nil` when the content
  fits and no scrollbar is needed.
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

  @doc "Thumb/track styles matching `ScrollableContainer`, derived from the theme."
  @spec styles(map()) :: %{thumb: Segment.style(), track: Segment.style()}
  def styles(theme) do
    %{
      thumb: %{fg: theme.primary, bg: theme.primary},
      track: %{fg: theme.text_muted, bg: theme.surface}
    }
  end

  @doc "The scrollbar cell (glyph + style) for a viewport row, using the active skin's glyphs."
  @spec segment(non_neg_integer(), Range.t() | nil, %{thumb: Segment.style(), track: Segment.style()}) ::
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
