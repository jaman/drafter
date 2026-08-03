defmodule Drafter.DrawDoctestTest do
  use ExUnit.Case, async: true

  doctest Drafter.Draw.BoxDrawing
  doctest Drafter.Draw.Canvas
  doctest Drafter.Draw.Segment
  doctest Drafter.Draw.Strip

  doctest Drafter.Style.Computed
  doctest Drafter.Style.CSSParser
  doctest Drafter.Style.Selector
  doctest Drafter.Style.Stylesheet
  doctest Drafter.Style.WidgetStyles

  doctest Drafter.Event.Object
end
