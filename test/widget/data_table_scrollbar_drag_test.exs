defmodule Drafter.Widget.DataTableScrollbarDragTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.DataTable
  alias Drafter.WidgetHierarchy.Mouse

  @columns [%{key: :name, label: "Name"}, %{key: :value, label: "Value"}]

  defp table do
    rows = for i <- 1..200, do: %{name: "row-#{i}", value: i}

    DataTable.mount(%{
      columns: @columns,
      data: rows,
      width: 40,
      height: 12,
      show_scrollbars: true
    })
  end

  defp scrollbar_x(state), do: state.width - 1
  defp first_data_row(state), do: DataTable.get_data_start_y(state)

  describe "drag lifecycle" do
    test "pressing the scrollbar starts a drag" do
      state = table()
      {:ok, pressed, _} = DataTable.handle_press(scrollbar_x(state), first_data_row(state), state)
      assert pressed.drag.dragging_scrollbar
    end

    test "releasing ends the drag" do
      state = table()
      {:ok, pressed, _} = DataTable.handle_press(scrollbar_x(state), first_data_row(state), state)

      {:ok, released} =
        DataTable.handle_mouse_up(scrollbar_x(state), first_data_row(state), pressed)

      refute released.drag.dragging_scrollbar
    end

    test "a press elsewhere does not start a scrollbar drag" do
      state = table()
      assert {:bubble, unchanged} = DataTable.handle_press(2, first_data_row(state), state)
      refute unchanged.drag.dragging_scrollbar
    end

    test "releasing on the scrollbar does not also select a row" do
      state = table()
      {:ok, pressed, _} = DataTable.handle_press(scrollbar_x(state), first_data_row(state), state)
      selected_before = {pressed.selected_indices, pressed.highlighted_index}

      {:ok, released} =
        DataTable.handle_mouse_up(scrollbar_x(state), first_data_row(state), pressed)

      assert {released.selected_indices, released.highlighted_index} == selected_before
    end

    test "a click on the scrollbar does not leave the table stuck in drag mode" do
      state = table()
      x = scrollbar_x(state)
      y = first_data_row(state)

      {:ok, pressed, _} = DataTable.handle_press(x, y, state)
      {:ok, released} = DataTable.handle_mouse_up(x, y, pressed)

      assert {:noreply, ^released} = DataTable.handle_drag(x, y + 5, released)
    end
  end

  describe "dragging scrolls" do
    test "dragging down the bar scrolls forward" do
      state = table()
      x = scrollbar_x(state)
      top = first_data_row(state)

      {:ok, pressed, _} = DataTable.handle_press(x, top, state)
      {:ok, dragged, _} = DataTable.handle_drag(x, top + 6, pressed)

      assert dragged.scroll.offset > pressed.scroll.offset
    end

    test "dragging back up scrolls back to the start" do
      state = table()
      x = scrollbar_x(state)
      top = first_data_row(state)

      {:ok, pressed, _} = DataTable.handle_press(x, top, state)
      {:ok, down, _} = DataTable.handle_drag(x, top + 8, pressed)
      {:ok, up, _} = DataTable.handle_drag(x, top, down)

      assert up.scroll.offset == 0
    end

    test "dragging past the bottom clamps rather than overscrolling" do
      state = table()
      x = scrollbar_x(state)
      top = first_data_row(state)

      {:ok, pressed, _} = DataTable.handle_press(x, top, state)
      {:ok, dragged, _} = DataTable.handle_drag(x, top + 500, pressed)

      max_offset = length(state.data) - DataTable.get_data_height(state)
      assert dragged.scroll.offset <= max_offset
    end
  end

  describe "pointer capture" do
    test "a table dragging its scrollbar captures the pointer" do
      state = table()
      {:ok, pressed, _} = DataTable.handle_press(scrollbar_x(state), first_data_row(state), state)

      hierarchy = Mouse.maybe_start_drag_capture(%{drag_capture_widget: nil}, :table, pressed)
      assert hierarchy.drag_capture_widget == :table
    end

    test "an idle table does not capture the pointer" do
      hierarchy = Mouse.maybe_start_drag_capture(%{drag_capture_widget: nil}, :table, table())
      assert hierarchy.drag_capture_widget == nil
    end

    test "a widget using flat drag fields still captures" do
      hierarchy =
        Mouse.maybe_start_drag_capture(%{drag_capture_widget: nil}, :w, %{dragging: true})

      assert hierarchy.drag_capture_widget == :w
    end
  end
end
