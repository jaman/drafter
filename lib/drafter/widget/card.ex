defmodule Drafter.Widget.Card do
  @moduledoc """
  Renders a bordered panel with an optional title and text content lines.

  Four border styles are available: `:single`, `:double`, `:rounded` (default),
  and `:heavy`. When a `:title` is provided it is embedded into the top border
  left-aligned with one padding character on either side. Content lines are
  padded and truncated to fit the inner width.

  ## Options

    * `:title` - string shown in the top border (optional)
    * `:content` - list of strings, one per inner line (default `[]`)
    * `:border` - border style atom: `:rounded` (default), `:single`, `:double`, `:heavy`
    * `:border_color` - `{r, g, b}` tuple for border characters
    * `:color` - `{r, g, b}` tuple for content text
    * `:background` - `{r, g, b}` tuple for the card background
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      card(title: "Summary", content: ["Line 1", "Line 2"], border: :rounded)
      card(title: "Alert", content: ["Disk full"], border_color: {255, 80, 80})
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @border_chars %{
    single: %{tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│"},
    double: %{tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║"},
    rounded: %{tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│"},
    heavy: %{tl: "┏", tr: "┓", bl: "┗", br: "┛", h: "━", v: "┃"}
  }

  defstruct [
    :title,
    :content,
    :border,
    :style,
    :border_color,
    :background,
    :color,
    :classes,
    :app_module
  ]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      title: Map.get(props, :title),
      content: Map.get(props, :content, []),
      border: Map.get(props, :border, :rounded),
      style: Map.get(props, :style, %{}),
      border_color: Map.get(props, :border_color),
      background: Map.get(props, :background),
      color: Map.get(props, :color),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    render_card(state, rect)
  end

  defp render_card(state, rect) do
    computed = Computed.for_widget(:card, state, classes: state.classes, style: state.style)

    bg = state.background || computed[:background] || {40, 44, 52}
    fg = state.color || computed[:color] || {200, 200, 200}
    border_fg = state.border_color || computed[:border_color] || fg

    content_style = %{fg: fg, bg: bg}
    border_style = %{fg: border_fg, bg: bg}
    title_style = %{fg: border_fg, bg: bg, bold: true}

    chars = Map.get(@border_chars, state.border, @border_chars[:rounded])
    inner_width = rect.width - 2

    content_lines = state.content || []
    content_lines = if is_list(content_lines), do: content_lines, else: [content_lines]

    [render_top_border(chars, inner_width, state.title, border_style, title_style)] ++
      render_content_lines(chars, inner_width, content_lines, content_style, border_style) ++
      [render_bottom_border(chars, inner_width, border_style)]
  end

  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | title: Map.get(props, :title, state.title),
        content: Map.get(props, :content, state.content),
        style: Map.get(props, :style, state.style),
        border_color: Map.get(props, :border_color, state.border_color),
        background: Map.get(props, :background, state.background),
        color: Map.get(props, :color, state.color),
        classes: Map.get(props, :classes, state.classes)
    }
  end

  @impl Drafter.Widget
  def handle_event(_event, state), do: {:noreply, state}

  defp render_top_border(chars, inner_width, nil, border_style, _title_style) do
    segments = [
      Segment.new(chars.tl, border_style),
      Segment.new(String.duplicate(chars.h, inner_width), border_style),
      Segment.new(chars.tr, border_style)
    ]

    Strip.new(segments)
  end

  defp render_top_border(chars, inner_width, title, border_style, title_style)
       when is_binary(title) do
    title_text = " #{title} "
    title_len = String.length(title_text)

    if title_len >= inner_width do
      segments = [
        Segment.new(chars.tl, border_style),
        Segment.new(String.duplicate(chars.h, inner_width), border_style),
        Segment.new(chars.tr, border_style)
      ]

      Strip.new(segments)
    else
      left_len = 1
      right_len = inner_width - title_len - left_len

      segments = [
        Segment.new(chars.tl, border_style),
        Segment.new(String.duplicate(chars.h, max(0, left_len)), border_style),
        Segment.new(title_text, title_style),
        Segment.new(String.duplicate(chars.h, max(0, right_len)), border_style),
        Segment.new(chars.tr, border_style)
      ]

      Strip.new(segments)
    end
  end

  defp render_bottom_border(chars, inner_width, border_style) do
    segments = [
      Segment.new(chars.bl, border_style),
      Segment.new(String.duplicate(chars.h, inner_width), border_style),
      Segment.new(chars.br, border_style)
    ]

    Strip.new(segments)
  end

  defp render_content_lines(chars, inner_width, content_lines, content_style, border_style) do
    Enum.map(content_lines, fn line ->
      text = to_string(line)
      padded = String.pad_trailing(text, inner_width)
      padded = String.slice(padded, 0, inner_width)

      segments = [
        Segment.new(chars.v, border_style),
        Segment.new(padded, content_style),
        Segment.new(chars.v, border_style)
      ]

      Strip.new(segments)
    end)
  end
end
