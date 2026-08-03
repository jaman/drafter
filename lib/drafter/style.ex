defmodule Drafter.Style do
  @moduledoc """
  Color and style utilities for widget rendering.

  Provides RGB color manipulation (lighten, darken, blend, interpolate),
  type definitions shared across the rendering pipeline, ANSI escape
  sequence helpers, and normalisation of the `:class` option every widget takes.
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

  @doc """
  Builds a style map from `props`, dropping every key that is not a recognised
  style property.

  Defaults to `%{}` when called with no argument. The recognised keys are exactly
  the optional keys of `t:t/0`.

  ## Examples

      iex> Drafter.Style.new(%{bold: true, nonsense: 1})
      %{bold: true}

      iex> Drafter.Style.new()
      %{}

  """
  @spec new(map()) :: t()
  def new(props \\ %{}) when is_map(props) do
    props
    |> Enum.filter(fn {k, _v} -> k in @valid_properties end)
    |> Map.new()
  end

  @doc """
  The atom form of a single CSS class name.

  An atom is returned as given. A string becomes the existing atom of that name
  where there is one, and a new atom otherwise, so a class named only in a
  stylesheet still resolves.

      iex> Drafter.Style.normalize_class(:primary)
      :primary

      iex> Drafter.Style.normalize_class("primary")
      :primary

  """
  @spec normalize_class(String.t() | atom()) :: atom()
  def normalize_class(class) when is_atom(class), do: class

  def normalize_class(class) when is_binary(class) do
    String.to_existing_atom(class)
  rescue
    ArgumentError -> String.to_atom(class)
  end

  @doc """
  The atom list form of a widget's `:class` option.

  Accepts a list, a single class, a string or an atom, and always returns a list.

      iex> Drafter.Style.normalize_classes(["primary", :large])
      [:primary, :large]

      iex> Drafter.Style.normalize_classes("primary")
      [:primary]

      iex> Drafter.Style.normalize_classes([])
      []

  """
  @spec normalize_classes([String.t() | atom()] | String.t() | atom()) :: [atom()]
  def normalize_classes(classes) when is_list(classes), do: Enum.map(classes, &normalize_class/1)
  def normalize_classes(class), do: normalize_classes([class])

  @doc """
  Merges `override` onto `base`, with `override` winning on conflicts.

  A `nil` override returns `base` unchanged. Neither side is filtered against the
  recognised property list.

  ## Examples

      iex> Drafter.Style.merge(%{bold: true, color: :red}, %{color: :blue})
      %{bold: true, color: :blue}

      iex> Drafter.Style.merge(%{bold: true}, nil)
      %{bold: true}

  """
  @spec merge(t(), t() | nil) :: t()
  def merge(base, nil) when is_map(base), do: base

  def merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override)
  end

  @doc """
  Merges a list of style maps left to right, so later entries win.

  ## Examples

      iex> Drafter.Style.merge([%{bold: true}, %{color: :red}, %{bold: false}])
      %{bold: false, color: :red}

      iex> Drafter.Style.merge([])
      %{}

  """
  @spec merge([t()]) :: t()
  def merge(styles) when is_list(styles) do
    Enum.reduce(styles, %{}, fn style, acc ->
      Map.merge(acc, style)
    end)
  end

  @doc """
  Reads `property` from `style`, returning `default` when absent.

  `default` is `nil` when omitted.

  ## Examples

      iex> Drafter.Style.get(%{bold: true}, :bold)
      true

      iex> Drafter.Style.get(%{}, :bold)
      nil

      iex> Drafter.Style.get(%{}, :bold, false)
      false

  """
  @spec get(t(), atom(), term()) :: term()
  def get(style, property, default \\ nil) do
    Map.get(style, property, default)
  end

  @doc """
  Sets `property` to `value`, silently ignoring properties that are not recognised.

  ## Examples

      iex> Drafter.Style.put(%{}, :bold, true)
      %{bold: true}

      iex> Drafter.Style.put(%{}, :nonsense, true)
      %{}

  """
  @spec put(t(), atom(), term()) :: t()
  def put(style, property, value) when property in @valid_properties do
    Map.put(style, property, value)
  end

  def put(style, _property, _value), do: style

  @doc """
  Converts a style map to the segment style map used by the rendering pipeline.

  Reads the foreground from `:fg` falling back to `:color`, and the background
  from `:bg` falling back to `:background`; both are passed through
  `resolve_color/2`. Copies `:bold`, `:dim`, `:italic`, `:underline` and
  `:reverse` through unchanged. Keys whose resolved value is `nil` are omitted
  entirely, so the result contains only the attributes that were actually set.

  `theme` defaults to `nil`, in which case atom colour names resolve against
  `Drafter.ThemeManager.get_current_theme/0`.

  ## Examples

      iex> Drafter.Style.to_segment_style(%{fg: {1, 2, 3}, bold: true})
      %{fg: {1, 2, 3}, bold: true}

      iex> Drafter.Style.to_segment_style(%{})
      %{}

  """
  @spec to_segment_style(map(), map() | nil) :: map()
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

  @doc """
  Resolve any colour form to an `{r, g, b}` triple, or `nil`.

  Accepts an `{r, g, b}` triple (returned as is), `{:rgba, {r, g, b}, alpha}`, a CSS
  `"#rrggbb"`, `"rgb(...)"` or `"rgba(...)"` string, a theme slot name as an atom, or
  that slot name as a string. Alpha is flattened by mixing against the theme's
  `:background`, falling back to black.

  `theme` may be `nil`, in which case atom slot names resolve against
  `Drafter.ThemeManager.get_current_theme/0` — which requires a running theme manager.
  Unparseable strings and unknown slot names return `nil`.
  """
  @spec resolve_color(term(), Drafter.Theme.t() | map() | nil) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()} | nil
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

  @doc """
  Padding from a style map, as `{top, right, bottom, left}`.

  `:padding` wins when set: an integer applies to all four sides, a `{v, h}` pair to
  two each, a four-tuple is taken as written. Without it, the individual
  `:padding_top`, `:padding_right`, `:padding_bottom` and `:padding_left` keys are
  read, each defaulting to `0`.

  ## Examples

      iex> Drafter.Style.get_padding(%{padding: 2})
      {2, 2, 2, 2}

      iex> Drafter.Style.get_padding(%{padding_left: 3})
      {0, 0, 0, 3}

      iex> Drafter.Style.get_padding(%{})
      {0, 0, 0, 0}

  """
  @spec get_padding(map()) :: {integer(), integer(), integer(), integer()}
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

  @doc """
  Margin from a style map, as `{top, right, bottom, left}`.

  Shares the shorthand forms of `get_padding/1`, reading `:margin` and the individual
  `:margin_top`, `:margin_right`, `:margin_bottom` and `:margin_left` keys.

  ## Examples

      iex> Drafter.Style.get_margin(%{margin: {1, 2}})
      {1, 2, 1, 2}

      iex> Drafter.Style.get_margin(%{})
      {0, 0, 0, 0}

  """
  @spec get_margin(map()) :: {integer(), integer(), integer(), integer()}
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

  @doc """
  Subtract `amount` from each channel, flooring at `0`.

  A theme slot atom is resolved first, which needs a running theme manager. A slot
  that does not resolve gives `{30, 30, 30}`, as does any other input — including a
  non-integer `amount`.

  ## Examples

      iex> Drafter.Style.darken({100, 50, 10}, 20)
      {80, 30, 0}

      iex> Drafter.Style.darken("not a colour", 20)
      {30, 30, 30}

  """
  @spec darken(term(), term()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
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

  @doc """
  Add `amount` to each channel, capping at `255`.

  As `darken/2`, but the fallback for anything unresolvable is `{100, 100, 100}`.

  ## Examples

      iex> Drafter.Style.lighten({100, 50, 250}, 20)
      {120, 70, 255}

      iex> Drafter.Style.lighten("not a colour", 20)
      {100, 100, 100}

  """
  @spec lighten(term(), term()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
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

  @doc """
  Lighten by a positive `adjustment` or darken by a negative one.

  Takes an `{r, g, b}` triple only; a slot atom or anything else raises
  `FunctionClauseError`, unlike `darken/2` and `lighten/2`.

  ## Examples

      iex> Drafter.Style.adjust({100, 100, 100}, 20)
      {120, 120, 120}

      iex> Drafter.Style.adjust({100, 100, 100}, -20)
      {80, 80, 80}

  """
  @spec adjust({integer(), integer(), integer()}, integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def adjust({r, g, b}, adjustment) when is_integer(adjustment) do
    if adjustment >= 0 do
      lighten({r, g, b}, adjustment)
    else
      darken({r, g, b}, -adjustment)
    end
  end

  @doc """
  Blend two colours channel by channel.

  `ratio` is the weight given to the *second* colour and defaults to `0.5`. It must
  be a float; an integer raises `FunctionClauseError`.

  ## Examples

      iex> Drafter.Style.mix({0, 0, 0}, {100, 200, 255})
      {50, 100, 128}

      iex> Drafter.Style.mix({0, 0, 0}, {100, 200, 255}, 0.25)
      {25, 50, 64}

  """
  @spec mix({integer(), integer(), integer()}, {integer(), integer(), integer()}, float()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def mix({r1, g1, b1}, {r2, g2, b2}, ratio \\ 0.5) when is_float(ratio) do
    {
      round(r1 * (1 - ratio) + r2 * ratio),
      round(g1 * (1 - ratio) + g2 * ratio),
      round(b1 * (1 - ratio) + b2 * ratio)
    }
  end

  @doc """
  Flatten a colour against the current theme's background at `alpha` opacity.

  `alpha` must be a float in `0.0..1.0`. Resolves `:background` through the running
  theme manager, falling back to black when it has none.
  """
  @spec with_alpha({integer(), integer(), integer()}, float()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def with_alpha({r, g, b}, alpha) when is_float(alpha) and alpha >= 0 and alpha <= 1 do
    bg = resolve_color(:background, nil) || {0, 0, 0}
    mix(bg, {r, g, b}, alpha)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
