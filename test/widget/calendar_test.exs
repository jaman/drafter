defmodule Drafter.Widget.CalendarTest do
  use ExUnit.Case

  alias Drafter.Widget.Calendar

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "defaults cursor to today when no selected_date" do
      state = Calendar.mount(%{})
      assert state.cursor_date == Date.utc_today()
      assert state.selected_date == nil
    end

    test "uses selected_date as cursor when provided" do
      date = ~D[2026-03-15]
      state = Calendar.mount(%{selected_date: date})
      assert state.cursor_date == date
      assert state.selected_date == date
    end

    test "sets view_date to beginning of cursor month" do
      state = Calendar.mount(%{selected_date: ~D[2026-07-20]})
      assert state.view_date == ~D[2026-07-01]
    end

    test "stores min_date and max_date" do
      state = Calendar.mount(%{min_date: ~D[2026-01-01], max_date: ~D[2026-12-31]})
      assert state.min_date == ~D[2026-01-01]
      assert state.max_date == ~D[2026-12-31]
    end

    test "defaults style and classes" do
      state = Calendar.mount(%{})
      assert state.style == %{}
      assert state.classes == []
    end
  end

  describe "handle_key/2 navigation" do
    test "right arrow moves cursor forward one day" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, new_state} = Calendar.handle_key(:right, state)
      assert new_state.cursor_date == ~D[2026-04-11]
    end

    test "left arrow moves cursor back one day" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, new_state} = Calendar.handle_key(:left, state)
      assert new_state.cursor_date == ~D[2026-04-09]
    end

    test "down arrow moves cursor forward one week" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, new_state} = Calendar.handle_key(:down, state)
      assert new_state.cursor_date == ~D[2026-04-17]
    end

    test "up arrow moves cursor back one week" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10]})
      {:ok, new_state} = Calendar.handle_key(:up, state)
      assert new_state.cursor_date == ~D[2026-04-03]
    end

    test "navigating past month end updates view_date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-30]})
      {:ok, new_state} = Calendar.handle_key(:right, state)
      assert new_state.cursor_date == ~D[2026-05-01]
      assert new_state.view_date == ~D[2026-05-01]
    end

    test "navigating before month start updates view_date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-01]})
      {:ok, new_state} = Calendar.handle_key(:left, state)
      assert new_state.cursor_date == ~D[2026-03-31]
      assert new_state.view_date == ~D[2026-03-01]
    end

    test "unhandled key bubbles" do
      state = Calendar.mount(%{})
      assert {:bubble, ^state} = Calendar.handle_key(:tab, state)
    end
  end

  describe "min_date / max_date constraints" do
    test "cannot navigate before min_date" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-01], min_date: ~D[2026-04-01]})
      {:ok, new_state} = Calendar.handle_key(:left, state)
      assert new_state.cursor_date == ~D[2026-04-01]
    end

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

    test "title contains month name and year" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-15]})
      rect = %{width: 28, height: 9}
      [title_strip | _rest] = Calendar.render(state, rect)
      title_text = strip_text(title_strip)
      assert title_text =~ "April 2026"
    end

    test "header contains weekday abbreviations" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-15]})
      rect = %{width: 28, height: 9}
      [_title, header | _rest] = Calendar.render(state, rect)
      header_text = strip_text(header)
      assert header_text =~ "Su"
      assert header_text =~ "Mo"
      assert header_text =~ "Sa"
    end

    test "week rows contain day numbers" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-15]})
      rect = %{width: 28, height: 9}
      strips = Calendar.render(state, rect)
      all_text = Enum.map_join(strips, "\n", &strip_text/1)
      assert all_text =~ "15"
      assert all_text =~ " 1"
    end
  end

  describe "update/2" do
    test "updates selected_date" do
      state = Calendar.mount(%{})
      updated = Calendar.update(%{selected_date: ~D[2026-06-01]}, state)
      assert updated.selected_date == ~D[2026-06-01]
    end

    test "updates min_date and max_date" do
      state = Calendar.mount(%{})
      updated = Calendar.update(%{min_date: ~D[2026-01-01], max_date: ~D[2026-12-31]}, state)
      assert updated.min_date == ~D[2026-01-01]
      assert updated.max_date == ~D[2026-12-31]
    end

    test "preserves existing values when not provided" do
      state = Calendar.mount(%{selected_date: ~D[2026-04-10], min_date: ~D[2026-01-01]})
      updated = Calendar.update(%{}, state)
      assert updated.selected_date == ~D[2026-04-10]
      assert updated.min_date == ~D[2026-01-01]
    end
  end

  describe "component_tag/0" do
    test "returns :calendar" do
      assert Calendar.component_tag() == :calendar
    end
  end

  describe "preferred_height/2" do
    test "returns 9" do
      assert Calendar.preferred_height(nil, []) == 9
    end
  end

  defp strip_text(strip) do
    strip.segments
    |> Enum.map_join(fn seg -> seg.text end)
  end
end
