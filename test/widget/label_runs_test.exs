defmodule Drafter.Widget.LabelRunsTest do
  use ExUnit.Case
  alias Drafter.Widget.Label
  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  test "a label given runs draws them as one line of segments, each in its own style" do
    state =
      Label.mount(%{text: [{"ab", %{fg: {255, 0, 0}}}, {"cd", %{fg: {0, 0, 255}, bold: true}}]})

    assert state.text == "abcd"

    [strip] = Label.render(state, %{x: 0, y: 0, width: 6, height: 1})
    assert Enum.map(strip.segments, & &1.text) == ["ab", "cd", "  "]
    assert Enum.at(strip.segments, 0).style[:fg] == {255, 0, 0}
    assert Enum.at(strip.segments, 1).style[:fg] == {0, 0, 255}
    assert Enum.at(strip.segments, 1).style[:bold] == true
  end

  test "runs wider than the rect are cropped, and update replaces them" do
    state = Label.mount(%{text: [{"abcdef", %{}}]})
    [strip] = Label.render(state, %{x: 0, y: 0, width: 3, height: 1})
    assert Enum.map_join(strip.segments, & &1.text) == "abc"

    updated = Label.update(%{text: [{"x", %{}}, {"y", %{}}]}, state)
    assert updated.text == "xy"
    [strip] = Label.render(updated, %{x: 0, y: 0, width: 2, height: 1})
    assert Enum.map(strip.segments, & &1.text) == ["x", "y"]

    plain = Label.update(%{text: "plain"}, updated)
    [strip] = Label.render(plain, %{x: 0, y: 0, width: 5, height: 1})
    assert Enum.map(strip.segments, & &1.text) == ["plain"]
  end
end
