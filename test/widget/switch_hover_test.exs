defmodule Drafter.Widget.SwitchHoverTest do
  @moduledoc """
  A hovered switch must look different, not merely record that it is hovered.
  """

  use ExUnit.Case, async: true

  alias Drafter.Widget.Switch

  defp rect, do: %{x: 0, y: 0, width: 20, height: 1}

  defp thumb_and_track(state) do
    state
    |> Switch.render(rect())
    |> Enum.flat_map(& &1.segments)
    |> Enum.filter(&switch_graphic?/1)
    |> Enum.map(& &1.style)
  end

  defp switch_graphic?(%{text: text, style: style}) do
    String.contains?(text, "█") or (String.trim(text) == "" and Map.get(style, :bold) != true)
  end

  defp styles(state), do: thumb_and_track(state)

  describe "hover" do
    test "the router's hover event sets the flag" do
      assert {:ok, %{hovered: true}} = Switch.handle_event(:hover, Switch.mount(%{}))
    end

    test "unhover clears it" do
      hovered = %{Switch.mount(%{}) | hovered: true}

      assert {:ok, %{hovered: false}} = Switch.handle_event(:unhover, hovered)
    end

    test "hovering changes what is drawn" do
      resting = Switch.mount(%{label: "Toggle"})
      hovered = %{resting | hovered: true}

      refute styles(resting) == styles(hovered),
             "a hovered switch renders identically to a resting one"
    end

    test "hovering changes the track, not only the thumb" do
      resting = Switch.mount(%{label: "Toggle"})
      hovered = %{resting | hovered: true}

      resting_backgrounds = resting |> styles() |> Enum.map(&Map.get(&1, :bg)) |> Enum.uniq()
      hovered_backgrounds = hovered |> styles() |> Enum.map(&Map.get(&1, :bg)) |> Enum.uniq()

      refute resting_backgrounds == hovered_backgrounds
    end

    test "hover styling applies whether the switch is on or off" do
      for switch_state <- [:on, :off] do
        resting = %{Switch.mount(%{label: "T"}) | state: switch_state}
        hovered = %{resting | hovered: true}

        refute styles(resting) == styles(hovered),
               "no hover change while #{switch_state}"
      end
    end

    test "a focused switch is also distinguishable from a resting one" do
      resting = Switch.mount(%{label: "Toggle"})
      focused = %{resting | focused: true}

      refute styles(resting) == styles(focused),
             "a focused switch renders identically to a resting one"
    end
  end
end
