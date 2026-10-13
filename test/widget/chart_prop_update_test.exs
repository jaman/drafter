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

    test "an absent renderer keeps the mounted one" do
      state = remount(%{renderer: :braille}, %{})

      assert state._internal.renderer == :braille
    end

    test "switching off a pixel renderer stops producing an image" do
      pixel = Chart.mount(%{data: @data, renderer: :kitty})
      braille = Chart.update(%{data: @data, renderer: :braille}, pixel)

      assert Chart.image_raster(pixel, @rect) != nil

      refute Chart.image_raster(braille, @rect),
             "a chart switched away from pixel still emits an image, so the old graphic is never cleared"
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

    test "text draws braille, or quad blocks with the quadrant pixel style" do
      assert strips(:braille) == strips(:text)

      quadrant =
        %{data: @data, renderer: :text, pixel_style: :quadrant}
        |> Chart.mount()
        |> Chart.render(@rect)
        |> Enum.map_join("\n", &Strip.to_plain_text/1)

      refute quadrant == strips(:text)
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

  describe "re-rendering with the same props" do
    defp rerender(opts, state) do
      Chart.update(Chart.from_component_opts(@data, opts), state)
    end

    test "leaves a chart that is not animated unchanged" do
      opts = [chart_type: :bar, renderer: :kitty]
      first = rerender(opts, Chart.mount(Chart.from_component_opts(@data, opts)))
      Process.sleep(2)

      assert rerender(opts, first) === first
    end

    test "advances an animated chart one frame per animation_speed milliseconds" do
      opts = [chart_type: :line, animated: true, animation_speed: 1]
      first = rerender(opts, Chart.mount(Chart.from_component_opts(@data, opts)))
      Process.sleep(3)

      assert rerender(opts, first)._internal.animation_offset > first._internal.animation_offset
    end

    test "shifts the points of an animated pixel chart" do
      state = Chart.mount(%{data: @data, chart_type: :line, renderer: :kitty, animated: true})
      frame = put_in(state._internal.animation_offset, 2)

      refute Chart.image_raster(frame, @rect).raster == Chart.image_raster(state, @rect).raster
    end
  end
end
