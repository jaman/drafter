defmodule Drafter.Style.Computed do
  @moduledoc """
  Resolves a widget's final style: stylesheet cascade, then inline overrides, then
  theme colour lookup.

  `for_widget/3` and `for_part/4` each build a match context from the widget's type
  and state, run it through a stylesheet, merge the caller's inline style on top,
  and resolve the colour-valued keys against the current theme.
  `to_segment_style/1` then converts the result into the shape
  `Drafter.Draw.Segment` expects.

  ## The match context

  The context is built from the widget's state map, reading `:focused`, `:hovered`,
  `:active`, `:disabled`, `:checked` and `:selected`, each defaulting to `false`
  when the state does not carry it, plus `:expanded`. A state that is not a map
  contributes `false` for every one of them. `:widget_type` comes from the first
  argument and `:id` and `:classes` from the options.

  ## Colour resolution

  `:color`, `:background` and `:border_color` are passed through
  `Drafter.Style.resolve_color/2` with the theme from
  `Drafter.ThemeManager.get_current_theme/0`, so a theme token such as `:primary`
  becomes an RGB triple. No other key is resolved, and in particular the `:fg` and
  `:bg` keys `to_segment_style/1` produces are never theme-resolved.

  Because the theme is read from the session's theme manager, `for_widget/3` and
  `for_part/4` need a running session; only `to_segment_style/1` is usable on its
  own.
  """

  alias Drafter.Style
  alias Drafter.Style.{Stylesheet, StylesheetLoader, WidgetStyles}
  alias Drafter.ThemeManager

  @typedoc "The map handed to `Drafter.Style.Selector.matches?/2`."
  @type context :: map()

  @doc """
  The resolved style for a widget of `widget_type` in `state`.

  Options:

    * `:id` — widget id used for `#id` selectors, default `nil`
    * `:classes` — list of class names used for `.class` selectors, default `[]`
    * `:style` — inline style merged over the stylesheet result, default `%{}`.
      Not filtered through `Drafter.Style.new/1`, so unknown keys survive.
    * `:stylesheet` — a `Drafter.Style.Stylesheet` to cascade against. When absent
      the sheet is loaded from `:app_module`.
    * `:app_module` — app whose stylesheet to load through
      `Drafter.Style.StylesheetLoader.load_stylesheet/1`, default `nil`. A `nil`
      module, or a load that fails, falls back to
      `Drafter.Style.WidgetStyles.default_stylesheet/0`.

  Passing `:stylesheet` makes `:app_module` unused.

      Drafter.Style.Computed.for_widget(:button, %{focused: true}, classes: [:primary])

  """
  @spec for_widget(atom(), map() | struct() | term(), keyword()) :: Style.t()
  def for_widget(widget_type, state, opts \\ []) do
    context = build_context(widget_type, state, opts)
    stylesheet = get_stylesheet(opts)
    inline_style = Keyword.get(opts, :style, %{})

    base_style = Stylesheet.compute_style(stylesheet, context)
    merged = Style.merge(base_style, inline_style)

    theme = ThemeManager.get_current_theme()
    resolve_colors(merged, theme)
  end

  @doc """
  The resolved style for the `part` sub-region of a widget of `widget_type`.

  As `for_widget/3`, with `:part` set to `part` in the match context so that
  `::part` selectors apply, and with one more layer merged on top.

  Options are those of `for_widget/3`, plus:

    * `:part_styles` — map of `%{part => style}` whose entry for `part` is merged
      last, over both the stylesheet result and `:style`. Default `%{}`, and a part
      with no entry contributes nothing.

      Drafter.Style.Computed.for_part(:text_input, %{focused: true}, :border)

  """
  @spec for_part(atom(), map() | struct() | term(), atom(), keyword()) :: Style.t()
  def for_part(widget_type, state, part, opts \\ []) do
    context = build_context(widget_type, state, opts)
    context_with_part = Map.put(context, :part, part)
    stylesheet = get_stylesheet(opts)
    inline_style = Keyword.get(opts, :style, %{})
    part_style = get_in(opts, [:part_styles, part]) || %{}

    base_style = Stylesheet.compute_style(stylesheet, context_with_part)
    merged = Style.merge([base_style, inline_style, part_style])

    theme = ThemeManager.get_current_theme()
    resolve_colors(merged, theme)
  end

  @doc """
  Convert a computed style into a `t:Drafter.Draw.Segment.style/0` map.

  `:fg` is taken from the style's `:fg`, or from `:color` when there is no `:fg`;
  `:bg` from `:bg`, or from `:background`. `:bold`, `:dim`, `:italic`, `:underline`
  and `:reverse` are copied across under the same names. Every other key is dropped,
  and a key whose value is `nil` is left out rather than set to `nil`. A key set to
  `false` is kept.

  ## Examples

      iex> Drafter.Style.Computed.to_segment_style(%{color: {1, 2, 3}, bold: true, padding: 2})
      %{bold: true, fg: {1, 2, 3}}

      iex> Drafter.Style.Computed.to_segment_style(%{fg: {1, 2, 3}, color: {9, 9, 9}})
      %{fg: {1, 2, 3}}

      iex> Drafter.Style.Computed.to_segment_style(%{})
      %{}

  """
  @spec to_segment_style(Style.t() | map()) :: Drafter.Draw.Segment.style()
  def to_segment_style(computed_style) do
    fg_color = computed_style[:fg] || computed_style[:color]
    bg_color = computed_style[:bg] || computed_style[:background]

    %{}
    |> maybe_put(:fg, fg_color)
    |> maybe_put(:bg, bg_color)
    |> maybe_put(:bold, computed_style[:bold])
    |> maybe_put(:dim, computed_style[:dim])
    |> maybe_put(:italic, computed_style[:italic])
    |> maybe_put(:underline, computed_style[:underline])
    |> maybe_put(:reverse, computed_style[:reverse])
  end

  defp build_context(widget_type, state, opts) do
    %{
      widget_type: widget_type,
      id: Keyword.get(opts, :id),
      classes: Keyword.get(opts, :classes, []),
      focused: get_state_value(state, :focused),
      hovered: get_state_value(state, :hovered),
      active: get_state_value(state, :active),
      disabled: get_state_value(state, :disabled),
      checked: get_state_value(state, :checked),
      selected: get_state_value(state, :selected),
      expanded: get_state_value(state, :expanded)
    }
  end

  defp get_state_value(state, key) when is_map(state) do
    Map.get(state, key, false)
  end

  defp get_state_value(state, key) when is_struct(state) do
    if Map.has_key?(state, key) do
      Map.get(state, key, false)
    else
      false
    end
  end

  defp get_state_value(_, _), do: false

  defp get_stylesheet(opts) do
    case Keyword.get(opts, :stylesheet) do
      nil -> load_app_stylesheet(Keyword.get(opts, :app_module))
      stylesheet -> stylesheet
    end
  end

  defp load_app_stylesheet(nil), do: WidgetStyles.default_stylesheet()

  defp load_app_stylesheet(app_module) do
    case StylesheetLoader.load_stylesheet(app_module) do
      {:ok, stylesheet} -> stylesheet
      {:error, _} -> WidgetStyles.default_stylesheet()
    end
  end

  defp resolve_colors(style, theme) do
    style
    |> maybe_resolve_color(:color, theme)
    |> maybe_resolve_color(:background, theme)
    |> maybe_resolve_color(:border_color, theme)
  end

  defp maybe_resolve_color(style, key, theme) do
    case Map.get(style, key) do
      nil -> style
      color -> Map.put(style, key, Style.resolve_color(color, theme))
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
