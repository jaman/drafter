defmodule Drafter.Widget.Card do
  @moduledoc """
  Renders a bordered panel with an optional title and text content lines.

  Four border styles are available: `:single`, `:double`, `:rounded` (default),
  and `:heavy`. When a `:title` is provided it is embedded into the top border
  left-aligned with one padding character on either side. Content lines are
  padded and truncated to fit the inner width.

  ## Component tag

  This module has no `component_tag/0` and is not reached through the widget
  registry. `Drafter.App` builds it as the element `{:card, children, opts}`:

      card(children, opts)

  `children` is the content: the renderer wraps it in a list and calls
  `to_string/1` on each entry, so every entry must implement `String.Chars`.
  Pass strings. The remaining props come from `opts`.

  ## Options

    * `:title` - `t:String.t/0` shown in the top border. Default `nil`. A title
      whose padded length reaches the inner width is dropped and a plain border is
      drawn instead
    * `:content` - list of strings, one per inner line. Default `[]`. A single
      non-list value is wrapped in a list at render time
    * `:border` - border style atom: `:rounded` (default), `:single`, `:double`,
      `:heavy`. An unknown value falls back to `:rounded` at render time
    * `:border_color` - `{r, g, b}` tuple for border characters. Default `nil`,
      which falls back to the theme's border colour and then to `:color`
    * `:color` - `{r, g, b}` tuple for content text. Default `nil`, which falls back
      to the theme and then to `{200, 200, 200}`
    * `:background` - `{r, g, b}` tuple for the card background. Default `nil`,
      which falls back to the theme and then to `{40, 44, 52}`
    * `:style` - `t:map/0` of style properties. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:app_module` - module supplying a per-app theme. Default `nil`

  `update/2` re-reads every option except `:border` and `:app_module`, which are
  mount-only.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget; the card is
  display-only and never focusable.

  ## Usage

      card(["Line 1", "Line 2"], title: "Summary", border: :rounded)
      card(["Disk full"], title: "Alert", border_color: {255, 80, 80})
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @type border :: :single | :double | :rounded | :heavy

  @type rgb :: {0..255, 0..255, 0..255}

  @type t :: %__MODULE__{
          title: String.t() | nil,
          content: [String.t()] | String.t() | nil,
          border: border(),
          style: map(),
          border_color: rgb() | nil,
          background: rgb() | nil,
          color: rgb() | nil,
          classes: [atom()],
          app_module: module() | nil
        }

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

  @doc """
  Builds the card state from `props`.

      iex> c = Drafter.Widget.Card.mount(%{title: "Summary", content: ["a", "b"]})
      iex> {c.title, c.content, c.border}
      {"Summary", ["a", "b"], :rounded}

      iex> c = Drafter.Widget.Card.mount(%{})
      iex> {c.title, c.content, c.border, c.color, c.background, c.classes}
      {nil, [], :rounded, nil, nil, []}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the card into `rect`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. Returns `[]`
  when `rect.width` is under 2. Otherwise returns `2 + length(content)` strips —
  a top border, one row per content line padded and truncated to the inner width,
  and a bottom border. `rect.height` is not consulted, so a card with more content
  lines than rows overflows.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    render_card(state, rect)
  end

  defp render_card(_state, %{width: width}) when width < 2, do: []

  defp render_card(state, rect) do
    computed = Computed.for_widget(:card, state, classes: state.classes, style: state.style)

    bg = state.background || computed[:background] || {40, 44, 52}
    fg = state.color || computed[:color] || {200, 200, 200}
    border_fg = state.border_color || computed[:border_color] || fg

    content_style = %{fg: fg, bg: bg}
    border_style = %{fg: border_fg, bg: bg}
    title_style = %{fg: border_fg, bg: bg, bold: true}

    chars = Map.get(@border_chars, state.border, @border_chars[:rounded])
    inner_width = max(rect.width - 2, 0)

    content_lines = state.content || []
    content_lines = if is_list(content_lines), do: content_lines, else: [content_lines]

    [render_top_border(chars, inner_width, state.title, border_style, title_style)] ++
      render_content_lines(chars, inner_width, content_lines, content_style, border_style) ++
      [render_bottom_border(chars, inner_width, border_style)]
  end

  @doc """
  Folds fresh props into `state`.

  Re-reads `:title`, `:content`, `:style`, `:border_color`, `:background`, `:color`
  and `:classes`. `:border` and `:app_module` are ignored here and keep their
  mounted values.

      iex> c = Drafter.Widget.Card.mount(%{border: :single, content: ["a"]})
      iex> updated = Drafter.Widget.Card.update(%{content: ["b"], border: :heavy}, c)
      iex> {updated.content, updated.border}
      {["b"], :single}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  Ignores every event and returns `{:noreply, state}`. The card is not focusable and
  never consumes input.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
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
