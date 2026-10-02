defmodule Drafter.Widget.BreadcrumbTest do
  use ExUnit.Case

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Breadcrumb

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "render/2" do
    test "pads to full width" do
      state = Breadcrumb.mount(%{items: [{"Hi", :hi}]})
      rect = %{width: 20, height: 1}
      [strip] = Breadcrumb.render(state, rect)
      assert Strip.width(strip) == 20
    end

    test "truncates from left with ellipsis when too wide" do
      items = Enum.map(1..10, fn n -> {"Item#{n}", :"item_#{n}"} end)
      state = Breadcrumb.mount(%{items: items})
      rect = %{width: 30, height: 1}
      [strip] = Breadcrumb.render(state, rect)
      text = strip_text(strip)
      assert String.starts_with?(text, "...")
    end
  end

  describe "keyboard navigation" do
    test "right arrow does not exceed last index" do
      state = %{Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}]}) | focused_index: 1}
      {:ok, new_state} = Breadcrumb.handle_key(:right, state)
      assert new_state.focused_index == 1
    end
  end

  describe "click handling" do
    test "click on second item selects it" do
      state = Breadcrumb.mount(%{items: [{"Home", :home}, {"Products", :products}]})
      {:ok, new_state, _actions} = Breadcrumb.handle_mouse_up(9, 0, state)
      assert new_state.focused_index == 1
    end

    test "click outside items does nothing" do
      state = Breadcrumb.mount(%{items: [{"Hi", :hi}]})
      {:ok, new_state} = Breadcrumb.handle_mouse_up(50, 0, state)
      assert new_state.focused_index == 0
    end
  end

  defp strip_text(strip) do
    Enum.map_join(strip.segments, & &1.text)
  end
end
