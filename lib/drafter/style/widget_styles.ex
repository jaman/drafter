defmodule Drafter.Style.WidgetStyles do
  @moduledoc """
  The built-in stylesheet every app starts from.

  One rule set per widget kind, written against theme colour tokens such as
  `:primary` and `:text_muted` rather than RGB values, so the same rules follow
  whichever theme is current. `Drafter.Style.Computed` resolves the tokens at
  render time.

  Rules use the selector syntax of `Drafter.Style.Selector`: a bare widget type for
  the widget's base style, `:pseudo_class` for state, and `::part` for a sub-region.
  Because a stylesheet resolves by specificity and then by insertion order, an app's
  own rules layered on top of these win a tie.

  Widget kinds covered: `button`, `checkbox`, `text_input`, `label`, `collapsible`,
  `switch`, `slider`, `progress_bar`, `option_list`, `data_table`, `tree`, `scrollbar`,
  `radio_set`, `selection_list`, `tabbed_content`, `digits`, `placeholder`,
  `markdown`, `text_area`, `command_palette`, `header` and `footer`.

  The assembled stylesheet is built once and kept in `:persistent_term`.
  """

  alias Drafter.Style.Stylesheet

  @persistent_term_key {__MODULE__, :default_stylesheet}

  @doc """
  The built-in stylesheet.

  Built on the first call and then served from `:persistent_term`, so every caller
  shares one copy. `clear_cache/0` forces the next call to rebuild it.

  ## Examples

      iex> Drafter.Style.WidgetStyles.default_stylesheet()
      ...> |> Drafter.Style.Stylesheet.compute_style(%{widget_type: :label, classes: [:error]})
      %{background: :background, color: :error}

  """
  @spec default_stylesheet() :: Stylesheet.t()
  def default_stylesheet do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        stylesheet = build_stylesheet()
        :persistent_term.put(@persistent_term_key, stylesheet)
        stylesheet

      stylesheet ->
        stylesheet
    end
  end

  @doc """
  Discard the cached stylesheet so the next `default_stylesheet/0` rebuilds it.

  Always returns `:ok`, whether or not anything was cached.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase(@persistent_term_key)
    :ok
  end

  defp build_stylesheet do
    Stylesheet.new()
    |> add_button_styles()
    |> add_checkbox_styles()
    |> add_text_input_styles()
    |> add_label_styles()
    |> add_collapsible_styles()
    |> add_switch_styles()
    |> add_slider_styles()
    |> add_progress_bar_styles()
    |> add_option_list_styles()
    |> add_data_table_styles()
    |> add_tree_styles()
    |> add_scrollbar_styles()
    |> add_radio_set_styles()
    |> add_selection_list_styles()
    |> add_tabbed_content_styles()
    |> add_digits_styles()
    |> add_placeholder_styles()
    |> add_markdown_styles()
    |> add_text_area_styles()
    |> add_command_palette_styles()
    |> add_header_styles()
    |> add_footer_styles()
  end

  defp add_button_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "button" => %{
        color: :background,
        background: :primary,
        bold: true
      },
      "button:hover" => %{},
      "button:focus" => %{
        reverse: true
      },
      "button:active" => %{},
      "button.default" => %{
        color: :text_primary,
        background: :panel
      },
      "button.primary" => %{
        color: :background,
        background: :primary
      },
      "button.success" => %{
        color: :background,
        background: :success
      },
      "button.warning" => %{
        color: :background,
        background: :warning
      },
      "button.error" => %{
        color: :background,
        background: :error
      },
      "button.secondary" => %{
        color: :text_primary,
        background: :secondary
      }
    })
  end

  defp add_checkbox_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "checkbox" => %{
        color: :text_primary,
        background: :surface
      },
      "checkbox:hover" => %{
        bold: true
      },
      "checkbox:focus" => %{
        background: :primary_muted
      },
      "checkbox:checked" => %{
        color: :success
      }
    })
  end

  defp add_text_input_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "text_input" => %{
        color: :text_primary,
        background: :surface
      },
      "text_input:focus" => %{},
      "text_input::border" => %{
        color: :border,
        background: :background
      },
      "text_input:focus::border" => %{
        color: :accent
      },
      "text_input::placeholder" => %{
        color: :text_muted
      }
    })
  end

  defp add_label_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "label" => %{
        color: :text_primary,
        background: :background
      },
      "label.primary" => %{
        color: :primary
      },
      "label.success" => %{
        color: :success
      },
      "label.warning" => %{
        color: :warning
      },
      "label.error" => %{
        color: :error
      },
      "label.muted" => %{
        color: :text_muted
      }
    })
  end

  defp add_collapsible_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "collapsible" => %{
        color: :text_primary,
        background: :background
      },
      "collapsible::arrow" => %{
        color: :primary
      },
      "collapsible:hover" => %{},
      "collapsible:hover::arrow" => %{
        color: :primary
      },
      "collapsible:focus" => %{
        background: :primary,
        bold: true
      },
      "collapsible:focus::arrow" => %{
        color: :accent,
        background: :primary
      }
    })
  end

  defp add_switch_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "switch" => %{
        color: :text_primary,
        background: :background
      },
      "switch::track" => %{
        color: :text_primary,
        background: :panel
      },
      "switch::thumb" => %{
        color: :text_primary,
        background: :border
      },
      "switch::thumb:checked" => %{
        background: :success
      }
    })
  end

  defp add_slider_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "slider" => %{
        color: :text_primary,
        background: :background
      },
      "slider::track" => %{
        color: :border
      },
      "slider::fill" => %{
        color: :primary
      },
      "slider::thumb" => %{
        color: :primary
      },
      "slider::thumb:focus" => %{
        color: :accent
      },
      "slider::value" => %{
        color: :text_muted
      },
      "slider:disabled" => %{
        color: :text_disabled
      }
    })
  end

  defp add_progress_bar_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "progress_bar" => %{
        color: :text_muted,
        background: :background
      },
      "progress_bar::bar" => %{
        color: :primary
      },
      "progress_bar::track" => %{
        color: :surface
      }
    })
  end

  defp add_option_list_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "option_list" => %{
        color: :text_primary,
        background: :surface
      },
      "option_list::item" => %{
        color: :text_primary,
        background: :surface
      },
      "option_list::item:hover" => %{
        background: :panel
      },
      "option_list::item:selected" => %{
        color: :background,
        background: :primary,
        bold: true
      },
      "option_list::item:disabled" => %{
        color: :text_disabled
      }
    })
  end

  defp add_data_table_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "data_table" => %{
        color: :text_primary,
        background: :surface
      },
      "data_table::header" => %{
        color: :text_primary,
        background: :panel,
        bold: true
      },
      "data_table::row" => %{
        color: :text_primary,
        background: :surface
      },
      "data_table::row:selected" => %{
        color: :background,
        background: :primary
      },
      "data_table::cell:focus" => %{
        color: :text_primary,
        background: :accent,
        bold: true
      }
    })
  end

  defp add_tree_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "tree" => %{
        color: :text_primary,
        background: :surface
      },
      "tree::node" => %{
        color: :text_primary
      },
      "tree::node:selected" => %{
        color: :background,
        background: :primary
      },
      "tree::node:focus" => %{
        background: :accent,
        bold: true
      },
      "tree::node:expanded" => %{
        color: :success
      }
    })
  end

  defp add_scrollbar_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "scrollbar::thumb" => %{
        color: :text_muted,
        background: :border
      },
      "scrollbar::thumb:hover" => %{
        color: :background,
        background: :accent
      },
      "scrollbar::track" => %{
        color: :text_disabled,
        background: :panel
      }
    })
  end

  defp add_radio_set_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "radio_set" => %{
        color: :text_primary,
        background: :surface
      },
      "radio_set::option" => %{
        color: :text_primary,
        background: :surface
      },
      "radio_set::option:hover" => %{
        background: :block_hover
      },
      "radio_set::option:selected" => %{
        color: :text_primary,
        background: :surface
      },
      "radio_set::option:focus" => %{
        color: :text_primary,
        background: :block_cursor_blurred
      },
      "radio_set::option:focus:selected" => %{
        color: :block_cursor_foreground,
        background: :block_cursor,
        bold: true
      },
      "radio_set::radio" => %{
        color: :panel
      },
      "radio_set::radio:selected" => %{
        color: :text_success
      }
    })
  end

  defp add_selection_list_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "selection_list" => %{
        color: :text_primary,
        background: :surface
      },
      "selection_list::item" => %{
        color: :text_primary,
        background: :surface
      },
      "selection_list::item:hover" => %{
        background: :block_hover
      },
      "selection_list::item:selected" => %{
        color: :text_success,
        background: :surface
      },
      "selection_list::item:focus" => %{
        color: :text_primary,
        background: :block_cursor_blurred
      },
      "selection_list::item:focus:selected" => %{
        color: :block_cursor_foreground,
        background: :block_cursor,
        bold: true
      },
      "selection_list::checkbox" => %{
        color: :panel
      },
      "selection_list::checkbox:selected" => %{
        color: :text_success
      }
    })
  end

  defp add_tabbed_content_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "tabbed_content" => %{
        color: :text_primary,
        background: :background
      },
      "tabbed_content::border" => %{
        color: :border,
        background: :background
      },
      "tabbed_content::title" => %{
        color: :primary,
        background: :background
      },
      "tabbed_content::tab" => %{
        color: :text_muted,
        background: :background
      },
      "tabbed_content::tab:hover" => %{
        color: :text_primary,
        background: :surface
      },
      "tabbed_content::tab:active" => %{
        color: :text_primary,
        background: :primary
      },
      "tabbed_content::content" => %{
        color: :text_primary,
        background: :background
      },
      "tabbed_content::item" => %{
        color: :text_primary,
        background: :background
      },
      "tabbed_content::item:selected" => %{
        color: :background,
        background: :primary
      }
    })
  end

  defp add_digits_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "digits" => %{
        color: :primary,
        background: :background
      }
    })
  end

  defp add_placeholder_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "placeholder" => %{
        color: :text_primary,
        background: :surface
      }
    })
  end

  defp add_markdown_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "markdown" => %{
        color: :text_primary,
        background: :background
      },
      "markdown::h1" => %{
        color: :primary,
        bold: true
      },
      "markdown::h2" => %{
        color: :secondary,
        bold: true
      },
      "markdown::code" => %{
        color: :accent,
        background: :surface
      },
      "markdown::text" => %{
        color: :text_primary
      }
    })
  end

  defp add_text_area_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "text_area" => %{
        color: :text_primary,
        background: :surface
      },
      "text_area:focus" => %{
        background: :panel
      },
      "text_area::border" => %{
        color: :border,
        background: :background
      },
      "text_area:focus::border" => %{
        color: :accent
      },
      "text_area::placeholder" => %{
        color: :text_muted
      },
      "text_area::cursor" => %{
        color: :text_primary,
        background: :accent
      }
    })
  end

  defp add_command_palette_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "command_palette" => %{
        color: :text_primary,
        background: :panel
      },
      "command_palette::overlay" => %{
        background: :background
      },
      "command_palette::border" => %{
        color: :primary,
        background: :panel
      },
      "command_palette::input" => %{
        color: :text_primary,
        background: :surface
      },
      "command_palette::item" => %{
        color: :text_primary,
        background: :panel
      },
      "command_palette::item:selected" => %{
        color: :text_primary,
        background: :primary
      }
    })
  end

  defp add_header_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "header" => %{
        color: :text_primary,
        background: :primary
      },
      "header::title" => %{
        color: :background,
        background: :primary,
        bold: true
      },
      "header::clock" => %{
        color: :background,
        background: :primary
      }
    })
  end

  defp add_footer_styles(stylesheet) do
    Stylesheet.add_rules(stylesheet, %{
      "footer" => %{
        color: :text_primary,
        background: :panel
      },
      "footer::key" => %{
        color: :background,
        background: :accent,
        bold: true
      }
    })
  end
end
