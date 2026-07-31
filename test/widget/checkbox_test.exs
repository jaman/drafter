defmodule Drafter.Widget.CheckboxTest do
  use ExUnit.Case
  alias Drafter.ComponentRenderer
  alias Drafter.Theme
  alias Drafter.Widget.Checkbox

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "defaults checked to false" do
      state = Checkbox.mount(%{})
      assert state.checked == false
    end

    test "mounts with checked: true" do
      state = Checkbox.mount(%{checked: true})
      assert state.checked == true
    end

    test "mounts with label" do
      state = Checkbox.mount(%{label: "Enable feature"})
      assert state.label == "Enable feature"
    end

    test "defaults focused to false" do
      state = Checkbox.mount(%{})
      assert state.focused == false
    end
  end

  describe "handle_event/2" do
    test "space toggles checked from false to true" do
      state = Checkbox.mount(%{checked: false, focused: true})
      assert {:ok, new_state} = Checkbox.handle_event({:key, :" "}, state)
      assert new_state.checked == true
    end

    test "enter toggles checked from true to false" do
      state = Checkbox.mount(%{checked: true, focused: true})
      assert {:ok, new_state} = Checkbox.handle_event({:key, :enter}, state)
      assert new_state.checked == false
    end

    test "click toggles checked" do
      state = Checkbox.mount(%{checked: false})
      assert {:ok, new_state} = Checkbox.handle_event({:mouse, %{type: :mouse_up}}, state)
      assert new_state.checked == true
    end

    test "focus sets focused to true" do
      state = Checkbox.mount(%{})
      assert {:ok, new_state} = Checkbox.handle_event({:focus}, state)
      assert new_state.focused == true
    end

    test "blur sets focused to false" do
      state = Checkbox.mount(%{focused: true})
      assert {:ok, new_state} = Checkbox.handle_event({:blur}, state)
      assert new_state.focused == false
    end

    test "unhandled events return noreply" do
      state = Checkbox.mount(%{})
      assert {:noreply, ^state} = Checkbox.handle_event(:something_else, state)
    end
  end

  describe "update/2" do
    test "syncs checked state" do
      state = Checkbox.mount(%{checked: false})
      new_state = Checkbox.update(%{checked: true}, state)
      assert new_state.checked == true
    end

    test "syncs on_change callback" do
      state = Checkbox.mount(%{})
      cb = fn _ -> :ok end
      new_state = Checkbox.update(%{on_change: cb}, state)
      assert new_state.on_change == cb
    end

    test "preserves checked when not in props" do
      state = Checkbox.mount(%{checked: true})
      new_state = Checkbox.update(%{}, state)
      assert new_state.checked == true
    end
  end

  describe "component_renderer fix: checked: opt at mount" do
    test "checkbox with checked: true produces checked widget at mount" do
      rect = %{x: 0, y: 0, width: 20, height: 1}
      theme = Theme.dark_theme()
      tree = {:layout, :vertical, [{:checkbox, "Option", [id: :cb1, checked: true]}], []}

      hierarchy = ComponentRenderer.render_tree(tree, rect, theme, %{})
      widget_state = Drafter.WidgetHierarchy.get_widget_state(hierarchy, :cb1)

      assert widget_state.checked == true
    end

    test "checkbox with checked: false produces unchecked widget at mount" do
      rect = %{x: 0, y: 0, width: 20, height: 1}
      theme = Theme.dark_theme()
      tree = {:layout, :vertical, [{:checkbox, "Option", [id: :cb2, checked: false]}], []}

      hierarchy = ComponentRenderer.render_tree(tree, rect, theme, %{})
      widget_state = Drafter.WidgetHierarchy.get_widget_state(hierarchy, :cb2)

      assert widget_state.checked == false
    end
  end

  describe "re-render prop update behavior" do
    test "re-rendering without bind: preserves internal checked state" do
      rect = %{x: 0, y: 0, width: 20, height: 1}
      theme = Theme.dark_theme()

      tree_true = {:layout, :vertical, [{:checkbox, "Option", [id: :cb3, checked: true]}], []}
      hierarchy = ComponentRenderer.render_tree(tree_true, rect, theme, %{})

      tree_false = {:layout, :vertical, [{:checkbox, "Option", [id: :cb3, checked: false]}], []}
      hierarchy2 = ComponentRenderer.render_tree(tree_false, rect, theme, %{}, hierarchy)

      widget_state = Drafter.WidgetHierarchy.get_widget_state(hierarchy2, :cb3)
      assert widget_state.checked == true
    end

    test "re-rendering with bind: syncs checked from app state" do
      rect = %{x: 0, y: 0, width: 20, height: 1}
      theme = Theme.dark_theme()

      tree_true = {:layout, :vertical, [{:checkbox, "Option", [id: :cb4, bind: :flag]}], []}
      hierarchy = ComponentRenderer.render_tree(tree_true, rect, theme, %{flag: true})

      hierarchy2 =
        ComponentRenderer.render_tree(tree_true, rect, theme, %{flag: false}, hierarchy)

      widget_state = Drafter.WidgetHierarchy.get_widget_state(hierarchy2, :cb4)
      assert widget_state.checked == false
    end
  end
end
