defmodule Drafter.Theme do
  @moduledoc """
  Theme definition and built-in theme library for TUI applications.

  A theme is a `%Drafter.Theme{}` struct containing named RGB color slots covering
  UI surfaces, semantic colors (primary, secondary, accent, warning, error, success),
  text variants, cursor colors, and a `syntax` map for code highlighting. The framework
  ships with thirteen ready-to-use themes accessible via `available_themes/0` and
  `get_theme/1`, including `"textual-dark"`, `"nord"`, `"dracula"`, `"monokai"`,
  `"tokyo-night"`, and `"catppuccin-mocha"`.
  """

  defstruct [
    :name,
    :dark,
    :primary,
    :secondary,
    :accent,
    :warning,
    :error,
    :success,
    :background,
    :foreground,
    :surface,
    :panel,
    :border,
    :text_primary,
    :text_secondary,
    :text_muted,
    :text_disabled,
    :text_accent,
    :text_warning,
    :text_error,
    :text_success,
    :primary_muted,
    :secondary_muted,
    :accent_muted,
    :warning_muted,
    :error_muted,
    :success_muted,
    :block_hover,
    cursor: %{},
    syntax: %{}
  ]

  @type rgb :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  A desaturated version of an `{r, g, b}` colour.

  Each channel is moved halfway towards the mean of the three, which keeps the
  colour's brightness and halves its saturation. A grey stays exactly as it was.

  `nil` passes through as `nil`, and any other term is returned unchanged.

  ## Examples

      iex> Drafter.Theme.mute_color({200, 100, 0})
      {150, 100, 50}

      iex> Drafter.Theme.mute_color({80, 80, 80})
      {80, 80, 80}

      iex> Drafter.Theme.mute_color(nil)
      nil

  """
  @spec mute_color(rgb() | nil | term()) :: rgb() | nil | term()
  def mute_color({r, g, b}) when is_integer(r) and is_integer(g) and is_integer(b) do
    avg = div(r + g + b, 3)
    mute_factor = 0.5

    new_r = round(r * mute_factor + avg * (1 - mute_factor))
    new_g = round(g * mute_factor + avg * (1 - mute_factor))
    new_b = round(b * mute_factor + avg * (1 - mute_factor))

    {new_r, new_g, new_b}
  end

  def mute_color(nil), do: nil
  def mute_color(color), do: color

  @type t :: %__MODULE__{
          name: String.t(),
          dark: boolean(),
          primary: rgb(),
          secondary: rgb(),
          accent: rgb(),
          warning: rgb(),
          error: rgb(),
          success: rgb(),
          background: rgb(),
          foreground: rgb(),
          surface: rgb(),
          panel: rgb(),
          border: rgb(),
          text_primary: rgb(),
          text_secondary: rgb(),
          text_muted: rgb(),
          text_disabled: rgb(),
          text_accent: rgb(),
          text_warning: rgb(),
          text_error: rgb(),
          text_success: rgb(),
          primary_muted: rgb(),
          secondary_muted: rgb(),
          accent_muted: rgb(),
          warning_muted: rgb(),
          error_muted: rgb(),
          success_muted: rgb(),
          block_hover: rgb(),
          cursor: %{
            block_cursor: rgb(),
            block_cursor_foreground: rgb(),
            block_cursor_blurred: rgb()
          },
          syntax: %{atom() => rgb()}
        }

  @doc """
  The syntax-highlighting palette derived from a theme's semantic colours.

  Keys: `:keyword`, `:keyword_builtin`, `:type`, `:function`, `:function_builtin`,
  `:variable`, `:string`, `:string_special`, `:number`, `:operator`, `:comment` and
  `:default`. The mapping is currently the same for dark and light themes, but a
  theme whose `:dark` field is neither `true` nor `false` raises
  `FunctionClauseError`.
  """
  @spec default_syntax_colors(t()) :: %{atom() => rgb()}
  def default_syntax_colors(%__MODULE__{dark: true} = theme) do
    %{
      keyword: theme.primary,
      keyword_builtin: theme.secondary,
      type: theme.accent,
      function: theme.primary,
      function_builtin: theme.secondary,
      variable: theme.foreground,
      string: theme.success,
      string_special: theme.text_accent,
      number: theme.warning,
      operator: theme.text_secondary,
      comment: theme.text_muted,
      default: theme.foreground
    }
  end

  def default_syntax_colors(%__MODULE__{dark: false} = theme) do
    %{
      keyword: theme.primary,
      keyword_builtin: theme.secondary,
      type: theme.accent,
      function: theme.primary,
      function_builtin: theme.secondary,
      variable: theme.foreground,
      string: theme.success,
      string_special: theme.text_accent,
      number: theme.warning,
      operator: theme.text_secondary,
      comment: theme.text_muted,
      default: theme.foreground
    }
  end

  @doc """
  The built-in `"textual-dark"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.dark_theme().name
      "textual-dark"

  """
  @spec dark_theme() :: t()
  def dark_theme do
    base = %__MODULE__{
      name: "textual-dark",
      dark: true,
      primary: {1, 120, 212},
      secondary: {0, 69, 120},
      accent: {255, 166, 43},
      warning: {255, 166, 43},
      error: {186, 60, 91},
      success: {78, 191, 113},
      background: {18, 18, 18},
      foreground: {224, 224, 224},
      surface: {30, 30, 30},
      panel: {42, 42, 42},
      border: {68, 68, 68},
      text_primary: {224, 224, 224},
      text_secondary: {180, 180, 180},
      text_muted: {134, 134, 134},
      text_disabled: {85, 85, 85},
      text_accent: {255, 166, 43},
      text_warning: {255, 166, 43},
      text_error: {186, 60, 91},
      text_success: {78, 191, 113},
      primary_muted: {1, 60, 106},
      secondary_muted: {0, 35, 60},
      accent_muted: {128, 83, 22},
      warning_muted: {128, 83, 22},
      error_muted: {93, 30, 46},
      success_muted: {39, 96, 57},
      cursor: %{
        block_cursor: {1, 120, 212},
        block_cursor_foreground: {224, 224, 224},
        block_cursor_blurred: {1, 60, 106}
      },
      block_hover: {38, 38, 38}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"textual-light"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.light_theme().name
      "textual-light"

  """
  @spec light_theme() :: t()
  def light_theme do
    base = %__MODULE__{
      name: "textual-light",
      dark: false,
      primary: {0, 69, 120},
      secondary: {1, 120, 212},
      accent: {255, 166, 43},
      warning: {255, 166, 43},
      error: {186, 60, 91},
      success: {78, 191, 113},
      background: {224, 224, 224},
      foreground: {32, 32, 32},
      surface: {216, 216, 216},
      panel: {208, 208, 208},
      border: {160, 160, 160},
      text_primary: {32, 32, 32},
      text_secondary: {64, 64, 64},
      text_muted: {96, 96, 96},
      text_disabled: {144, 144, 144},
      text_accent: {200, 130, 34},
      text_warning: {200, 130, 34},
      text_error: {150, 48, 73},
      text_success: {62, 153, 90},
      primary_muted: {179, 197, 210},
      secondary_muted: {179, 210, 230},
      accent_muted: {255, 220, 179},
      warning_muted: {255, 220, 179},
      error_muted: {230, 179, 190},
      success_muted: {190, 230, 200},
      cursor: %{
        block_cursor: {0, 69, 120},
        block_cursor_foreground: {224, 224, 224},
        block_cursor_blurred: {179, 197, 210}
      },
      block_hover: {200, 200, 200}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  Every built-in theme, keyed by the name `get_theme/1` takes.

  ## Examples

      iex> Drafter.Theme.available_themes() |> Map.keys() |> Enum.sort() |> hd()
      "catppuccin-mocha"

      iex> Drafter.Theme.available_themes() |> map_size()
      13

  """
  @spec available_themes() :: %{String.t() => t()}
  def available_themes do
    %{
      "textual-dark" => dark_theme(),
      "textual-light" => light_theme(),
      "nord" => nord_theme(),
      "dracula" => dracula_theme(),
      "solarized-dark" => solarized_dark_theme(),
      "solarized-light" => solarized_light_theme(),
      "monokai" => monokai_theme(),
      "gruvbox-dark" => gruvbox_dark_theme(),
      "gruvbox-light" => gruvbox_light_theme(),
      "tokyo-night" => tokyo_night_theme(),
      "catppuccin-mocha" => catppuccin_mocha_theme(),
      "classic" => classic_theme(),
      "retro" => retro_theme()
    }
  end

  @doc """
  The built-in `"nord"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.nord_theme().name
      "nord"

  """
  @spec nord_theme() :: t()
  def nord_theme do
    base = %__MODULE__{
      name: "nord",
      dark: true,
      primary: {136, 192, 208},
      secondary: {129, 161, 193},
      accent: {180, 142, 173},
      warning: {235, 203, 139},
      error: {191, 97, 106},
      success: {163, 190, 140},
      background: {46, 52, 64},
      foreground: {216, 222, 233},
      surface: {59, 66, 82},
      panel: {67, 76, 94},
      border: {76, 86, 106},
      text_primary: {236, 239, 244},
      text_secondary: {216, 222, 233},
      text_muted: {129, 161, 193},
      text_disabled: {76, 86, 106},
      text_accent: {180, 142, 173},
      text_warning: {235, 203, 139},
      text_error: {191, 97, 106},
      text_success: {163, 190, 140},
      primary_muted: {94, 129, 172},
      secondary_muted: {94, 129, 172},
      accent_muted: {143, 113, 138},
      warning_muted: {188, 162, 111},
      error_muted: {153, 78, 85},
      success_muted: {130, 152, 112},
      cursor: %{
        block_cursor: {136, 192, 208},
        block_cursor_foreground: {46, 52, 64},
        block_cursor_blurred: {94, 129, 172}
      },
      block_hover: {67, 76, 94}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"dracula"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.dracula_theme().name
      "dracula"

  """
  @spec dracula_theme() :: t()
  def dracula_theme do
    base = %__MODULE__{
      name: "dracula",
      dark: true,
      primary: {189, 147, 249},
      secondary: {139, 233, 253},
      accent: {255, 184, 108},
      warning: {241, 250, 140},
      error: {255, 85, 85},
      success: {80, 250, 123},
      background: {40, 42, 54},
      foreground: {248, 248, 242},
      surface: {68, 71, 90},
      panel: {68, 71, 90},
      border: {98, 114, 164},
      text_primary: {248, 248, 242},
      text_secondary: {189, 147, 249},
      text_muted: {98, 114, 164},
      text_disabled: {68, 71, 90},
      text_accent: {255, 184, 108},
      text_warning: {241, 250, 140},
      text_error: {255, 85, 85},
      text_success: {80, 250, 123},
      primary_muted: {95, 74, 125},
      secondary_muted: {70, 117, 127},
      accent_muted: {128, 92, 54},
      warning_muted: {121, 125, 70},
      error_muted: {128, 43, 43},
      success_muted: {40, 125, 62},
      cursor: %{
        block_cursor: {189, 147, 249},
        block_cursor_foreground: {40, 42, 54},
        block_cursor_blurred: {95, 74, 125}
      },
      block_hover: {68, 71, 90}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"solarized-dark"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.solarized_dark_theme().name
      "solarized-dark"

  """
  @spec solarized_dark_theme() :: t()
  def solarized_dark_theme do
    base = %__MODULE__{
      name: "solarized-dark",
      dark: true,
      primary: {38, 139, 210},
      secondary: {42, 161, 152},
      accent: {181, 137, 0},
      warning: {203, 75, 22},
      error: {220, 50, 47},
      success: {133, 153, 0},
      background: {0, 43, 54},
      foreground: {131, 148, 150},
      surface: {7, 54, 66},
      panel: {7, 54, 66},
      border: {88, 110, 117},
      text_primary: {131, 148, 150},
      text_secondary: {147, 161, 161},
      text_muted: {88, 110, 117},
      text_disabled: {88, 110, 117},
      text_accent: {181, 137, 0},
      text_warning: {203, 75, 22},
      text_error: {220, 50, 47},
      text_success: {133, 153, 0},
      primary_muted: {19, 70, 105},
      secondary_muted: {21, 81, 76},
      accent_muted: {91, 69, 0},
      warning_muted: {102, 38, 11},
      error_muted: {110, 25, 24},
      success_muted: {67, 77, 0},
      cursor: %{
        block_cursor: {38, 139, 210},
        block_cursor_foreground: {253, 246, 227},
        block_cursor_blurred: {19, 70, 105}
      },
      block_hover: {7, 54, 66}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"solarized-light"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.solarized_light_theme().name
      "solarized-light"

  """
  @spec solarized_light_theme() :: t()
  def solarized_light_theme do
    base = %__MODULE__{
      name: "solarized-light",
      dark: false,
      primary: {38, 139, 210},
      secondary: {42, 161, 152},
      accent: {181, 137, 0},
      warning: {203, 75, 22},
      error: {220, 50, 47},
      success: {133, 153, 0},
      background: {253, 246, 227},
      foreground: {101, 123, 131},
      surface: {238, 232, 213},
      panel: {238, 232, 213},
      border: {147, 161, 161},
      text_primary: {101, 123, 131},
      text_secondary: {88, 110, 117},
      text_muted: {147, 161, 161},
      text_disabled: {147, 161, 161},
      text_accent: {181, 137, 0},
      text_warning: {203, 75, 22},
      text_error: {220, 50, 47},
      text_success: {133, 153, 0},
      primary_muted: {198, 220, 235},
      secondary_muted: {200, 228, 225},
      accent_muted: {235, 220, 179},
      warning_muted: {240, 195, 180},
      error_muted: {245, 190, 188},
      success_muted: {218, 225, 179},
      cursor: %{
        block_cursor: {38, 139, 210},
        block_cursor_foreground: {253, 246, 227},
        block_cursor_blurred: {198, 220, 235}
      },
      block_hover: {238, 232, 213}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"monokai"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.monokai_theme().name
      "monokai"

  """
  @spec monokai_theme() :: t()
  def monokai_theme do
    base = %__MODULE__{
      name: "monokai",
      dark: true,
      primary: {174, 129, 255},
      secondary: {249, 38, 114},
      accent: {102, 217, 239},
      warning: {253, 151, 31},
      error: {249, 38, 114},
      success: {166, 226, 46},
      background: {39, 40, 34},
      foreground: {214, 214, 214},
      surface: {46, 46, 46},
      panel: {62, 61, 50},
      border: {117, 113, 94},
      text_primary: {248, 248, 242},
      text_secondary: {214, 214, 214},
      text_muted: {121, 121, 121},
      text_disabled: {80, 80, 80},
      text_accent: {102, 217, 239},
      text_warning: {253, 151, 31},
      text_error: {249, 38, 114},
      text_success: {166, 226, 46},
      primary_muted: {87, 65, 128},
      secondary_muted: {125, 19, 57},
      accent_muted: {51, 109, 120},
      warning_muted: {127, 76, 16},
      error_muted: {125, 19, 57},
      success_muted: {83, 113, 23},
      cursor: %{
        block_cursor: {174, 129, 255},
        block_cursor_foreground: {39, 40, 34},
        block_cursor_blurred: {87, 65, 128}
      },
      block_hover: {50, 50, 44}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"gruvbox-dark"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.gruvbox_dark_theme().name
      "gruvbox-dark"

  """
  @spec gruvbox_dark_theme() :: t()
  def gruvbox_dark_theme do
    base = %__MODULE__{
      name: "gruvbox-dark",
      dark: true,
      primary: {131, 165, 152},
      secondary: {211, 134, 155},
      accent: {250, 189, 47},
      warning: {254, 128, 25},
      error: {251, 73, 52},
      success: {184, 187, 38},
      background: {40, 40, 40},
      foreground: {235, 219, 178},
      surface: {60, 56, 54},
      panel: {80, 73, 69},
      border: {146, 131, 116},
      text_primary: {235, 219, 178},
      text_secondary: {213, 196, 161},
      text_muted: {146, 131, 116},
      text_disabled: {102, 92, 84},
      text_accent: {250, 189, 47},
      text_warning: {254, 128, 25},
      text_error: {251, 73, 52},
      text_success: {184, 187, 38},
      primary_muted: {66, 83, 76},
      secondary_muted: {106, 67, 78},
      accent_muted: {125, 95, 24},
      warning_muted: {127, 64, 13},
      error_muted: {126, 37, 26},
      success_muted: {92, 94, 19},
      cursor: %{
        block_cursor: {131, 165, 152},
        block_cursor_foreground: {40, 40, 40},
        block_cursor_blurred: {66, 83, 76}
      },
      block_hover: {60, 56, 54}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"gruvbox-light"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.gruvbox_light_theme().name
      "gruvbox-light"

  """
  @spec gruvbox_light_theme() :: t()
  def gruvbox_light_theme do
    base = %__MODULE__{
      name: "gruvbox-light",
      dark: false,
      primary: {7, 102, 120},
      secondary: {143, 63, 113},
      accent: {181, 118, 20},
      warning: {175, 58, 3},
      error: {157, 0, 6},
      success: {121, 116, 14},
      background: {251, 241, 199},
      foreground: {60, 56, 54},
      surface: {235, 219, 178},
      panel: {213, 196, 161},
      border: {189, 174, 147},
      text_primary: {60, 56, 54},
      text_secondary: {80, 73, 69},
      text_muted: {124, 111, 100},
      text_disabled: {168, 153, 132},
      text_accent: {181, 118, 20},
      text_warning: {175, 58, 3},
      text_error: {157, 0, 6},
      text_success: {121, 116, 14},
      primary_muted: {198, 226, 231},
      secondary_muted: {227, 198, 219},
      accent_muted: {235, 218, 188},
      warning_muted: {235, 198, 180},
      error_muted: {230, 179, 180},
      success_muted: {218, 217, 186},
      cursor: %{
        block_cursor: {7, 102, 120},
        block_cursor_foreground: {251, 241, 199},
        block_cursor_blurred: {198, 226, 231}
      },
      block_hover: {235, 219, 178}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"tokyo-night"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.tokyo_night_theme().name
      "tokyo-night"

  """
  @spec tokyo_night_theme() :: t()
  def tokyo_night_theme do
    base = %__MODULE__{
      name: "tokyo-night",
      dark: true,
      primary: {187, 154, 247},
      secondary: {122, 162, 247},
      accent: {255, 158, 100},
      warning: {224, 175, 104},
      error: {247, 118, 142},
      success: {158, 206, 106},
      background: {26, 27, 38},
      foreground: {192, 202, 245},
      surface: {36, 40, 59},
      panel: {65, 72, 104},
      border: {59, 66, 97},
      text_primary: {192, 202, 245},
      text_secondary: {169, 177, 214},
      text_muted: {86, 95, 137},
      text_disabled: {65, 72, 104},
      text_accent: {255, 158, 100},
      text_warning: {224, 175, 104},
      text_error: {247, 118, 142},
      text_success: {158, 206, 106},
      primary_muted: {94, 77, 124},
      secondary_muted: {61, 81, 124},
      accent_muted: {128, 79, 50},
      warning_muted: {112, 88, 52},
      error_muted: {124, 59, 71},
      success_muted: {79, 103, 53},
      cursor: %{
        block_cursor: {187, 154, 247},
        block_cursor_foreground: {26, 27, 38},
        block_cursor_blurred: {94, 77, 124}
      },
      block_hover: {41, 46, 66}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"catppuccin-mocha"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.catppuccin_mocha_theme().name
      "catppuccin-mocha"

  """
  @spec catppuccin_mocha_theme() :: t()
  def catppuccin_mocha_theme do
    base = %__MODULE__{
      name: "catppuccin-mocha",
      dark: true,
      primary: {245, 194, 231},
      secondary: {203, 166, 247},
      accent: {250, 179, 135},
      warning: {249, 226, 175},
      error: {243, 139, 168},
      success: {166, 227, 161},
      background: {24, 24, 37},
      foreground: {205, 214, 244},
      surface: {49, 50, 68},
      panel: {69, 71, 90},
      border: {88, 91, 112},
      text_primary: {205, 214, 244},
      text_secondary: {186, 194, 222},
      text_muted: {147, 153, 178},
      text_disabled: {88, 91, 112},
      text_accent: {250, 179, 135},
      text_warning: {249, 226, 175},
      text_error: {243, 139, 168},
      text_success: {166, 227, 161},
      primary_muted: {123, 97, 116},
      secondary_muted: {102, 83, 124},
      accent_muted: {125, 90, 68},
      warning_muted: {125, 113, 88},
      error_muted: {122, 70, 84},
      success_muted: {83, 114, 81},
      cursor: %{
        block_cursor: {245, 194, 231},
        block_cursor_foreground: {24, 24, 37},
        block_cursor_blurred: {123, 97, 116}
      },
      block_hover: {49, 50, 68}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"classic"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.classic_theme().name
      "classic"

  """
  @spec classic_theme() :: t()
  def classic_theme do
    base = %__MODULE__{
      name: "classic",
      dark: true,
      primary: {0, 175, 215},
      secondary: {0, 135, 175},
      accent: {215, 175, 0},
      warning: {215, 135, 0},
      error: {215, 0, 0},
      success: {0, 175, 0},
      background: {8, 8, 8},
      foreground: {215, 215, 215},
      surface: {18, 18, 18},
      panel: {28, 28, 28},
      border: {0, 175, 215},
      text_primary: {215, 215, 215},
      text_secondary: {175, 175, 175},
      text_muted: {0, 175, 215},
      text_disabled: {95, 95, 95},
      text_accent: {215, 175, 0},
      text_warning: {215, 135, 0},
      text_error: {215, 0, 0},
      text_success: {0, 175, 0},
      primary_muted: {0, 95, 135},
      secondary_muted: {0, 68, 95},
      accent_muted: {135, 110, 0},
      warning_muted: {135, 68, 0},
      error_muted: {135, 0, 0},
      success_muted: {0, 95, 0},
      cursor: %{
        block_cursor: {0, 175, 215},
        block_cursor_foreground: {8, 8, 8},
        block_cursor_blurred: {0, 95, 135}
      },
      block_hover: {28, 28, 48}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in `"retro"` theme, with its syntax map filled in from
  `default_syntax_colors/1`.

  ## Examples

      iex> Drafter.Theme.retro_theme().name
      "retro"

  """
  @spec retro_theme() :: t()
  def retro_theme do
    base = %__MODULE__{
      name: "retro",
      dark: true,
      primary: {255, 176, 0},
      secondary: {215, 135, 0},
      accent: {0, 215, 95},
      warning: {215, 135, 0},
      error: {255, 80, 0},
      success: {0, 215, 95},
      background: {10, 6, 0},
      foreground: {255, 200, 80},
      surface: {20, 12, 0},
      panel: {30, 18, 0},
      border: {215, 135, 0},
      text_primary: {255, 200, 80},
      text_secondary: {215, 155, 40},
      text_muted: {175, 115, 0},
      text_disabled: {95, 68, 0},
      text_accent: {0, 215, 95},
      text_warning: {215, 135, 0},
      text_error: {255, 80, 0},
      text_success: {0, 215, 95},
      primary_muted: {135, 95, 0},
      secondary_muted: {95, 68, 0},
      accent_muted: {0, 135, 60},
      warning_muted: {135, 68, 0},
      error_muted: {135, 40, 0},
      success_muted: {0, 135, 60},
      cursor: %{
        block_cursor: {255, 176, 0},
        block_cursor_foreground: {10, 6, 0},
        block_cursor_blurred: {135, 95, 0}
      },
      block_hover: {30, 20, 0}
    }

    %{base | syntax: default_syntax_colors(base)}
  end

  @doc """
  The built-in theme called `name`, or `nil` when there is no such theme.

  ## Examples

      iex> Drafter.Theme.get_theme("nord").dark
      true

      iex> Drafter.Theme.get_theme("no-such-theme")
      nil

  """
  @spec get_theme(String.t()) :: t() | nil
  def get_theme(name) do
    Map.get(available_themes(), name)
  end

  @doc """
  Look a colour up on a theme by slot name.

  `{:syntax, key}` reads the theme's syntax map. A plain atom reads the struct field
  of that name and, when that field is `nil`, falls back to the theme's `:cursor`
  map — so `:block_cursor` and friends resolve without naming the map. Returns `nil`
  when neither carries the name. Any struct field is reachable this way, including
  the non-colour `:name` and `:dark`.

  ## Examples

      iex> Drafter.Theme.get_color(Drafter.Theme.nord_theme(), :primary)
      {136, 192, 208}

      iex> Drafter.Theme.get_color(Drafter.Theme.nord_theme(), {:syntax, :no_such_token})
      nil

      iex> Drafter.Theme.get_color(Drafter.Theme.nord_theme(), :no_such_slot)
      nil

  """
  @spec get_color(t(), {:syntax, atom()} | atom()) :: term() | nil
  def get_color(theme, {:syntax, key}) do
    Map.get(theme.syntax || %{}, key)
  end

  def get_color(theme, color_name) do
    case Map.get(theme, color_name) do
      nil -> theme |> Map.get(:cursor, %{}) |> Map.get(color_name)
      value -> value
    end
  end
end
