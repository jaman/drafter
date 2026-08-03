defmodule Drafter.RuntimeDoctestTest do
  use ExUnit.Case, async: true

  doctest Drafter.Runtime
  doctest Drafter.Event
  doctest Drafter.EventResult
  doctest Drafter.Layout
  doctest Drafter.Style
  doctest Drafter.Theme
  doctest Drafter.Validation
  doctest Drafter.Visualization
  doctest Drafter.Visualization.LTTB
  doctest Drafter.WidgetHierarchy.Query
end
