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

  test "a partially clipped widget is visible, and reports the part that shows" do
    WidgetStripCache.mark_visible(:w, %{x: 0, y: 0, width: 40, height: 7})

    assert WidgetStripCache.visible?(:w)
    assert WidgetStripCache.visible_rect(:w).height == 7
  end

  test "a widget taller than its viewport still counts as visible" do
    WidgetStripCache.mark_visible(:tall, %{x: 0, y: 0, width: 40, height: 12})

    assert WidgetStripCache.visible?(:tall),
           "a chart taller than the viewport must not be treated as hidden"
  end

  test "an unknown widget is neither visible nor has a region" do
    assert WidgetStripCache.visible?(:never_seen) == false
    assert WidgetStripCache.visible_rect(:never_seen) == nil
  end

  test "marking invisible clears a previously reported region" do
    WidgetStripCache.mark_visible(:w, %{x: 0, y: 0, width: 40, height: 7})
    WidgetStripCache.mark_visible(:w, false)

    assert WidgetStripCache.visible_rect(:w) == nil
  end
end
