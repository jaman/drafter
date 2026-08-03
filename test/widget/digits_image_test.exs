defmodule Drafter.Widget.DigitsImageTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.Digits
  alias Drafter.Widget.Digits.{Bitmap, Image}
  alias FrenchCurve.Raster

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp with_env(vars, fun) do
    kept = Map.new(vars, fn {name, _value} -> {name, System.get_env(name)} end)

    put_env(vars)

    try do
      fun.()
    after
      put_env(kept)
    end
  end

  defp put_env(vars) do
    Enum.each(vars, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)
  end

  describe "rasterising" do
    test "text becomes a raster wide enough for every character" do
      raster = Image.raster(["4", "2"], {40, 6}, {255, 255, 255})

      {width, _height} = Raster.dimensions(raster)
      assert width >= 2 * Bitmap.width()
    end

    test "the raster is a whole multiple of the bitmap size" do
      raster = Image.raster(["A"], {40, 6}, {255, 255, 255})
      {width, height} = Raster.dimensions(raster)

      assert rem(width, Bitmap.width()) == 0
      assert rem(height, Bitmap.height()) == 0
      assert div(width, Bitmap.width()) == div(height, Bitmap.height())
    end

    test "an inked character puts pixels down" do
      raster = Image.raster(["8"], {20, 4}, {255, 255, 255})

      lit =
        for x <- 0..(Raster.dimensions(raster) |> elem(0) |> Kernel.-(1)),
            y <- 0..(Raster.dimensions(raster) |> elem(1) |> Kernel.-(1)),
            Raster.get_pixel(raster, x, y) not in [nil, {0, 0, 0, 0}],
            do: {x, y}

      assert lit != []
    end

    test "a blank character puts nothing down" do
      raster = Image.raster([" "], {20, 4}, {255, 255, 255})
      {width, height} = Raster.dimensions(raster)

      inked =
        for x <- 0..(width - 1),
            y <- 0..(height - 1),
            Raster.get_pixel(raster, x, y) not in [nil, {0, 0, 0, 0}],
            do: {x, y}

      assert inked == []
    end

    test "a box too small to scale up still rasterises at native size" do
      graphemes = Enum.map(1..200, fn _ -> "8" end)
      raster = Image.raster(graphemes, {1, 1}, {255, 255, 255})

      assert Raster.dimensions(raster) == {200 * Bitmap.width(), Bitmap.height()}
    end

    test "a larger box scales the glyphs up rather than leaving them native" do
      small = Image.raster(["8"], {4, 2}, {255, 255, 255})
      large = Image.raster(["8"], {40, 20}, {255, 255, 255})

      assert elem(Raster.dimensions(large), 0) > elem(Raster.dimensions(small), 0)
    end
  end

  describe "protocol negotiation" do
    test "no protocol means no image, and the widget falls back to cells" do
      if Image.protocol(:auto) == nil do
        assert Image.render("42", {20, 4}, {255, 255, 255}, :auto, :id) == nil
      end
    end

    test "an explicit protocol produces a paint and a clear" do
      case Image.render("42", {20, 4}, {255, 255, 255}, :sixel, :id) do
        nil ->
          flunk("an explicitly requested protocol should still encode")

        {paint, clear} ->
          assert IO.iodata_length(paint) > 0
          assert is_binary(clear) or is_list(clear)
      end
    end

    test "kitty encoding carries a delete before the transmit so frames do not stack" do
      env = %{
        "TERM" => "xterm-kitty",
        "KITTY_WINDOW_ID" => "1",
        "TERM_PROGRAM" => nil,
        "TERM_PROGRAM_VERSION" => nil
      }

      with_env(env, fn ->
        {paint, clear} = Image.render("7", {10, 3}, {255, 255, 255}, :auto, :some_widget)

        assert IO.iodata_length(clear) > 0
        assert paint |> IO.iodata_to_binary() |> String.starts_with?(IO.iodata_to_binary(clear))
      end)
    end

    test "on iTerm there is nothing to delete, since nothing was stored" do
      env = %{
        "TERM" => "xterm-256color",
        "KITTY_WINDOW_ID" => nil,
        "TERM_PROGRAM" => "iTerm.app",
        "TERM_PROGRAM_VERSION" => "3.5.0"
      }

      with_env(env, fn ->
        {paint, clear} = Image.render("7", {10, 3}, {255, 255, 255}, :auto, :some_widget)

        assert paint |> IO.iodata_to_binary() =~ "\e]1337;File=inline=1"
        assert IO.iodata_length(clear) == 0
      end)
    end

    test "empty text never produces an image" do
      assert Image.render("", {20, 4}, {255, 255, 255}, :sixel, :id) == nil
    end

    test "a zero-area box never produces an image" do
      assert Image.render("42", {0, 4}, {255, 255, 255}, :sixel, :id) == nil
      assert Image.render("42", {20, 0}, {255, 255, 255}, :sixel, :id) == nil
    end
  end

  describe "the widget callback" do
    test "the default renderer draws cells and asks for no image" do
      state = Digits.mount(%{text: "42"})

      assert Digits.image(state, rect(20, 5), :id) == nil
      assert Digits.render(state, rect(20, 5)) != []
    end

    test "an explicit protocol returns paint, clear and a placement box" do
      state = Digits.mount(%{text: "42", renderer: :sixel})

      assert {_paint, _clear, %{dx: 0, dy: 0, cols: 20, rows: 5}} =
               Digits.image(state, rect(20, 5), :id)
    end

    test "cells still render when a graphics renderer is asked for" do
      state = Digits.mount(%{text: "42", renderer: :graphics})

      assert length(Digits.render(state, rect(20, 5))) == 5
    end

    test "the renderer survives a component re-mount" do
      mount_props = Digits.from_component_opts(42, renderer: :graphics)
      existing = Digits.mount(Digits.from_component_opts(42, []))

      assert %{renderer: :graphics} = Digits.update_props_from_mount(mount_props, existing, [])
    end
  end
end
