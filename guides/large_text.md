# Large Text

`Drafter.Widget.Digits` draws headline figures and labels at several times the
height of ordinary text. This guide explains how the fonts are built and how to
choose between them; the API reference lives in `Drafter.Widget.Digits.Font`.

## Contents

- [Choosing a font](#choosing-a-font)
- [How the rasterised fonts are built](#how-the-rasterised-fonts-are-built)
- [Braille or quadrant](#braille-or-quadrant)
- [FIGlet fonts and full-width layout](#figlet-fonts-and-full-width-layout)
- [Rendering as an image](#rendering-as-an-image)

---

## Choosing a font

Fonts differ in cell footprint as much as in style, so picking one is partly a
layout decision. A single headline reading can afford seven columns per
character; a row of six stat panels cannot.

| Name | Cell | Character of the result |
|---|---|---|
| `:block` | 7×5 | Box-drawing outlines. The default for a headline figure. |
| `:compact` | 5×3 | The same outlines at half the height, for stat rows and dense tables. |
| `:tall` | 8×4 | Half blocks. The widest and boldest. |
| `:pixel` | 4×4 | Quadrant blocks. |
| `:braille` | 4×4 | Braille. The finest detail at that footprint. |

Every built-in font covers the same repertoire — digits, upper and lower case,
and common punctuation — so swapping one for another never drops characters.

A character the font cannot draw renders as blanks of the font's widest glyph
rather than raising. A display that loses one glyph is preferable to a display
that crashes, and reserving the width keeps the surrounding layout intact.

## How the rasterised fonts are built

`:tall`, `:pixel` and `:braille` are not authored as glyph art. They are
rasterised at compile time from a single set of 8×16 pixel bitmaps in
`Drafter.Widget.Digits.Bitmap`, using the pixel packings in
`Drafter.Widget.Digits.Raster` — the same packings the chart renderers use, so a
headline figure is drawn with the technique that draws the plot beside it.

Sixteen rows is the resolution braille asks for: it packs 2×4 pixels into a
cell, so a four-row glyph needs sixteen pixel rows to fill it. The coarser
packings downsample from those same bitmaps rather than carrying shapes of their
own. Each glyph is therefore authored once and rendered at three densities, and
the three fonts cannot drift apart as they are edited.

When a packing shrinks the bitmap, a shrunk pixel is lit if any pixel it covers
was lit. That keeps thin strokes from disappearing at the coarser densities.

## Braille or quadrant

`:braille` and `:pixel` occupy the same four by four cells. Braille carries
eight pixels per cell against quadrant's four, so it resolves finer curves.
Quadrant blocks survive terminal fonts with poor braille coverage. Prefer
`:braille` unless you know the target terminal's font is weak there.

## FIGlet fonts and full-width layout

`Drafter.Widget.Digits.Figlet` parses `.flf` files, which opens the catalogue to
the several hundred published FIGlet fonts — a far larger repertoire than is
worth authoring by hand.

Drafter lays FIGlet glyphs out full width: characters are placed side by side
with no kerning or smushing. Every FIGlet font supports that layout, and it is
the only layout whose spacing can be computed without interpreting a font's
smushing rules, so a font can never render narrower than the space reserved for
it.

Hardblanks are spaces a smushing layout must not eat. With full-width layout
nothing is eaten, so they render as plain spaces.

FIGlet fonts are proportional. `Drafter.Widget.Digits.Font.width/1` reports the
widest glyph, which is the space a character *might* take; use `text_width/2` to
measure what a string will actually occupy.

## Rendering as an image

With `renderer: :graphics`, a terminal that speaks the kitty, iTerm2, or sixel
protocol receives the text as a transmitted picture rather than as block
characters. The glyph bitmaps are scaled into a raster, so strokes land on pixel
boundaries instead of cell boundaries and the text stays smooth at whatever size
the layout gives it.

Scale never drops below one: the bitmaps are the finest detail available, and a
raster at native size is still sharper than cells. When the box is smaller than
that, the encoder's `fit` scales the finished picture down rather than drawing
the glyphs incomplete.

Nothing here is required for `Drafter.Widget.Digits` to work. Where no protocol
is available, `Drafter.Widget.Digits.Image` returns `nil` and the widget renders
cells as usual.
