defmodule Drafter.Prompt.RegionTest do
  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.{Frame, Region}
  alias Drafter.TestSupport.InlineScreen

  defp frame(lines, cursor \\ nil), do: Frame.new(Enum.map(lines, &Strip.from_text/1), cursor)

  defp draw({screen, region}, frame, size \\ {80, 24}) do
    {bytes, region} = Region.draw(region, frame, size)
    {InlineScreen.write(screen, bytes), region}
  end

  test "a shorter frame replaces a taller one and leaves nothing of it behind" do
    {screen, _region} =
      {InlineScreen.new(6), %Region{}}
      |> draw(frame(["? Pick", "> one", "  two"]))
      |> draw(frame(["+ Pick - one"]))

    assert InlineScreen.lines(screen) == ["+ Pick - one", "", "", "", "", ""]
  end

  test "a frame is redrawn in the same rows wherever the cursor was left in it" do
    {screen, _region} =
      {InlineScreen.new(6, 1), %Region{}}
      |> draw(frame(["? Name > ad", "  x Too short"], {0, 11}))
      |> draw(frame(["? Name > ada"], {0, 12}))

    assert InlineScreen.lines(screen) == ["", "? Name > ada", "", "", "", ""]
    assert InlineScreen.cursor(screen) == {1, 12}
  end

  test "a frame that scrolls the terminal is still redrawn over itself" do
    {screen, region} =
      {InlineScreen.new(4, 3), %Region{}}
      |> draw(frame(["? Pick", "> one", "  two"]))
      |> draw(frame(["? Pick", "  one", "> two"]))

    assert InlineScreen.lines(screen) == ["", "? Pick", "  one", "> two"]

    {bytes, _region} = Region.leave(region)
    screen = InlineScreen.write(screen, bytes)

    assert InlineScreen.lines(screen) == ["? Pick", "  one", "> two", ""]
    assert InlineScreen.cursor(screen) == {3, 0}
  end

  test "lines wider than the terminal are cut one column short of its width" do
    {screen, _region} = draw({InlineScreen.new(3), %Region{}}, frame(["0123456789"]), {6, 24})

    assert InlineScreen.lines(screen) == ["01234", "", ""]
  end

  test "clear erases the frame and leaves the cursor on its first row" do
    {screen, region} =
      draw({InlineScreen.new(5, 1), %Region{}}, frame(["working", "second"], {0, 7}))

    {bytes, region} = Region.clear(region)
    screen = InlineScreen.write(screen, bytes)

    assert InlineScreen.lines(screen) == ["", "", "", "", ""]
    assert InlineScreen.cursor(screen) == {1, 0}
    assert region == %Region{}
  end
end
