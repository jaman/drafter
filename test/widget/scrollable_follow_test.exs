defmodule Drafter.Widget.ScrollableFollowTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.ScrollableContainer

  defp container(follow) do
    ScrollableContainer.mount(%{content_height: 30, viewport_height: 10, follow: follow})
  end

  test "a following viewport starts at the bottom" do
    assert container(true).scroll_offset_y == 20
    assert container(false).scroll_offset_y == 0
  end

  test "a following viewport at the bottom stays at the bottom as the content grows" do
    at_bottom = ScrollableContainer.update(%{scroll_offset_y: 20}, container(true))

    assert ScrollableContainer.update(%{content_height: 45}, at_bottom).scroll_offset_y == 35
  end

  test "a following viewport scrolled up, or one not following, stays where it is" do
    scrolled_up = ScrollableContainer.update(%{scroll_offset_y: 5}, container(true))
    assert ScrollableContainer.update(%{content_height: 45}, scrolled_up).scroll_offset_y == 5

    still = ScrollableContainer.update(%{scroll_offset_y: 20}, container(false))
    assert ScrollableContainer.update(%{content_height: 45}, still).scroll_offset_y == 20
  end
end
