defmodule Drafter.Regression.RepeatClickTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.Button
  alias Drafter.WidgetHierarchy

  @rect %{x: 0, y: 0, width: 9, height: 3}

  setup do
    {:ok, theme_manager} = start_manager(Drafter.ThemeManager)
    {:ok, skin_manager} = start_manager(Drafter.SkinManager)
    Process.put(:drafter_theme_manager, theme_manager)
    Process.put(:drafter_skin_manager, skin_manager)
    :ok
  end

  defp start_manager(module) do
    case module.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  defp hierarchy_with_button do
    Drafter.WidgetStripCache.create()
    owner = self()

    props = Button.mount(%{text: "9", on_click: fn -> send(owner, :clicked) end})

    WidgetHierarchy.new()
    |> WidgetHierarchy.add_widget(:btn_9, Button, Map.from_struct(props), nil, @rect)
  end

  defp click(hierarchy) do
    {h, _actions, consumed} =
      WidgetHierarchy.handle_event_consumed(
        hierarchy,
        {:mouse, %{type: :mouse_up, x: 2, y: 1, mods: []}}
      )

    {h, consumed}
  end

  defp clicks_received(acc \\ 0) do
    receive do
      :clicked -> clicks_received(acc + 1)
    after
      50 -> acc
    end
  end

  test "a single click fires the callback once and reports consumed" do
    {_h, consumed} = click(hierarchy_with_button())
    assert consumed
    assert clicks_received() == 1
  end

  test "a rapid second click is still reported consumed" do
    hierarchy = hierarchy_with_button()
    {hierarchy, first} = click(hierarchy)
    {_hierarchy, second} = click(hierarchy)

    assert first, "first click should be consumed"
    assert second, "a repeat click inside the active-effect window must also be consumed"
  end

  test "two rapid clicks fire the callback exactly twice" do
    hierarchy = hierarchy_with_button()
    {hierarchy, _} = click(hierarchy)
    {_hierarchy, _} = click(hierarchy)

    assert clicks_received() == 2
  end

  test "a click on a disabled button is not reported consumed" do
    Drafter.WidgetStripCache.create()
    owner = self()
    props = Button.mount(%{text: "9", on_click: fn -> send(owner, :clicked) end, disabled: true})

    hierarchy =
      WidgetHierarchy.new()
      |> WidgetHierarchy.add_widget(:btn_off, Button, Map.from_struct(props), nil, @rect)

    {_h, _consumed} = click(hierarchy)
    assert clicks_received() == 0
  end
end
