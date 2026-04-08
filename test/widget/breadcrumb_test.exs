defmodule Drafter.Widget.BreadcrumbTest do
  use ExUnit.Case

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Breadcrumb

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "mounts with tuple items" do
      state = Breadcrumb.mount(%{items: [{"Home", :home}, {"Products", :products}]})
      assert state.items == [{"Home", :home}, {"Products", :products}]
      assert state.separator == " › "
      assert state.active == true
      assert state.focused_index == 0
    end

    test "mounts with plain string items" do
      state = Breadcrumb.mount(%{items: ["Home", "Products"]})
      assert state.items == [{"Home", "Home"}, {"Products", "Products"}]
    end

    test "mounts with custom separator" do
      state = Breadcrumb.mount(%{items: ["A", "B"], separator: " / "})
      assert state.separator == " / "
    end

    test "mounts with empty items" do
      state = Breadcrumb.mount(%{items: []})
      assert state.items == []
    end

    test "mounts with active disabled" do
      state = Breadcrumb.mount(%{items: ["A"], active: false})
      assert state.active == false
    end

    test "defaults to not focused" do
      state = Breadcrumb.mount(%{items: ["A"]})
      assert state.focused == false
    end
  end

  describe "render/2" do
    test "renders single item" do
      state = Breadcrumb.mount(%{items: [{"Home", :home}]})
      rect = %{width: 20, height: 1}
      strips = Breadcrumb.render(state, rect)
      assert length(strips) == 1
      text = strip_text(hd(strips))
      assert String.contains?(text, "Home")
    end

    test "renders multiple items with separator" do
      state = Breadcrumb.mount(%{items: [{"Home", :home}, {"Products", :products}]})
      rect = %{width: 40, height: 1}
      strips = Breadcrumb.render(state, rect)
      text = strip_text(hd(strips))
      assert String.contains?(text, "Home")
      assert String.contains?(text, " › ")
      assert String.contains?(text, "Products")
    end

    test "renders with custom separator" do
      state = Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}], separator: " / "})
      rect = %{width: 40, height: 1}
      strips = Breadcrumb.render(state, rect)
      text = strip_text(hd(strips))
      assert String.contains?(text, " / ")
    end

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

    test "renders empty items without error" do
      state = Breadcrumb.mount(%{items: []})
      rect = %{width: 20, height: 1}
      strips = Breadcrumb.render(state, rect)
      assert length(strips) == 1
    end
  end

  describe "keyboard navigation" do
    test "right arrow increases focused_index" do
      state = Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}, {"C", :c}]})
      {:ok, new_state} = Breadcrumb.handle_key(:right, state)
      assert new_state.focused_index == 1
    end

    test "left arrow decreases focused_index" do
      state = %{Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}]}) | focused_index: 1}
      {:ok, new_state} = Breadcrumb.handle_key(:left, state)
      assert new_state.focused_index == 0
    end

    test "left arrow does not go below zero" do
      state = Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}]})
      {:ok, new_state} = Breadcrumb.handle_key(:left, state)
      assert new_state.focused_index == 0
    end

    test "right arrow does not exceed last index" do
      state = %{Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}]}) | focused_index: 1}
      {:ok, new_state} = Breadcrumb.handle_key(:right, state)
      assert new_state.focused_index == 1
    end

    test "enter triggers selection at focused index" do
      state = %{Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}]}) | focused_index: 1}
      {:ok, new_state, _actions} = Breadcrumb.handle_key(:enter, state)
      assert new_state.focused_index == 1
    end

    test "unhandled keys bubble" do
      state = Breadcrumb.mount(%{items: [{"A", :a}]})
      assert {:bubble, ^state} = Breadcrumb.handle_key(:up, state)
    end
  end

  describe "click handling" do
    test "click on first item selects it" do
      state = Breadcrumb.mount(%{items: [{"Home", :home}, {"Products", :products}]})
      {:ok, new_state, _actions} = Breadcrumb.handle_mouse_up(2, 0, state)
      assert new_state.focused_index == 0
    end

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

  describe "update/2" do
    test "updates items" do
      state = Breadcrumb.mount(%{items: [{"A", :a}]})
      new_state = Breadcrumb.update(%{items: [{"B", :b}, {"C", :c}]}, state)
      assert new_state.items == [{"B", :b}, {"C", :c}]
    end

    test "updates separator" do
      state = Breadcrumb.mount(%{items: [{"A", :a}]})
      new_state = Breadcrumb.update(%{separator: " -> "}, state)
      assert new_state.separator == " -> "
    end

    test "clamps focused_index when items shrink" do
      state = %{Breadcrumb.mount(%{items: [{"A", :a}, {"B", :b}, {"C", :c}]}) | focused_index: 2}
      new_state = Breadcrumb.update(%{items: [{"X", :x}]}, state)
      assert new_state.focused_index == 0
    end
  end

  describe "from_component_opts/2" do
    test "builds props from opts" do
      props = Breadcrumb.from_component_opts([{"Home", :home}], separator: " / ", active: false)
      assert props.items == [{"Home", :home}]
      assert props.separator == " / "
      assert props.active == false
    end
  end

  describe "component_tag/0" do
    test "returns :breadcrumb" do
      assert Breadcrumb.component_tag() == :breadcrumb
    end
  end

  describe "preferred_height/2" do
    test "always returns 1" do
      assert Breadcrumb.preferred_height([], []) == 1
    end
  end

  defp strip_text(strip) do
    Enum.map_join(strip.segments, & &1.text)
  end
end
