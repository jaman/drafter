defmodule Drafter.Widget.OptionListFocusTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.OptionList

  @rect %{width: 24, height: 4}

  defp options do
    [
      OptionList.option("a", "Alpha"),
      OptionList.option("b", "Beta")
    ]
  end

  defp rows(state) do
    state
    |> OptionList.render(@rect)
    |> Enum.map(fn strip -> Enum.map_join(strip.segments, & &1.text) end)
  end

  defp focus(state) do
    {:ok, focused} = OptionList.handle_event({:focus}, state)
    focused
  end

  defp blur(state) do
    {:ok, blurred} = OptionList.handle_event({:blur}, state)
    blurred
  end

  describe "focused state" do
    test "mount leaves the list unfocused" do
      refute OptionList.mount(%{options: options()}).focused
    end

    test "mount reads :focused from props" do
      assert OptionList.mount(%{options: options(), focused: true}).focused
    end

    test "focus and blur flip the field" do
      state = OptionList.mount(%{options: options()})

      assert state |> focus() |> Map.fetch!(:focused)
      refute state |> focus() |> blur() |> Map.fetch!(:focused)
    end
  end

  describe "highlight rendering" do
    test "an unfocused list draws no highlight marker" do
      assert [first, second] = rows(OptionList.mount(%{options: options()}))
      assert String.starts_with?(first, "  Alpha")
      assert String.starts_with?(second, "  Beta")
    end

    test "a focused list marks its highlighted option" do
      assert [first, second] = rows(focus(OptionList.mount(%{options: options()})))
      assert String.starts_with?(first, "▶ Alpha")
      assert String.starts_with?(second, "  Beta")
    end

    test "the marker follows the highlight while focused" do
      state = focus(OptionList.mount(%{options: options()}))
      {:ok, moved} = OptionList.handle_key(:down, state)

      assert [first, second] = rows(moved)
      assert String.starts_with?(first, "  Alpha")
      assert String.starts_with?(second, "▶ Beta")
    end

    test "blurring hides the marker without losing the highlight" do
      state = focus(OptionList.mount(%{options: options()}))
      {:ok, moved} = OptionList.handle_key(:down, state)
      blurred = blur(moved)

      assert blurred.highlighted_index == 1
      assert [first, second] = rows(blurred)
      assert String.starts_with?(first, "  Alpha")
      assert String.starts_with?(second, "  Beta")
    end

    test "a re-render keeps the widget focused" do
      state = focus(OptionList.mount(%{options: options()}))
      props = OptionList.from_component_opts(["a", "b"], [])

      assert props
             |> OptionList.update_props_from_mount(state, [])
             |> OptionList.update(state)
             |> Map.fetch!(:focused)
    end
  end
end
