defmodule Drafter.Widget.CalendarTest do
  use ExUnit.Case

  alias Drafter.Widget.Calendar

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "handle_key/2 navigation" do
    test "up arrow moves cursor back one week" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, new_state} = Calendar.handle_key(:up, state)
      assert new_state.cursor_date == ~D[2026-04-03]
    end
  end

  describe "min_date / max_date constraints" do
    test "cannot navigate past max_date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-30], max_date: ~D[2026-04-30]})
      {:ok, new_state} = Calendar.handle_key(:right, state)
      assert new_state.cursor_date == ~D[2026-04-30]
    end

    test "navigation within bounds succeeds" do
      state =
        Calendar.mount(%{
          selected_date: ~D[2026-04-15],
          min_date: ~D[2026-04-01],
          max_date: ~D[2026-04-30]
        })

      {:ok, new_state} = Calendar.handle_key(:right, state)
      assert new_state.cursor_date == ~D[2026-04-16]
    end
  end

  describe "date selection" do
    test "enter selects the cursor date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, moved} = Calendar.handle_key(:right, state)
      {:ok, selected} = Calendar.handle_key(:enter, moved)
      assert selected.selected_date == ~D[2026-04-11]
    end

    test "space selects the cursor date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, selected} = Calendar.handle_key(:" ", state)
      assert selected.selected_date == ~D[2026-04-10]
    end

    test "on_select callback is invoked" do
      test_pid = self()

      state =
        Calendar.mount(%{
          selected_date: ~D[2026-04-10],
          on_select: fn date -> send(test_pid, {:selected, date}) end
        })

      {:ok, _new_state} = Calendar.handle_key(:enter, state)
      assert_receive {:selected, ~D[2026-04-10]}
    end
  end

  describe "render/2" do
    test "produces 9 strips (title + header + 6 weeks + padding)" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-15]})
      rect = %{width: 28, height: 9}
      strips = Calendar.render(state, rect)
      assert length(strips) == 9
    end
  end

  describe "update/2" do
    test "preserves existing values when not provided" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10], min_date: ~D[2026-01-01]})
      updated = Calendar.update(%{}, state)
      assert updated.selected_date == ~D[2026-04-10]
      assert updated.min_date == ~D[2026-01-01]
    end
  end
end
