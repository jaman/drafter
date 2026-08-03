defmodule Drafter.Draw.AlphaBlendTest do
  @moduledoc """
  An `rgba(...)` colour blends with the cell beneath instead of painting solid.

  A terminal has no alpha channel, so the only place transparency can mean anything
  is the compositor, which holds both the overlay and what it covers.
  `Drafter.Color.normalize_with_alpha/1` carries the alpha through to it, and a
  segment keeps fg and bg alphas separately while leaving the rgb where every other
  consumer expects it. The alpha is consumed during compositing: a blended colour
  encodes as ordinary truecolour and the alpha key never survives into the composited
  style. Layer opacity applies on top of a per-colour alpha rather than replacing it.
  """

  use ExUnit.Case, async: true

  alias Drafter.Color
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor

  @viewport %{x: 0, y: 0, width: 4, height: 1}

  defp layer(strips, opts) do
    LayerCompositor.create_layer(
      Keyword.get(opts, :id, :layer),
      strips,
      %{x: 0, y: 0, width: @viewport.width, height: @viewport.height},
      Keyword.get(opts, :z, 0),
      Keyword.get(opts, :opacity, 1.0)
    )
  end

  defp row(text, style), do: Strip.new([Segment.new(text, style)])

  defp composited_style(over_style) do
    base = layer([row("....", %{bg: {0, 0, 0}, fg: {0, 0, 0}})], id: :base, z: 0)
    top = layer([row("XXXX", over_style)], id: :top, z: 1)

    [strip] = LayerCompositor.composite([base, top], @viewport)
    strip.segments |> List.first() |> Map.get(:style)
  end

  describe "Color.normalize_with_alpha/1" do
    test "keeps the alpha an rgba string carries" do
      assert Color.normalize_with_alpha("rgba(255, 0, 0, 0.5)") == {{255, 0, 0}, 0.5}
    end

    test "keeps the alpha a 4-tuple carries" do
      assert Color.normalize_with_alpha({10, 20, 30, 0.25}) == {{10, 20, 30}, 0.25}
    end

    test "reports fully opaque for colours with no alpha" do
      assert Color.normalize_with_alpha("#f00") == {{255, 0, 0}, 1.0}
      assert Color.normalize_with_alpha({1, 2, 3}) == {{1, 2, 3}, 1.0}
      assert Color.normalize_with_alpha(:black) == {{0, 0, 0}, 1.0}
    end

    test "clamps a nonsense alpha rather than propagating it" do
      assert Color.normalize_with_alpha({1, 2, 3, 5.0}) == {{1, 2, 3}, 1.0}
      assert Color.normalize_with_alpha({1, 2, 3, -2.0}) == {{1, 2, 3}, 0.0}
    end
  end

  describe "a segment built from an rgba colour" do
    test "keeps the rgb where every consumer expects it" do
      style = Segment.new("x", %{bg: "rgba(255, 0, 0, 0.5)"}).style

      assert style.bg == {255, 0, 0}
      assert style.bg_alpha == 0.5
    end

    test "carries no alpha key when the colour is opaque" do
      style = Segment.new("x", %{bg: "#f00"}).style

      assert style.bg == {255, 0, 0}
      refute Map.has_key?(style, :bg_alpha)
    end

    test "tracks fg and bg alphas separately" do
      style = Segment.new("x", %{fg: {255, 255, 255, 0.25}, bg: {0, 0, 0, 0.75}}).style

      assert style.fg_alpha == 0.25
      assert style.bg_alpha == 0.75
    end
  end

  describe "compositing" do
    test "a half-transparent overlay lands halfway to the colour beneath" do
      style = composited_style(%{bg: {255, 0, 0, 0.5}})

      assert style.bg == {128, 0, 0}
    end

    test "a fully transparent overlay leaves the colour beneath untouched" do
      style = composited_style(%{bg: {255, 0, 0, 0.0}})

      assert style.bg == {0, 0, 0}
    end

    test "a fully opaque overlay covers what is beneath" do
      style = composited_style(%{bg: {255, 0, 0, 1.0}})

      assert style.bg == {255, 0, 0}
    end

    test "the alpha key never survives into the composited style" do
      style = composited_style(%{bg: {255, 0, 0, 0.5}, fg: {255, 255, 255, 0.5}})

      refute Map.has_key?(style, :bg_alpha)
      refute Map.has_key?(style, :fg_alpha)
    end

    test "a blended colour encodes as ordinary truecolour, since terminals have no alpha" do
      style = composited_style(%{bg: {255, 0, 0, 0.5}})

      assert Segment.style_codes(style) =~ "48;2;128;0;0"
    end

    test "foreground alpha blends against the background beneath" do
      style = composited_style(%{fg: {255, 255, 255, 0.5}})

      assert style.fg == {128, 128, 128}
    end

    test "layer opacity still applies, and composes with a per-colour alpha" do
      base = layer([row("....", %{bg: {0, 0, 0}})], id: :base, z: 0)
      top = layer([row("XXXX", %{bg: {255, 255, 255}})], id: :top, z: 1, opacity: 0.5)

      [strip] = LayerCompositor.composite([base, top], @viewport)

      assert List.first(strip.segments).style.bg == {128, 128, 128}
    end
  end
end
