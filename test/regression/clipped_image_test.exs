defmodule Drafter.Regression.ClippedImageTest do
  use ExUnit.Case, async: false

  alias Drafter.WidgetStripCache

  setup do
    WidgetStripCache.create()
    :ok
  end

  test "a widget with nothing on screen is marked invisible" do
    WidgetStripCache.mark_visible(:w, false)

    refute WidgetStripCache.visible?(:w)
    assert WidgetStripCache.visible_rect(:w) == nil
  end

  test "an unknown widget is neither visible nor has a region" do
    assert WidgetStripCache.visible?(:never_seen) == false
    assert WidgetStripCache.visible_rect(:never_seen) == nil
  end
end
