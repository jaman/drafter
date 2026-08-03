defmodule Drafter.Widget.ChartPropUpdateTest do
  @moduledoc """
  Props a chart is re-rendered with must reach an already-mounted chart.

  A chart mounts once and is then updated in place on every re-render, so a prop
  that `update/2` drops is frozen at its mount-time value for the life of the
  widget — an app that switches `:renderer` from its own state sees nothing change.
  """

  use ExUnit.Case, async: true

  alias Drafter.Draw.Strip
  alias Drafter.Widget.Chart
  alias Drafter.Widget.Chart.Pixel

  @data [1, 5, 2, 8, 3, 9, 4]
  @rect %{x: 0, y: 0, width: 40, height: 10}

  defp remount(mount_props, update_props) do
    mount_props
    |> Map.put_new(:data, @data)
    |> Chart.mount()
    |> then(&Chart.update(Map.put_new(update_props, :data, @data), &1))
  end

  describe "renderer" do
    test "a new renderer replaces the mount-time one" do
      state = remount(%{renderer: :pixel}, %{renderer: :braille})

      assert state._internal.renderer == :braille
    end

    test "toggling back and forth follows the props each time" do
      mounted = Chart.mount(%{data: @data, renderer: :braille})

      pixel = Chart.update(%{data: @data, renderer: :pixel}, mounted)
      braille = Chart.update(%{data: @data, renderer: :braille}, pixel)

      assert pixel._internal.renderer == :pixel
      assert braille._internal.renderer == :braille
    end

    test "the resolved mode follows the renderer, not the mount" do
      state = remount(%{renderer: :kitty}, %{renderer: :text})

      assert Pixel.mode(state._internal.renderer, state.chart_type) == :text
    end

    test "an absent renderer keeps the mounted one" do
      state = remount(%{renderer: :braille}, %{})

      assert state._internal.renderer == :braille
    end

    test "switching off a pixel renderer stops producing an image" do
      pixel = Chart.mount(%{data: @data, renderer: :kitty})
      braille = Chart.update(%{data: @data, renderer: :braille}, pixel)

      assert Chart.image(pixel, @rect, :probe) != nil

      refute Chart.image(braille, @rect, :probe),
             "a chart switched away from pixel still emits an image, so the old graphic is never cleared"
    end

    test "switching on a pixel renderer starts producing an image" do
      braille = Chart.mount(%{data: @data, renderer: :braille})
      pixel = Chart.update(%{data: @data, renderer: :kitty}, braille)

      refute Chart.image(braille, @rect, :probe)
      assert Chart.image(pixel, @rect, :probe) != nil
    end

    test "the renderer is part of the state a widget server hashes for redraws" do
      braille = Chart.mount(%{data: @data, renderer: :braille})
      pixel = Chart.update(%{data: @data, renderer: :kitty}, braille)

      assert :erlang.phash2(braille) != :erlang.phash2(pixel),
             "a renderer change that leaves the state hash untouched schedules no repaint"
    end
  end

  describe "other declarative props" do
    test "line rendering props follow the props" do
      state =
        remount(
          %{smooth: false, line_thickness: 1, connect_lines: false, image_scale: 4},
          %{smooth: true, line_thickness: 3, connect_lines: true, image_scale: 8}
        )

      assert state._internal.smooth == true
      assert state._internal.line_thickness == 3
      assert state._internal.connect_lines == true
      assert state._internal.image_scale == 8
    end

    test "raw_data follows the props" do
      assert remount(%{raw_data: false}, %{raw_data: true})._internal.raw_data == true
      assert remount(%{raw_data: true}, %{raw_data: false})._internal.raw_data == false
    end

    test "area and baseline props follow the props" do
      state =
        remount(
          %{fill_opacity: 0.6, show_baseline: false, zero_center: :symmetric},
          %{fill_opacity: 0.2, show_baseline: true, zero_center: :none}
        )

      assert state.fill_opacity == 0.2
      assert state.show_baseline == true
      assert state.zero_center == :none
    end
  end

  describe "the modes a demo can cycle through" do
    defp strips(renderer) do
      %{data: @data, renderer: renderer}
      |> Chart.mount()
      |> Chart.render(@rect)
      |> Enum.map_join("\n", &Strip.to_plain_text/1)
    end

    test "braille and text draw different glyphs" do
      refute strips(:braille) == strips(:text)
    end

    test "a pixel renderer leaves the cells blank for the image to occupy" do
      assert strips(:kitty) |> String.trim() == ""
      refute strips(:braille) |> String.trim() == ""
      refute strips(:text) |> String.trim() == ""
    end

    test "each mode fills the requested rect height" do
      for renderer <- [:kitty, :braille, :text] do
        assert length(Chart.render(Chart.mount(%{data: @data, renderer: renderer}), @rect)) ==
                 @rect.height,
               "#{renderer} did not fill the rect, so cycling to it would leave stale rows"
      end
    end
  end

  describe "interaction state" do
    test "scroll, drag and animation offsets survive a re-render" do
      scrolled =
        %{data: @data, renderer: :braille}
        |> Chart.mount()
        |> then(
          &%{
            &1
            | _internal:
                Map.merge(&1._internal, %{scroll_offset: 12, y_offset: 3, animation_offset: 7})
          }
        )

      state = Chart.update(%{data: @data, renderer: :pixel}, scrolled)

      assert state._internal.scroll_offset == 12
      assert state._internal.y_offset == 3
      assert state._internal.animation_offset == 7
      assert state._internal.renderer == :pixel
    end
  end
end
