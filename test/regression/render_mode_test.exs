defmodule Drafter.RenderModeTest do
  use ExUnit.Case, async: false

  alias Drafter.Widget.Chart.Pixel

  setup do
    System.delete_env("DRAFTER_MODE")
    System.delete_env("DRAFTER_NO_PIXEL")
    Application.delete_env(:drafter, :render_mode)

    on_exit(fn ->
      System.delete_env("DRAFTER_MODE")
      System.delete_env("DRAFTER_NO_PIXEL")
      Application.delete_env(:drafter, :render_mode)
    end)

    :ok
  end

  test "unset renderer falls back to text" do
    assert Pixel.resolve(nil) == :text
    assert Pixel.mode(nil, :line) == :text
  end

  test "explicit per-widget renderer wins over the runtime config" do
    Application.put_env(:drafter, :render_mode, :text)

    assert Pixel.resolve(:braille) == :braille
    assert Pixel.mode(:braille, :line) == :braille
  end

  test "DRAFTER_MODE forces and overrides an explicit per-widget renderer" do
    System.put_env("DRAFTER_MODE", "text")

    assert Pixel.resolve(:pixel) == :text
    assert Pixel.mode(:pixel, :line) == :text
  end

  test "DRAFTER_MODE sets the global default" do
    System.put_env("DRAFTER_MODE", "braille")
    assert Pixel.resolve(nil) == :braille
    assert Pixel.mode(nil, :line) == :braille
  end

  test "DRAFTER_MODE parses case-insensitively and trims" do
    System.put_env("DRAFTER_MODE", "  Sixel ")
    assert Pixel.resolve(nil) == :sixel
    assert Pixel.protocol(nil) == :sixel
  end

  test "unknown DRAFTER_MODE is ignored, falls through" do
    System.put_env("DRAFTER_MODE", "nonsense")
    Application.put_env(:drafter, :render_mode, :braille)
    assert Pixel.resolve(nil) == :braille
  end

  test "runtime application env applies when env var unset" do
    Application.put_env(:drafter, :render_mode, :sixel)
    assert Pixel.resolve(nil) == :sixel
  end

  test "DRAFTER_MODE takes precedence over runtime config" do
    System.put_env("DRAFTER_MODE", "braille")
    Application.put_env(:drafter, :render_mode, :sixel)
    assert Pixel.resolve(nil) == :braille
  end

  test "invalid runtime mode is ignored" do
    Application.put_env(:drafter, :render_mode, :bogus)
    assert Pixel.resolve(nil) == :text
  end

  test "legacy DRAFTER_NO_PIXEL maps to text" do
    System.put_env("DRAFTER_NO_PIXEL", "1")
    assert Pixel.resolve(nil) == :text
    assert Pixel.mode(nil, :line) == :text
  end

  test "DRAFTER_MODE overrides the legacy DRAFTER_NO_PIXEL" do
    System.put_env("DRAFTER_NO_PIXEL", "1")
    System.put_env("DRAFTER_MODE", "braille")
    assert Pixel.resolve(nil) == :braille
  end

  test "forced protocol resolves to pixel mode and that protocol" do
    assert Pixel.mode(:kitty, :line) == :pixel
    assert Pixel.protocol(:kitty) == :kitty
  end

  test "unsupported chart type always renders as text" do
    System.put_env("DRAFTER_MODE", "pixel")
    assert Pixel.mode(:pixel, :unsupported_type) == :text
  end

  test "render_mode/1 sets and validates the runtime mode" do
    assert Drafter.render_mode(:braille) == :ok
    assert Pixel.resolve(nil) == :braille

    assert Drafter.render_mode(:bogus) == :ok
    assert Pixel.resolve(nil) == :braille
  end
end
