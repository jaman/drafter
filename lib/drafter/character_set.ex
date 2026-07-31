defmodule Drafter.CharacterSet do
  @moduledoc """
  Named character lookup for TUI rendering.

  Provides a single authoritative source for every Unicode/ASCII character
  used across Drafter widgets. Characters are grouped by purpose and keyed
  by skin name so that calling code can switch between graphical and
  wireframe rendering without embedding strings directly.

  ## Usage

      import Drafter.CharacterSet

      # Current-skin lookup (respects SkinManager)
      fill(:full)          # "█" in :graphical / :wireframe
      sparkline_levels()   # ["▁".."█"] in :graphical, ["1".."8"] in :ascii

      # Explicit skin override
      fill(:full, :wireframe)
      box(:h_line, :wireframe)

  ## Built-in skins

  | Skin | Description |
  |------|-------------|
  | `:graphical` | Unicode block + braille characters (default) |
  | `:wireframe` | Unicode box-drawing, block fill, minimal decoration |
  | `:ascii` | 7-bit ASCII only — maximum compatibility |
  """

  @graphical %{
    style: %{border: :rounded, padding: 1, preferred_theme: "textual-dark"},
    fill: %{
      full: "█",
      seven_eights: "▉",
      three_quarter: "▊",
      five_eights: "▋",
      half: "▌",
      three_eights: "▍",
      quarter: "▎",
      one_eighth: "▏",
      empty: "░",
      medium: "▒",
      dark: "▓",
      lower_half: "▄",
      upper_half: "▀",
      left_half: "▌",
      right_half: "▐"
    },
    box: %{
      h_line: "─",
      v_line: "│",
      tl: "┌",
      tr: "┐",
      bl: "└",
      br: "┘",
      cross: "┼",
      t_down: "┬",
      t_up: "┴",
      t_right: "├",
      t_left: "┤",
      h_bold: "━",
      v_bold: "┃",
      tl_bold: "┏",
      tr_bold: "┓",
      bl_bold: "┗",
      br_bold: "┛",
      h_double: "═",
      v_double: "║",
      tl_double: "╔",
      tr_double: "╗",
      bl_double: "╚",
      br_double: "╝",
      h_dashed: "╌",
      v_dashed: "╎"
    },
    arrow: %{
      up: "▲",
      down: "▼",
      left: "◀",
      right: "▶",
      up_small: "↑",
      down_small: "↓",
      left_small: "←",
      right_small: "→",
      up_down: "↕",
      left_right: "↔",
      expand: "▼",
      collapse: "▶"
    },
    indicator: %{
      radio_on: "●",
      radio_off: "○",
      check_on: "✓",
      check_off: " ",
      bullet: "•",
      dot: "·",
      diamond_on: "◆",
      diamond_off: "◇",
      circle: "◉"
    },
    scroll: %{
      thumb: "█",
      track: "░",
      thumb_drag: "▓",
      thumb_hover: "▒"
    },
    sparkline: %{
      levels_v: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],
      levels_h: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
    },
    spinner: %{
      dots: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
      braille: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
      line: ["|", "/", "-", "\\"],
      points: ["•", "·", "•", "·", "•"]
    }
  }

  @wireframe %{
    style: %{border: :single, padding: 0, preferred_theme: "textual-dark"},
    fill: %{
      full: "█",
      seven_eights: "█",
      three_quarter: "█",
      five_eights: "█",
      half: "▌",
      three_eights: "▌",
      quarter: "░",
      one_eighth: "░",
      empty: "░",
      medium: "▒",
      dark: "▓",
      lower_half: "▄",
      upper_half: "▀",
      left_half: "▌",
      right_half: "▐"
    },
    box: %{
      h_line: "─",
      v_line: "│",
      tl: "┌",
      tr: "┐",
      bl: "└",
      br: "┘",
      cross: "┼",
      t_down: "┬",
      t_up: "┴",
      t_right: "├",
      t_left: "┤",
      h_bold: "─",
      v_bold: "│",
      tl_bold: "┌",
      tr_bold: "┐",
      bl_bold: "└",
      br_bold: "┘",
      h_double: "═",
      v_double: "║",
      tl_double: "╔",
      tr_double: "╗",
      bl_double: "╚",
      br_double: "╝",
      h_dashed: "-",
      v_dashed: ":"
    },
    arrow: %{
      up: "^",
      down: "v",
      left: "<",
      right: ">",
      up_small: "^",
      down_small: "v",
      left_small: "<",
      right_small: ">",
      up_down: "|",
      left_right: "-",
      expand: "v",
      collapse: ">"
    },
    indicator: %{
      radio_on: "(x)",
      radio_off: "( )",
      check_on: "[x]",
      check_off: "[ ]",
      bullet: "-",
      dot: ".",
      diamond_on: "#",
      diamond_off: "+",
      circle: "o"
    },
    scroll: %{
      thumb: "█",
      track: "|",
      thumb_drag: "▓",
      thumb_hover: "▒"
    },
    sparkline: %{
      levels_v: ["1", "2", "3", "4", "5", "6", "7", "8"],
      levels_h: [" ", "1", "2", "3", "4", "5", "6", "7", "8"]
    },
    spinner: %{
      dots: ["|", "/", "-", "\\", "|", "/", "-", "\\", "|", "\\"],
      braille: ["|", "/", "-", "\\"],
      line: ["|", "/", "-", "\\"],
      points: [".", "o", "O", "o", "."]
    }
  }

  @ascii %{
    style: %{border: :ascii, padding: 0, preferred_theme: "textual-dark"},
    fill: %{
      full: "#",
      seven_eights: "#",
      three_quarter: "#",
      five_eights: "#",
      half: "+",
      three_eights: "+",
      quarter: ".",
      one_eighth: ".",
      empty: ".",
      medium: "+",
      dark: "#",
      lower_half: "_",
      upper_half: "\"",
      left_half: "|",
      right_half: "|"
    },
    box: %{
      h_line: "-",
      v_line: "|",
      tl: "+",
      tr: "+",
      bl: "+",
      br: "+",
      cross: "+",
      t_down: "+",
      t_up: "+",
      t_right: "+",
      t_left: "+",
      h_bold: "=",
      v_bold: "|",
      tl_bold: "+",
      tr_bold: "+",
      bl_bold: "+",
      br_bold: "+",
      h_double: "=",
      v_double: "|",
      tl_double: "+",
      tr_double: "+",
      bl_double: "+",
      br_double: "+",
      h_dashed: "-",
      v_dashed: ":"
    },
    arrow: %{
      up: "^",
      down: "v",
      left: "<",
      right: ">",
      up_small: "^",
      down_small: "v",
      left_small: "<",
      right_small: ">",
      up_down: "|",
      left_right: "-",
      expand: "v",
      collapse: ">"
    },
    indicator: %{
      radio_on: "(x)",
      radio_off: "( )",
      check_on: "[x]",
      check_off: "[ ]",
      bullet: "-",
      dot: ".",
      diamond_on: "#",
      diamond_off: "+",
      circle: "o"
    },
    scroll: %{
      thumb: "#",
      track: ".",
      thumb_drag: "X",
      thumb_hover: "*"
    },
    sparkline: %{
      levels_v: ["1", "2", "3", "4", "5", "6", "7", "8"],
      levels_h: [" ", "1", "2", "3", "4", "5", "6", "7", "8"]
    },
    spinner: %{
      dots: ["|", "/", "-", "\\", "|", "/", "-", "\\", "|", "\\"],
      braille: ["|", "/", "-", "\\"],
      line: ["|", "/", "-", "\\"],
      points: [".", "o", "O", "o", "."]
    }
  }

  @classic %{
    style: %{border: :single, padding: 0, preferred_theme: "classic"},
    fill: %{
      full: "█",
      seven_eights: "▉",
      three_quarter: "▊",
      five_eights: "▋",
      half: "▌",
      three_eights: "▍",
      quarter: "▎",
      one_eighth: "▏",
      empty: "░",
      medium: "▒",
      dark: "▓",
      lower_half: "▄",
      upper_half: "▀",
      left_half: "▌",
      right_half: "▐"
    },
    box: %{
      h_line: "─",
      v_line: "│",
      tl: "┌",
      tr: "┐",
      bl: "└",
      br: "┘",
      cross: "┼",
      t_down: "┬",
      t_up: "┴",
      t_right: "├",
      t_left: "┤",
      h_bold: "━",
      v_bold: "┃",
      tl_bold: "┏",
      tr_bold: "┓",
      bl_bold: "┗",
      br_bold: "┛",
      h_double: "═",
      v_double: "║",
      tl_double: "╔",
      tr_double: "╗",
      bl_double: "╚",
      br_double: "╝",
      h_dashed: "╌",
      v_dashed: "╎"
    },
    arrow: %{
      up: "▲",
      down: "▼",
      left: "◀",
      right: "▶",
      up_small: "↑",
      down_small: "↓",
      left_small: "←",
      right_small: "→",
      up_down: "↕",
      left_right: "↔",
      expand: "▼",
      collapse: "▶"
    },
    indicator: %{
      radio_on: "●",
      radio_off: "○",
      check_on: "✓",
      check_off: " ",
      bullet: "•",
      dot: "·",
      diamond_on: "◆",
      diamond_off: "◇",
      circle: "◉"
    },
    scroll: %{
      thumb: "█",
      track: "░",
      thumb_drag: "▓",
      thumb_hover: "▒"
    },
    sparkline: %{
      levels_v: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],
      levels_h: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
    },
    spinner: %{
      dots: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
      braille: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
      line: ["|", "/", "-", "\\"],
      points: ["•", "·", "•", "·", "•"]
    }
  }

  @retro %{
    style: %{border: :double, padding: 0, preferred_theme: "retro"},
    fill: %{
      full: "█",
      seven_eights: "▉",
      three_quarter: "▊",
      five_eights: "▋",
      half: "▌",
      three_eights: "▍",
      quarter: "▎",
      one_eighth: "▏",
      empty: "░",
      medium: "▒",
      dark: "▓",
      lower_half: "▄",
      upper_half: "▀",
      left_half: "▌",
      right_half: "▐"
    },
    box: %{
      h_line: "═",
      v_line: "║",
      tl: "╔",
      tr: "╗",
      bl: "╚",
      br: "╝",
      cross: "╬",
      t_down: "╦",
      t_up: "╩",
      t_right: "╠",
      t_left: "╣",
      h_bold: "═",
      v_bold: "║",
      tl_bold: "╔",
      tr_bold: "╗",
      bl_bold: "╚",
      br_bold: "╝",
      h_double: "═",
      v_double: "║",
      tl_double: "╔",
      tr_double: "╗",
      bl_double: "╚",
      br_double: "╝",
      h_dashed: "─",
      v_dashed: "│"
    },
    arrow: %{
      up: "▲",
      down: "▼",
      left: "◀",
      right: "▶",
      up_small: "↑",
      down_small: "↓",
      left_small: "←",
      right_small: "→",
      up_down: "↕",
      left_right: "↔",
      expand: "▼",
      collapse: "▶"
    },
    indicator: %{
      radio_on: "●",
      radio_off: "○",
      check_on: "✓",
      check_off: " ",
      bullet: "•",
      dot: "·",
      diamond_on: "◆",
      diamond_off: "◇",
      circle: "◉"
    },
    scroll: %{
      thumb: "█",
      track: "░",
      thumb_drag: "▓",
      thumb_hover: "▒"
    },
    sparkline: %{
      levels_v: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],
      levels_h: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
    },
    spinner: %{
      dots: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
      braille: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
      line: ["|", "/", "-", "\\"],
      points: ["•", "·", "•", "·", "•"]
    }
  }

  @skins %{
    graphical: @graphical,
    wireframe: @wireframe,
    ascii: @ascii,
    classic: @classic,
    retro: @retro
  }

  @doc "Returns the full style preferences map for the current skin."
  @spec style() :: map()
  def style,
    do:
      get_in(@skins, [current_skin(), :style]) ||
        %{border: :rounded, padding: 1, preferred_theme: "textual-dark"}

  @doc "Returns a single style preference key for the current skin."
  @spec style(atom()) :: term()
  def style(key), do: Map.get(style(), key)

  @doc "Returns the preferred theme name for the current skin."
  @spec preferred_theme() :: String.t()
  def preferred_theme, do: style(:preferred_theme) || "textual-dark"

  @doc "Returns the preferred theme name for the given skin atom."
  @spec preferred_theme(atom()) :: String.t()
  def preferred_theme(skin),
    do: get_in(@skins, [skin, :style, :preferred_theme]) || "textual-dark"

  @doc "Look up a fill character for the current skin."
  @spec fill(atom()) :: String.t()
  def fill(key), do: fill(key, current_skin())

  @doc "Look up a fill character for the given skin."
  @spec fill(atom(), atom()) :: String.t()
  def fill(key, skin), do: get_in(@skins, [skin, :fill, key]) || "?"

  @doc "Look up a box-drawing character for the current skin."
  @spec box(atom()) :: String.t()
  def box(key), do: box(key, current_skin())

  @doc "Look up a box-drawing character for the given skin."
  @spec box(atom(), atom()) :: String.t()
  def box(key, skin), do: get_in(@skins, [skin, :box, key]) || "?"

  @doc "Look up an arrow character for the current skin."
  @spec arrow(atom()) :: String.t()
  def arrow(key), do: arrow(key, current_skin())

  @doc "Look up an arrow character for the given skin."
  @spec arrow(atom(), atom()) :: String.t()
  def arrow(key, skin), do: get_in(@skins, [skin, :arrow, key]) || "?"

  @doc "Look up an indicator character for the current skin."
  @spec indicator(atom()) :: String.t()
  def indicator(key), do: indicator(key, current_skin())

  @doc "Look up an indicator character for the given skin."
  @spec indicator(atom(), atom()) :: String.t()
  def indicator(key, skin), do: get_in(@skins, [skin, :indicator, key]) || "?"

  @doc "Look up a scrollbar character for the current skin."
  @spec scroll(atom()) :: String.t()
  def scroll(key), do: scroll(key, current_skin())

  @doc "Look up a scrollbar character for the given skin."
  @spec scroll(atom(), atom()) :: String.t()
  def scroll(key, skin), do: get_in(@skins, [skin, :scroll, key]) || "?"

  @doc "Returns the vertical sparkline level list for the current skin."
  @spec sparkline_levels_v() :: [String.t()]
  def sparkline_levels_v, do: sparkline_levels_v(current_skin())

  @doc "Returns the vertical sparkline level list for the given skin."
  @spec sparkline_levels_v(atom()) :: [String.t()]
  def sparkline_levels_v(skin), do: get_in(@skins, [skin, :sparkline, :levels_v]) || []

  @doc "Returns the horizontal sparkline level list for the current skin."
  @spec sparkline_levels_h() :: [String.t()]
  def sparkline_levels_h, do: sparkline_levels_h(current_skin())

  @doc "Returns the horizontal sparkline level list for the given skin."
  @spec sparkline_levels_h(atom()) :: [String.t()]
  def sparkline_levels_h(skin), do: get_in(@skins, [skin, :sparkline, :levels_h]) || []

  @doc "Returns the spinner frame list for a given style and current skin."
  @spec spinner(atom()) :: [String.t()]
  def spinner(style \\ :dots), do: spinner(style, current_skin())

  @doc "Returns the spinner frame list for a given style and skin."
  @spec spinner(atom(), atom()) :: [String.t()]
  def spinner(style, skin), do: get_in(@skins, [skin, :spinner, style]) || ["|"]

  @doc "Returns all characters for a group in the current skin."
  @spec group(atom()) :: map()
  def group(key), do: group(key, current_skin())

  @doc "Returns all characters for a group in the given skin."
  @spec group(atom(), atom()) :: map()
  def group(key, skin), do: get_in(@skins, [skin, key]) || %{}

  @doc "Returns the list of registered skin names."
  @spec skins() :: [atom()]
  def skins, do: Map.keys(@skins)

  defp current_skin do
    case Process.get(:drafter_skin) do
      nil -> Drafter.SkinManager.get_current_skin()
      skin -> skin
    end
  end
end
