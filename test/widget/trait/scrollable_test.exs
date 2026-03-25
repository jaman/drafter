defmodule Drafter.Widget.Trait.ScrollableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Scrollable

  describe "metadata" do
    test "name is :scrollable" do
      assert :scrollable = Scrollable.name()
    end

    test "no dependencies" do
      assert [] = Scrollable.dependencies()
    end

    test "handles scroll and keyboard" do
      handles = Scrollable.handles()
      assert :scroll in handles
      assert :keyboard in handles
    end

    test "is layout static" do
      assert Scrollable.layout_static?()
    end
  end

  describe "default_state/0" do
    test "initializes scroll offsets to zero" do
      state = Scrollable.default_state()
      assert state._scroll_offset_y == 0
      assert state._scroll_offset_x == 0
    end

    test "initializes dimensions to zero" do
      state = Scrollable.default_state()
      assert state._content_height == 0
      assert state._viewport_height == 0
    end
  end

  describe "handle_event/3 scroll events" do
    test "scroll up decreases offset" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 5}
      event = {:mouse, %{type: :scroll, direction: :up}}
      {:ok, new_state} = Scrollable.handle_event(event, state, %{})
      assert new_state._scroll_offset_y == 4
    end

    test "scroll up does not go below zero" do
      state = Scrollable.default_state()
      event = {:mouse, %{type: :scroll, direction: :up}}
      {:ok, new_state} = Scrollable.handle_event(event, state, %{})
      assert new_state._scroll_offset_y == 0
    end

    test "scroll down increases offset" do
      state = %{Scrollable.default_state() | _content_height: 100, _viewport_height: 20}
      event = {:mouse, %{type: :scroll, direction: :down}}
      {:ok, new_state} = Scrollable.handle_event(event, state, %{})
      assert new_state._scroll_offset_y == 1
    end

    test "scroll down does not exceed max offset" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 80, _content_height: 100, _viewport_height: 20}
      event = {:mouse, %{type: :scroll, direction: :down}}
      {:ok, new_state} = Scrollable.handle_event(event, state, %{})
      assert new_state._scroll_offset_y == 80
    end
  end

  describe "handle_event/3 keyboard events" do
    test "arrow up scrolls up" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 5}
      {:ok, new_state} = Scrollable.handle_event({:key, :up}, state, %{})
      assert new_state._scroll_offset_y == 4
    end

    test "arrow down scrolls down" do
      state = %{Scrollable.default_state() | _content_height: 100, _viewport_height: 20}
      {:ok, new_state} = Scrollable.handle_event({:key, :down}, state, %{})
      assert new_state._scroll_offset_y == 1
    end

    test "page_up jumps by viewport height minus one" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 30, _viewport_height: 20}
      {:ok, new_state} = Scrollable.handle_event({:key, :page_up}, state, %{})
      assert new_state._scroll_offset_y == 11
    end

    test "page_down jumps by viewport height minus one" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 0, _content_height: 100, _viewport_height: 20}
      {:ok, new_state} = Scrollable.handle_event({:key, :page_down}, state, %{})
      assert new_state._scroll_offset_y == 19
    end

    test "home scrolls to top" do
      state = %{Scrollable.default_state() | _scroll_offset_y: 50}
      {:ok, new_state} = Scrollable.handle_event({:key, :home}, state, %{})
      assert new_state._scroll_offset_y == 0
    end

    test "end scrolls to bottom" do
      state = %{Scrollable.default_state() | _content_height: 100, _viewport_height: 20}
      {:ok, new_state} = Scrollable.handle_event({:key, :end}, state, %{})
      assert new_state._scroll_offset_y == 80
    end

    test "unhandled key passes through" do
      state = Scrollable.default_state()
      {:pass, _} = Scrollable.handle_event({:key, :tab}, state, %{})
    end
  end

  describe "pre_render/3" do
    test "sets viewport dimensions from rect" do
      state = Scrollable.default_state()
      rect = %{x: 0, y: 0, width: 80, height: 40}

      {new_state, _} = Scrollable.pre_render(state, %{}, rect)
      assert new_state._viewport_height == 40
      assert new_state._viewport_width == 80
    end

    test "reduces width for scrollbar when content overflows and show_scrollbar is auto" do
      state = %{Scrollable.default_state() | _content_height: 100, _show_scrollbar: :auto}
      rect = %{x: 0, y: 0, width: 80, height: 40}

      {_, adjusted_rect} = Scrollable.pre_render(state, %{}, rect)
      assert adjusted_rect.width == 79
    end

    test "does not reduce width when content fits" do
      state = %{Scrollable.default_state() | _content_height: 30, _show_scrollbar: :auto}
      rect = %{x: 0, y: 0, width: 80, height: 40}

      {_, adjusted_rect} = Scrollable.pre_render(state, %{}, rect)
      assert adjusted_rect.width == 80
    end
  end
end
