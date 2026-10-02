defmodule Drafter.Regression.AuditedBugFixesTest do
  @moduledoc """
  Guards for defects that reached shipped code because nothing covered the mechanism.

  Each test names the line it protects and the edit that would break it again.
  """

  use ExUnit.Case, async: false

  alias Drafter.Clipboard
  alias Drafter.Runtime.FrameClock
  alias Drafter.Widget.Chart
  alias Drafter.Widget.Trait.Scrollable
  alias Drafter.WidgetStripCache

  describe "scrollable" do
    test "home keeps the rest of the trait slice, so the next page_down can still measure" do
      state = %{Scrollable.default_state() | _content_height: 40, _viewport_height: 10}

      {:ok, homed} = Scrollable.handle_event({:key, :home}, state, %{})

      assert homed._content_height == 40,
             "the :home clause dropped the slice; scrollable.ex must return %{trait_state | ...}"

      assert {:ok, paged} = Scrollable.handle_event({:key, :page_down}, homed, %{})
      assert paged._scroll_offset_y == 9
    end
  end

  describe "chart ranges" do
    test "a scatter series is measured on its y values, not its x values" do
      props =
        Chart.from_component_opts([{0, 100}, {1, 200}, {2, 300}],
          chart_type: :scatter,
          width: 20,
          height: 6
        )

      state = Chart.mount(props)

      assert state.max_value > 100,
             "chart.ex extract_values read {x, y} as {value, weight} and returned the x range"
    end

    test "a weighted series is still measured on its values" do
      state =
        Chart.mount(Chart.from_component_opts([{10, 3}, {20, 5}], chart_type: :line, width: 20))

      assert state.min_value < 10 and state.max_value > 20
    end
  end

  describe "frame clock" do
    test "a rate that cannot produce an interval is an argument error, as documented" do
      for spec <- ["0fps", 0, -5, "nonsense"] do
        assert_raise ArgumentError, fn -> FrameClock.interval_for(spec) end
      end
    end

    test "a rate that can is still honoured" do
      assert FrameClock.interval_for("30fps") == 33
      assert FrameClock.interval_for(16) == 16
      assert FrameClock.interval_for(:unlimited) == nil
    end
  end

  describe "clipboard" do
    setup do
      previous = Application.get_env(:drafter, :clipboard)
      on_exit(fn -> Application.put_env(:drafter, :clipboard, previous) end)
      :ok
    end

    test "paste is gated on the paste permission, not the copy permission" do
      Application.put_env(:drafter, :clipboard, copy: false, paste: true)

      assert Clipboard.paste_enabled?()
      refute match?({:error, :disabled}, Clipboard.paste())
    end

    test "paste is still refused when paste itself is off" do
      Application.put_env(:drafter, :clipboard, copy: true, paste: false)

      assert Clipboard.paste() == {:error, :disabled}
    end
  end

  describe "widget strip cache" do
    test "delete clears the visible region too, so a reused id starts unseen" do
      id = :"audited_cache_#{System.unique_integer([:positive])}"

      WidgetStripCache.mark_visible(id, %{x: 0, y: 0, width: 10, height: 4})
      assert WidgetStripCache.visible?(id)

      WidgetStripCache.delete(id)

      refute WidgetStripCache.visible?(id),
             "delete/1 left @visible_table, so the next widget under this id inherits its rect"
    end
  end
end
