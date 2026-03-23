defmodule Drafter.Style.Computed do
  @moduledoc false

  alias Drafter.Style
  alias Drafter.Style.{Stylesheet, StylesheetLoader, WidgetStyles}
  alias Drafter.ThemeManager

  @type context :: map()

  def for_widget(widget_type, state, opts \\ []) do
    context = build_context(widget_type, state, opts)
    stylesheet = get_stylesheet(opts)
    inline_style = Keyword.get(opts, :style, %{})

    base_style = Stylesheet.compute_style(stylesheet, context)
    merged = Style.merge(base_style, inline_style)

    theme = ThemeManager.get_current_theme()
    resolve_colors(merged, theme)
  end

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
