defmodule Drafter.Widget.SliderTest do
  use ExUnit.Case

  alias Drafter.CharacterSet
  alias Drafter.Draw.Strip
  alias Drafter.Widget.Slider

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  defp rect(width, height \\ 1), do: %{x: 0, y: 0, width: width, height: height}

  defp lines(strips), do: Enum.map(strips, &Strip.to_plain_text/1)

  defp track_line(state, rect), do: state |> Slider.render(rect) |> lines() |> hd()

  defp thumb_at(line), do: line |> String.graphemes() |> Enum.find_index(&(&1 == thumb()))

  defp thumb, do: CharacterSet.slider(:thumb)

  defp bare(props),
    do: Slider.mount(Map.merge(%{renderer: :text, show_value: false}, props))

  describe "mount/1" do
    test "mounts with defaults" do
      state = Slider.mount(%{})

      assert state.value == 0.0
      assert state.min == 0.0
      assert state.max == 1.0
      assert state.step == nil
      assert state.label == nil
      assert state.orientation == :horizontal
      assert state.show_value == true
      assert state.disabled == false
      assert state.dragging == false
      assert state.focused == false
    end

    test "clamps the mounted value into the range" do
      assert Slider.mount(%{value: 5.0}).value == 1.0
      assert Slider.mount(%{value: -5.0, min: -1.0, max: 1.0}).value == -1.0
    end

    test "snaps the mounted value to the step" do
      assert Slider.mount(%{value: 0.37, step: 0.25}).value == 0.25
    end

    test "keeps an integer range on integers" do
      state = Slider.mount(%{value: 4, min: 0, max: 10, step: 1})
      assert state.value === 4
    end
  end

  describe "keyboard" do
    test "right and up raise the value by one step" do
      state = Slider.mount(%{value: 0.5, step: 0.1})

      assert {:ok, right} = Slider.handle_key(:right, state)
      assert right.value == 0.6

      assert {:ok, up} = Slider.handle_key(:up, state)
      assert up.value == 0.6
    end

    test "left and down lower the value by one step" do
      state = Slider.mount(%{value: 0.5, step: 0.1})

      assert {:ok, left} = Slider.handle_key(:left, state)
      assert left.value == 0.4

      assert {:ok, down} = Slider.handle_key(:down, state)
      assert down.value == 0.4
    end

    test "moves by a hundredth of the range when no step is given" do
      state = Slider.mount(%{value: 0.5})
      assert {:ok, moved} = Slider.handle_key(:right, state)
      assert moved.value == 0.51
    end

    test "home and end jump to the ends of the range" do
      state = Slider.mount(%{value: 0.5, min: -1.0, max: 1.0})

      assert {:ok, home} = Slider.handle_key(:home, state)
      assert home.value == -1.0

      assert {:ok, last} = Slider.handle_key(:end, state)
      assert last.value == 1.0
    end

    test "page keys move by ten steps" do
      state = Slider.mount(%{value: 0.5, step: 0.01})

      assert {:ok, up} = Slider.handle_key(:page_up, state)
      assert up.value == 0.6

      assert {:ok, down} = Slider.handle_key(:page_down, state)
      assert down.value == 0.4
    end

    test "stops at the ends of the range" do
      assert {:ok, low} = Slider.handle_key(:left, Slider.mount(%{value: 0.0, step: 0.1}))
      assert low.value == 0.0

      assert {:ok, high} = Slider.handle_key(:right, Slider.mount(%{value: 1.0, step: 0.1}))
      assert high.value == 1.0
    end

    test "an unrelated key bubbles" do
      state = Slider.mount(%{value: 0.5})
      assert {:bubble, ^state} = Slider.handle_key(:q, state)
    end

    test "a disabled slider ignores keys" do
      state = Slider.mount(%{value: 0.5, step: 0.1, disabled: true})
      assert {:bubble, ^state} = Slider.handle_key(:right, state)
    end
  end

  describe "mouse" do
    test "a press sets the value from the column and starts a drag" do
      state = bare(%{value: 0.0})

      assert {:ok, pressed} = Slider.handle_press(10, 0, on_rect_change(state, 21, 1))
      assert pressed.value == 0.5
      assert pressed.dragging == true
    end

    test "a press at the ends reaches the ends of the range" do
      state = on_rect_change(bare(%{value: 0.5}), 21, 1)

      assert {:ok, left} = Slider.handle_press(0, 0, state)
      assert left.value == 0.0

      assert {:ok, right} = Slider.handle_press(20, 0, state)
      assert right.value == 1.0
    end

    test "a press outside the track clamps rather than overflowing" do
      state = on_rect_change(bare(%{value: 0.5}), 21, 1)

      assert {:ok, before} = Slider.handle_press(-4, 0, state)
      assert before.value == 0.0

      assert {:ok, past} = Slider.handle_press(40, 0, state)
      assert past.value == 1.0
    end

    test "a drag tracks the pointer" do
      state = %{on_rect_change(bare(%{value: 0.0}), 21, 1) | dragging: true}

      assert {:ok, dragged} = Slider.handle_drag(5, 0, state)
      assert dragged.value == 0.25
    end

    test "a release ends the drag" do
      state = %{on_rect_change(bare(%{value: 0.0}), 21, 1) | dragging: true}

      assert {:ok, released} = Slider.handle_mouse_up(10, 0, state)
      assert released.dragging == false
      assert released.value == 0.5
    end

    test "the value text is kept out of the track" do
      state = on_rect_change(Slider.mount(%{value: 0.0, renderer: :text}), 26, 1)

      assert {:ok, pressed} = Slider.handle_press(20, 0, state)
      assert pressed.value == 1.0
    end

    test "a disabled slider ignores a press" do
      state = on_rect_change(bare(%{value: 0.5, disabled: true}), 21, 1)
      assert {:bubble, ^state} = Slider.handle_press(0, 0, state)
    end

    test "scrolling moves by one step" do
      state = Slider.mount(%{value: 0.5, step: 0.1})

      assert {:ok, up} = Slider.handle_scroll(:up, state)
      assert up.value == 0.6

      assert {:ok, down} = Slider.handle_scroll(:down, state)
      assert down.value == 0.4
    end

    test "hover is tracked" do
      state = Slider.mount(%{})

      assert {:ok, hovered} = Slider.handle_event(:hover, state)
      assert hovered.hovered == true

      assert {:ok, unhovered} = Slider.handle_event(:unhover, hovered)
      assert unhovered.hovered == false
    end
  end

  describe "on_change" do
    test "fires with the new value when it changes" do
      parent = self()
      state = Slider.mount(%{value: 0.5, step: 0.1, on_change: &send(parent, {:changed, &1})})

      assert {:ok, _} = Slider.handle_key(:right, state)
      assert_received {:changed, 0.6}
    end

    test "stays quiet when the value does not move" do
      parent = self()
      state = Slider.mount(%{value: 1.0, step: 0.1, on_change: &send(parent, {:changed, &1})})

      assert {:ok, _} = Slider.handle_key(:right, state)
      refute_received {:changed, _}
    end
  end

  describe "render/2" do
    test "fills the rect it is given" do
      state = Slider.mount(%{value: 0.5, renderer: :text})
      strips = Slider.render(state, rect(30, 3))

      assert length(strips) == 3
      assert Enum.all?(strips, &(Strip.width(&1) == 30))
    end

    test "returns nothing for a rect with no width" do
      assert Slider.render(Slider.mount(%{}), rect(0, 1)) == []
    end

    test "puts the thumb at the left end at the minimum" do
      assert thumb_at(track_line(bare(%{value: 0.0}), rect(21))) == 0
    end

    test "puts the thumb at the right end at the maximum" do
      assert thumb_at(track_line(bare(%{value: 1.0}), rect(21))) == 20
    end

    test "puts the thumb in the middle halfway" do
      assert thumb_at(track_line(bare(%{value: 0.5}), rect(21))) == 10
    end

    test "draws the value with the precision the step implies" do
      line = track_line(Slider.mount(%{value: 0.5, renderer: :text}), rect(30))
      assert String.ends_with?(line, "0.50")

      whole = track_line(Slider.mount(%{value: 50, min: 0, max: 100, renderer: :text}), rect(30))
      assert String.ends_with?(whole, "50")
    end

    test "honours an explicit precision" do
      state = Slider.mount(%{value: 0.546, precision: 3, renderer: :text})
      assert String.ends_with?(track_line(state, rect(30)), "0.546")
    end

    test "honours a format function" do
      state = Slider.mount(%{value: 0.5, format: fn value -> "#{round(value * 100)}%" end})
      assert String.ends_with?(track_line(state, rect(30)), "50%")
    end

    test "draws the label ahead of the track" do
      state = Slider.mount(%{value: 0.5, label: "Gain", renderer: :text})
      assert String.starts_with?(track_line(state, rect(30)), "Gain")
    end

    test "reserves the widest value text so the track does not move" do
      low = Slider.mount(%{value: 0, min: 0, max: 100, renderer: :text})
      high = Slider.mount(%{value: 100, min: 0, max: 100, renderer: :text})

      assert thumb_at(track_line(low, rect(30))) == 0
      assert thumb_at(track_line(high, rect(30))) == 25
    end

    test "draws a vertical slider down its rect" do
      state = Slider.mount(%{value: 0.5, orientation: :vertical, renderer: :text})
      strips = Slider.render(state, rect(9, 7))

      assert length(strips) == 7
      assert Enum.all?(strips, &(Strip.width(&1) == 9))
    end

    test "puts a vertical thumb at the bottom at the minimum" do
      state = bare(%{value: 0.0, orientation: :vertical})
      rows = state |> Slider.render(rect(5, 5)) |> lines()

      assert rows |> List.last() |> String.contains?(thumb())
    end

    test "puts a vertical thumb at the top at the maximum" do
      state = bare(%{value: 1.0, orientation: :vertical})
      rows = state |> Slider.render(rect(5, 5)) |> lines()

      assert rows |> hd() |> String.contains?(thumb())
    end

    test "renders a props map without mounting first" do
      strips = Slider.render(%{value: 0.5, renderer: :text}, rect(20, 1))
      assert length(strips) == 1
    end

    test "survives a rect too narrow for a track" do
      state = Slider.mount(%{value: 0.5, label: "A very long label", renderer: :text})
      strips = Slider.render(state, rect(4, 1))

      assert length(strips) == 1
      assert Strip.width(hd(strips)) == 4
    end
  end

  describe "braille rendering" do
    test "draws the slider as braille cells" do
      state = Slider.mount(%{value: 0.5, renderer: :braille, show_value: false})
      strips = Slider.render(state, rect(20, 1))

      assert length(strips) == 1
      assert Strip.width(hd(strips)) == 20
    end

    test "the drawn extent grows with the value" do
      low = Slider.mount(%{value: 0.0, renderer: :braille, show_value: false})
      high = Slider.mount(%{value: 1.0, renderer: :braille, show_value: false})

      assert lines(Slider.render(low, rect(20, 1))) != lines(Slider.render(high, rect(20, 1)))
    end
  end

  describe "update/2" do
    test "applies a new value, clamped and snapped" do
      state = Slider.mount(%{value: 0.5, step: 0.25})
      assert Slider.update(%{value: 0.9}, state).value == 1.0
      assert Slider.update(%{value: 0.4}, state).value == 0.5
    end

    test "keeps fields the props do not mention" do
      state = Slider.mount(%{value: 0.5, label: "Gain"})
      assert Slider.update(%{value: 0.2}, state).label == "Gain"
    end

    test "reclamps the value when the range moves" do
      state = Slider.mount(%{value: 90, min: 0, max: 100})
      assert Slider.update(%{max: 50}, state).value == 50
    end
  end

  describe "on_rect_change/2" do
    test "records the rect the layout gave the widget" do
      state = on_rect_change(Slider.mount(%{}), 40, 3)

      assert state.width == 40
      assert state.height == 3
    end
  end

  describe "component plumbing" do
    test "registers under the slider tag" do
      assert Slider.component_tag() == :slider
      assert Drafter.Widget.Registry.lookup(:slider) == Slider
    end

    test "builds props from element opts" do
      props = Slider.from_component_opts(nil, value: 3, min: 0, max: 10, step: 1, label: "Take")

      assert props.value == 3
      assert props.min == 0
      assert props.max == 10
      assert props.step == 1
      assert props.label == "Take"
    end

    test "reads a bound value out of the app state" do
      opts = [bind: :gain, __app_state__: %{gain: 0.75}]
      assert Slider.from_component_opts(nil, opts).value == 0.75
    end

    test "builds a change callback that writes back to the bound key" do
      props = Slider.from_component_opts(nil, bind: :gain)
      assert is_function(props.on_change, 1)

      props.on_change.(0.25)
      assert_received {:bound_state_update, :gain, 0.25}
    end

    test "an unbound slider keeps the value the user set" do
      props = Slider.from_component_opts(nil, value: 0.5)
      state = Slider.mount(%{value: 0.8})

      refute Map.has_key?(Slider.update_props_from_mount(props, state, []), :value)
    end

    test "a bound slider takes a value that differs from its own" do
      opts = [bind: :gain, __app_state__: %{gain: 0.25}]
      props = Slider.from_component_opts(nil, opts)
      state = Slider.mount(%{value: 0.8})

      assert Slider.update_props_from_mount(props, state, opts).value == 0.25
    end

    test "a bound slider is left alone when the value already agrees" do
      opts = [bind: :gain, __app_state__: %{gain: 0.8}]
      props = Slider.from_component_opts(nil, opts)
      state = Slider.mount(%{value: 0.8})

      refute Map.has_key?(Slider.update_props_from_mount(props, state, opts), :value)
    end

    test "asks for one row, or the height it was given" do
      assert Slider.preferred_height(nil, []) == 1
      assert Slider.preferred_height(nil, height: 3) == 3
      assert Slider.preferred_height(nil, orientation: :vertical) == 8
    end
  end

  defp on_rect_change(state, width, height) do
    Slider.on_rect_change(%{x: 0, y: 0, width: width, height: height}, state)
  end
end
