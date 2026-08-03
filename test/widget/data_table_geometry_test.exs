defmodule Drafter.Widget.DataTableGeometryTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.DataTable.Rendering

  alias Drafter.Widget.DataTable
  alias Drafter.Widget.Scrollbar
  alias Drafter.WidgetServer
  alias Drafter.WidgetStripCache

  @columns [%{key: :name, label: "Name"}, %{key: :value, label: "Value"}]

  setup do
    WidgetStripCache.create()

    {:ok, tm} =
      case Drafter.ThemeManager.start_link() do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

    Process.put(:drafter_theme_manager, tm)
    {:ok, session: %{drafter_theme_manager: tm}}
  end

  defp session_ctx, do: %{drafter_theme_manager: Process.get(:drafter_theme_manager)}

  defp props(row_count) do
    %{
      columns: @columns,
      data: for(i <- 1..row_count, do: %{name: "row-#{i}", value: i}),
      width: 40,
      height: 10,
      show_scrollbars: true
    }
  end

  defp mounted_at(rect, row_count) do
    {:ok, pid} =
      WidgetServer.start_link(
        id: :"tbl_#{System.unique_integer([:positive])}",
        module: DataTable,
        props: props(row_count),
        rect: rect,
        session_ctx: session_ctx()
      )

    WidgetServer.get_state(pid)
  end

  test "a table laid out taller than its mount height adopts the real viewport" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 200)

    assert state.viewport_height == 40
    assert state.width == 60
  end

  test "drag maths uses the laid-out height, not the mount height" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 200)
    assert DataTable.get_data_height(state) == 39
  end

  test "the thumb the renderer draws is the thumb the drag maths targets" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 200)
    data_height = DataTable.get_data_height(state)
    total = length(state.data)

    for row <- 0..(data_height - 1) do
      offset = Scrollbar.offset_from_row(row, total, data_height)
      drawn = Scrollbar.thumb_rows(offset, total, data_height)

      assert drawn.first <= row and row <= drawn.last,
             "grabbing row #{row} scrolled to #{offset}, drawing the thumb at #{inspect(drawn)}"
    end
  end

  test "the drawn thumb lands under the pointer that dragged it" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 100)
    data_start_y = DataTable.get_data_start_y(state)
    data_height = DataTable.get_data_height(state)
    total = length(state.data)

    for row <- 0..(data_height - 1) do
      offset = Scrollbar.offset_from_row(row, total, data_height)
      scrolled = put_in(state.scroll.offset, offset)

      thumb =
        Rendering.scrollbar_thumb_rows(
          scrolled,
          data_start_y,
          data_height
        )

      pointer = data_start_y + row

      assert thumb.first <= pointer and pointer <= thumb.last,
             "pointer at strip row #{pointer} scrolled to #{offset}, " <>
               "but the thumb drew at #{inspect(thumb)}"
    end
  end

  test "the thumb is sized in proportion to the visible fraction" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 100)
    data_start_y = DataTable.get_data_start_y(state)
    data_height = DataTable.get_data_height(state)

    thumb =
      Rendering.scrollbar_thumb_rows(state, data_start_y, data_height)

    assert Range.size(thumb) > 1,
           "39 of 100 rows visible should give a multi-row thumb, got #{inspect(thumb)}"
  end

  test "a small drag produces a proportionally small scroll" do
    state = mounted_at(%{x: 0, y: 0, width: 60, height: 40}, 200)
    data_height = DataTable.get_data_height(state)
    total = length(state.data)
    max_offset = total - data_height

    one_row = Scrollbar.offset_from_row(1, total, data_height)

    assert one_row <= div(max_offset, 4),
           "one row of drag jumped #{one_row} of #{max_offset} rows"
  end

  test "resizing the widget keeps geometry in step" do
    {:ok, pid} =
      WidgetServer.start_link(
        id: :"tbl_resize_#{System.unique_integer([:positive])}",
        module: DataTable,
        props: props(200),
        rect: %{x: 0, y: 0, width: 40, height: 10},
        session_ctx: session_ctx()
      )

    WidgetServer.update_rect(pid, %{x: 0, y: 0, width: 80, height: 50})
    state = WidgetServer.get_state(pid)

    assert state.viewport_height == 50
    assert state.width == 80
    assert DataTable.get_data_height(state) == 49
  end
end
