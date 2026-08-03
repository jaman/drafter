defmodule Drafter.Widget.RadioSetColumnsTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.RadioSet

  @themes ~w(
    catppuccin-mocha classic dracula gruvbox-dark gruvbox-light monokai
    nord retro solarized-dark solarized-light textual-dark textual-light
  )

  defp two_column_set do
    RadioSet.mount(%{
      options: @themes,
      selected: "textual-dark",
      cols: 2,
      width: 100,
      on_change: fn _ -> :ok end
    })
  end

  defp click(state, x, y) do
    {:ok, new_state} = RadioSet.handle_event({:mouse, %{type: :mouse_up, x: x, y: y}}, state)
    Enum.at(new_state.options, new_state.selected_index).id
  end

  describe "single column" do
    test "row maps directly to option" do
      state = RadioSet.mount(%{options: @themes, cols: 1, width: 40})
      assert click(state, 2, 0) == "catppuccin-mocha"
      assert click(state, 2, 3) == "gruvbox-dark"
      assert click(state, 2, 11) == "textual-light"
    end
  end

  describe "two columns" do
    test "the left column selects the first half, top to bottom" do
      state = two_column_set()
      assert click(state, 5, 0) == "catppuccin-mocha"
      assert click(state, 5, 3) == "gruvbox-dark"
      assert click(state, 5, 5) == "monokai"
    end

    test "the right column selects the second half, top to bottom" do
      state = two_column_set()
      assert click(state, 60, 0) == "nord"
      assert click(state, 60, 3) == "solarized-light"
      assert click(state, 60, 5) == "textual-light"
    end

    test "a click at the far right edge stays in the last column" do
      state = two_column_set()
      assert click(state, 99, 1) == "retro"
    end

    test "a click past the last row of a column selects nothing" do
      state = two_column_set()

      assert {:noreply, _} =
               RadioSet.handle_event({:mouse, %{type: :mouse_up, x: 5, y: 6}}, state)
    end
  end

  describe "three columns" do
    test "each column selects its own third" do
      state =
        RadioSet.mount(%{options: @themes, cols: 3, width: 90, on_change: fn _ -> :ok end})

      assert click(state, 5, 0) == "catppuccin-mocha"
      assert click(state, 35, 0) == "gruvbox-light"
      assert click(state, 65, 0) == "solarized-dark"
      assert click(state, 65, 3) == "textual-light"
    end
  end

  describe "uneven split" do
    test "a short final column does not select out of range" do
      state =
        RadioSet.mount(%{options: ~w(a b c d e), cols: 2, width: 40, on_change: fn _ -> :ok end})

      assert click(state, 5, 0) == "a"
      assert click(state, 5, 2) == "c"
      assert click(state, 25, 0) == "d"
      assert click(state, 25, 1) == "e"

      assert {:noreply, _} =
               RadioSet.handle_event({:mouse, %{type: :mouse_up, x: 25, y: 2}}, state)
    end
  end

  test "the change callback fires with the clicked option" do
    owner = self()

    state =
      RadioSet.mount(%{
        options: @themes,
        cols: 2,
        width: 100,
        on_change: fn id -> send(owner, {:changed, id}) end
      })

    RadioSet.handle_event({:mouse, %{type: :mouse_up, x: 60, y: 3}}, state)
    assert_received {:changed, "solarized-light"}
  end

  test "every option is reachable by exactly one click position" do
    state = two_column_set()

    reached =
      for col <- 0..1, row <- 0..5 do
        RadioSet.option_index_at(state, col * 50 + 5, row)
      end

    assert Enum.sort(reached) == Enum.to_list(0..11)
  end
end
