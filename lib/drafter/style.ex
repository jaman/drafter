defmodule Drafter.Style do
  @moduledoc """
  Color and style utilities for widget rendering.

  Provides RGB color manipulation (lighten, darken, blend, interpolate),
  type definitions shared across the rendering pipeline, and ANSI escape
  sequence helpers.
  """

  alias Drafter.Style.CSSParser

  @type rgb :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type rgba :: {:rgba, rgb(), float()}
  @type color :: rgb() | rgba() | String.t() | atom()

  @type t :: %{
          optional(:color) => color(),
          optional(:background) => color(),
          optional(:bold) => boolean(),
          optional(:dim) => boolean(),
          optional(:italic) => boolean(),
          optional(:underline) => boolean(),
          optional(:reverse) => boolean(),
          optional(:padding) => padding(),
          optional(:padding_top) => non_neg_integer(),
          optional(:padding_right) => non_neg_integer(),
          optional(:padding_bottom) => non_neg_integer(),
          optional(:padding_left) => non_neg_integer(),
          optional(:margin) => margin(),
          optional(:margin_top) => non_neg_integer(),
          optional(:margin_right) => non_neg_integer(),
          optional(:margin_bottom) => non_neg_integer(),
          optional(:margin_left) => non_neg_integer(),
          optional(:width) => dimension(),
          optional(:height) => dimension(),
          optional(:min_width) => non_neg_integer(),
          optional(:max_width) => non_neg_integer(),
          optional(:min_height) => non_neg_integer(),
          optional(:max_height) => non_neg_integer(),
          optional(:border) => border_style(),
          optional(:border_color) => color(),
          optional(:text_align) => :left | :center | :right,
          optional(:text_wrap) => :none | :char | :word,
          optional(:text_overflow) => :clip | :ellipsis,
          optional(:visibility) => :visible | :hidden,
          optional(:opacity) => float()
        }

  @type padding ::
          non_neg_integer()
          | {non_neg_integer(), non_neg_integer()}
          | {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type margin :: padding()
  @type dimension :: non_neg_integer() | :auto | {:percent, number()} | {:fr, number()}
  @type border_style :: :none | :solid | :dashed | :double | :rounded | :heavy

  @valid_properties [
    :color,
    :background,
    :bold,
    :dim,
    :italic,
    :underline,
    :reverse,
    :padding,
    :padding_top,
    :padding_right,
    :padding_bottom,
    :padding_left,
    :margin,
    :margin_top,
    :margin_right,
    :margin_bottom,
    :margin_left,
    :width,
    :height,
    :min_width,
    :max_width,
    :min_height,
    :max_height,
    :border,
    :border_color,
    :text_align,
    :text_wrap,
    :text_overflow,
    :visibility,
    :opacity
  ]

  def new(props \\ %{}) when is_map(props) do
    props
    |> Enum.filter(fn {k, _v} -> k in @valid_properties end)
    |> Map.new()
  end

  def merge(base, nil) when is_map(base), do: base

  def merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override)
  end

  def merge(styles) when is_list(styles) do
    Enum.reduce(styles, %{}, fn style, acc ->
      Map.merge(acc, style)
    end)
  end

  def get(style, property, default \\ nil) do
    Map.get(style, property, default)
  end

  def put(style, property, value) when property in @valid_properties do
    Map.put(style, property, value)
  end

  def put(style, _property, _value), do: style

  def to_segment_style(style, theme \\ nil) do
    fg_color = style[:fg] || style[:color]
    bg_color = style[:bg] || style[:background]

    %{}
    |> maybe_put(:fg, resolve_color(fg_color, theme))
    |> maybe_put(:bg, resolve_color(bg_color, theme))
    |> maybe_put(:bold, style[:bold])
    |> maybe_put(:dim, style[:dim])
    |> maybe_put(:italic, style[:italic])
    |> maybe_put(:underline, style[:underline])
    |> maybe_put(:reverse, style[:reverse])
  end

  def resolve_color(nil, _theme), do: nil

  def resolve_color({r, g, b}, _theme) when is_integer(r) and is_integer(g) and is_integer(b),
    do: {r, g, b}

  def resolve_color({:rgba, {r, g, b}, alpha}, theme)
      when is_float(alpha) and alpha >= 0 and alpha <= 1 do
    bg = resolve_color(:background, theme) || {0, 0, 0}
    mix(bg, {r, g, b}, alpha)
  end

  def resolve_color("#" <> _hex_str = hex_color, theme) do
    case CSSParser.parse_hex_color(hex_color) do
      {:ok, rgb} -> rgb
      :error -> resolve_color_fallback(hex_color, theme)
    end
  end

  def resolve_color("rgb(" <> _ = rgb_str, theme) do
    case CSSParser.parse_rgb_color(rgb_str) do
      {:ok, rgb} -> rgb
      :error -> resolve_color_fallback(rgb_str, theme)
    end
  end

  def resolve_color("rgba(" <> _ = rgba_str, theme) do
    case CSSParser.parse_rgba_color(rgba_str) do
      {:ok, {:rgba, rgb, alpha}} ->
        bg = resolve_color(:background, theme) || {0, 0, 0}
        mix(bg, rgb, alpha)

      :error ->
        resolve_color_fallback(rgba_str, theme)
    end
  end

  def resolve_color(name, theme) when is_atom(name) do
    resolved_theme =
      if theme do
        theme
      else
        Drafter.ThemeManager.get_current_theme()
      end

    case Map.get(resolved_theme, name) do
      nil -> resolved_theme |> Map.get(:cursor, %{}) |> Map.get(name)
      value -> value
    end
  end

  def resolve_color(name, theme) when is_binary(name) do
    resolve_color(String.to_existing_atom(name), theme)
  rescue
    ArgumentError -> resolve_color_fallback(name, theme)
  end

  defp resolve_color_fallback(_name, _theme), do: nil

  def get_padding(style) do
    case style[:padding] do
      nil ->
        {
          style[:padding_top] || 0,
          style[:padding_right] || 0,
          style[:padding_bottom] || 0,
          style[:padding_left] || 0
        }

      n when is_integer(n) ->
        {n, n, n, n}

      {v, h} ->
        {v, h, v, h}

      {t, r, b, l} ->
        {t, r, b, l}
    end
  end

  def get_margin(style) do
    case style[:margin] do
      nil ->
        {
          style[:margin_top] || 0,
          style[:margin_right] || 0,
          style[:margin_bottom] || 0,
          style[:margin_left] || 0
        }

      n when is_integer(n) ->
        {n, n, n, n}

      {v, h} ->
        {v, h, v, h}

      {t, r, b, l} ->
        {t, r, b, l}
    end
  end

  def darken({r, g, b}, amount) when is_integer(amount) do
    {max(0, r - amount), max(0, g - amount), max(0, b - amount)}
  end

  def darken(color, amount) when is_atom(color) do
    case resolve_color(color, nil) do
      {r, g, b} -> darken({r, g, b}, amount)
      _ -> {30, 30, 30}
    end
  end

  def darken(_, _), do: {30, 30, 30}

  def lighten({r, g, b}, amount) when is_integer(amount) do
    {min(255, r + amount), min(255, g + amount), min(255, b + amount)}
  end

  def lighten(color, amount) when is_atom(color) do
    case resolve_color(color, nil) do
      {r, g, b} -> lighten({r, g, b}, amount)
      _ -> {100, 100, 100}
    end
  end

  def lighten(_, _), do: {100, 100, 100}

  def adjust({r, g, b}, adjustment) when is_integer(adjustment) do
    if adjustment >= 0 do
      lighten({r, g, b}, adjustment)
    else
      darken({r, g, b}, -adjustment)
    end
  end

  def mix({r1, g1, b1}, {r2, g2, b2}, ratio \\ 0.5) when is_float(ratio) do
    {
      round(r1 * (1 - ratio) + r2 * ratio),
      round(g1 * (1 - ratio) + g2 * ratio),
      round(b1 * (1 - ratio) + b2 * ratio)
    }
  end

  def with_alpha({r, g, b}, alpha) when is_float(alpha) and alpha >= 0 and alpha <= 1 do
    bg = resolve_color(:background, nil) || {0, 0, 0}
    mix(bg, {r, g, b}, alpha)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
