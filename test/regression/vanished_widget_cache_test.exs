defmodule Drafter.Regression.VanishedWidgetCacheTest do
  use ExUnit.Case, async: false

  import Drafter.Test

  defmodule RowsApp do
    use Drafter

    state(%{rows: 8})

    keybinding :d, "fewer" do
      {:ok, %{state | rows: 2}}
    end

    def render(state) do
      vertical([label("header") | for(row <- 1..state.rows, do: label("row #{row}"))])
    end
  end

  defp cached_widget_count(app_pid) do
    {:dictionary, dictionary} = Process.info(app_pid, :dictionary)

    {map_size(dictionary[:render_cache_widget_bounds]),
     map_size(dictionary[:render_cache_widget_rowkeys])}
  end

  test "the render cache keeps no entry for a widget that left the screen" do
    ctx = start_headless(RowsApp, %{}, size: {40, 12})
    on_exit(fn -> stop(ctx) end)

    assert cached_widget_count(ctx.app_pid) == {9, 9}

    send_key(ctx, :d)
    get_state(ctx)

    assert cached_widget_count(ctx.app_pid) == {3, 3}
  end
end
