defmodule Drafter.Prompt.Style do
  @moduledoc """
  The colours and symbols prompts are drawn with.

  `current/1` reads the colours from the active `Drafter.Theme` and the symbols from
  the active skin: `:ascii` gives 7-bit symbols, every other skin gives Unicode ones.
  Colours are left out when the `NO_COLOR` environment variable is set to anything
  but the empty string.

      style = Drafter.Prompt.Style.current()
      Drafter.Prompt.Style.segment(style, :accent, "?")

  ## Roles

  `segment/3` styles text by role: `:plain`, `:strong`, `:accent`, `:success`,
  `:error`, `:warning` and `:muted`.

  ## Symbols

  `symbol/2` looks up `:question`, `:done`, `:failed`, `:pointer`, `:on`, `:off`,
  `:prompt`, `:separator`, `:info`, `:warning`, `:bar_full` and `:bar_empty`.
  `spinner/2` gives the spinner's symbol for a tick count.
  """

  alias Drafter.Draw.Segment
  alias Drafter.Session.Context
  alias Drafter.{SkinManager, Theme, ThemeManager}

  defstruct [:accent, :success, :error, :warning, :muted, :symbols, :spinner, color: true]

  @type role :: :plain | :strong | :accent | :success | :error | :warning | :muted
  @type t :: %__MODULE__{
          accent: Segment.color(),
          success: Segment.color(),
          error: Segment.color(),
          warning: Segment.color(),
          muted: Segment.color(),
          symbols: %{atom() => String.t()},
          spinner: [String.t()],
          color: boolean()
        }

  @unicode %{
    question: "?",
    done: "✔",
    failed: "✖",
    pointer: "❯",
    on: "◉",
    off: "◯",
    prompt: "›",
    separator: "·",
    info: "ℹ",
    warning: "▲",
    bar_full: "█",
    bar_empty: "░"
  }

  @ascii %{
    question: "?",
    done: "+",
    failed: "x",
    pointer: ">",
    on: "[x]",
    off: "[ ]",
    prompt: ">",
    separator: "-",
    info: "i",
    warning: "!",
    bar_full: "#",
    bar_empty: "-"
  }

  @unicode_spinner ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  @ascii_spinner ~w(| / - \\)

  @doc """
  The style for the calling process.

  `overrides` replaces fields of the result: `:accent`, `:success`, `:error`,
  `:warning` and `:muted` take `{r, g, b}` colours, `:symbols` a map merged over the
  built-in symbols, `:spinner` a list of symbols, and `:color` a boolean.
  """
  @spec current(keyword()) :: t()
  def current(overrides \\ []) do
    theme = theme()
    ascii? = SkinManager.get_current_skin() == :ascii
    {symbols, overrides} = Keyword.pop(overrides, :symbols, %{})

    base = %__MODULE__{
      accent: theme.primary,
      success: theme.success,
      error: theme.error,
      warning: theme.warning,
      muted: theme.text_muted,
      symbols: Map.merge(if(ascii?, do: @ascii, else: @unicode), symbols),
      spinner: if(ascii?, do: @ascii_spinner, else: @unicode_spinner),
      color: System.get_env("NO_COLOR") in [nil, ""]
    }

    struct!(base, overrides)
  end

  @doc "`text` styled for `role`."
  @spec segment(t(), role(), String.t()) :: Segment.t()
  def segment(_style, :plain, text), do: Segment.new(text)
  def segment(_style, :strong, text), do: Segment.new(text, %{bold: true})
  def segment(%__MODULE__{color: false}, :muted, text), do: Segment.new(text, %{dim: true})
  def segment(%__MODULE__{color: false}, :accent, text), do: Segment.new(text, %{bold: true})
  def segment(%__MODULE__{color: false}, _role, text), do: Segment.new(text)

  def segment(%__MODULE__{} = style, role, text),
    do: Segment.new(text, %{fg: Map.fetch!(style, role)})

  @doc "The symbol named `name`."
  @spec symbol(t(), atom()) :: String.t()
  def symbol(%__MODULE__{symbols: symbols}, name), do: Map.fetch!(symbols, name)

  @doc "The spinner's symbol at `tick`, cycling through the spinner's symbols."
  @spec spinner(t(), non_neg_integer()) :: String.t()
  def spinner(%__MODULE__{spinner: frames}, tick), do: Enum.at(frames, rem(tick, length(frames)))

  defp theme do
    case Context.get(:theme_manager) do
      nil -> Theme.dark_theme()
      _manager -> ThemeManager.get_current_theme()
    end
  end
end
