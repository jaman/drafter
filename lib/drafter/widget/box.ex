defmodule Drafter.Widget.Box do
  @moduledoc """
  Draws a titled border around a region; children render inside the border.

  The box itself renders only the frame and the title. Children are laid out by
  the component renderer into the rect remaining after the border and padding
  are subtracted, so a box one row tall has no room for content.

  A `:title` is embedded in the top border. Border style `:none` still occupies
  no rows, meaning the content rect is inset by padding only.

  ## Component tag

  This module has no `component_tag/0` and is not reached through the widget
  registry. `Drafter.App` builds it as the element `{:box, children, opts}`:

      box(children, opts)

  `children` is a list of child element tuples. `opts` is a keyword list read
  by the renderer, which passes `:title`, `:border`, `:padding` and `:style`
  through to `mount/1`.

  ## Options

    * `:title` — string embedded in the top border; `nil` for none (default `nil`)
    * `:border` — border style atom, one of `:none`, `:single`, `:double`,
      `:rounded`, `:heavy`, `:dashed`, `:ascii`. Defaults to the current
      character set's border style, falling back to `:rounded`
    * `:padding` — inner padding in columns and rows (default `0` when mounting
      this module directly; the `box/2` element defaults it to the character
      set's padding, falling back to `1`)
    * `:style` — map of style overrides for the widget as a whole
    * `:border_style` — map of style overrides for the border characters
    * `:title_style` — map of style overrides for the title text
    * `:content_style` — map of style overrides for the interior fill
    * `:classes` — list of theme class atoms

  `:border_style`, `:title_style`, `:content_style` and `:classes` are read by
  `mount/1` only; the `{:box, children, opts}` element does not forward them.

  Every option is live-updatable: `update/2` merges the props map into the state.

  ## Usage

      box([label("Ready")], title: "Status", border: :double, padding: 1)
  """

  @behaviour Drafter.Widget

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @type border :: :none | :single | :double | :rounded | :heavy | :dashed | :ascii

  @type t :: %__MODULE__{
          title: String.t() | nil,
          border: border(),
          padding: non_neg_integer(),
          style: map(),
          border_style: map(),
          title_style: map(),
          content_style: map(),
          classes: [atom()],
          app_module: module() | nil
        }

  @border_chars %{
    none: %{tl: " ", tr: " ", bl: " ", br: " ", h: " ", v: " "},
    single: %{tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│"},
    double: %{tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║"},
    rounded: %{tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│"},
    heavy: %{tl: "┏", tr: "┓", bl: "┗", br: "┛", h: "━", v: "┃"},
    dashed: %{tl: "┌", tr: "┐", bl: "└", br: "┘", h: "┄", v: "┆"},
    ascii: %{tl: "+", tr: "+", bl: "+", br: "+", h: "-", v: "|"}
  }

  defstruct [
    :title,
    :border,
    :padding,
    :style,
    :border_style,
    :title_style,
    :content_style,
    :classes,
    :app_module
  ]

  @doc """
  Builds the box state from `props`.

  An unknown `:border` value is kept on the state as given and falls back to the
  `:rounded` characters at render time.

      iex> box = Drafter.Widget.Box.mount(%{title: "Status", border: :double, padding: 2})
      iex> {box.title, box.border, box.padding}
      {"Status", :double, 2}

      iex> box = Drafter.Widget.Box.mount(%{})
      iex> {box.title, box.padding, box.classes, box.style}
      {nil, 0, [], %{}}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    %__MODULE__{
      title: Map.get(props, :title),
      border: Map.get(props, :border, CharacterSet.style(:border) || :rounded),
      padding: Map.get(props, :padding, 0),
      style: Map.get(props, :style, %{}),
      border_style: Map.get(props, :border_style, %{}),
      title_style: Map.get(props, :title_style, %{}),
      content_style: Map.get(props, :content_style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @doc """
  Draws the frame, the title and the blank interior of the box into `rect`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. Emits, in
  order, the top border row (when `:border` is not `:none`), `:padding` blank rows,
  the interior rows, `:padding` blank rows again, and the bottom border row. At
  least one interior row is always emitted, so a box shorter than its own chrome
  returns more strips than `rect.height`.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    render_box(state, rect)
  end

  defp render_box(state, rect) do
    computed = Computed.for_widget(:box, state, classes: state.classes, style: state.style)
    bg = computed[:background] || {40, 44, 52}
    fg = computed[:color] || {200, 200, 200}
    border_fg = computed[:border_color] || {100, 100, 120}

    base_style = %{fg: fg, bg: bg}
    border_style_map = %{fg: border_fg, bg: bg}
    title_style_map = Map.merge(%{fg: {150, 200, 255}, bg: bg, bold: true}, state.title_style)

    chars = Map.get(@border_chars, state.border, @border_chars[:rounded])
    has_border = state.border != :none
    border_offset = if has_border, do: 1, else: 0

    content_height = max(0, rect.height - border_offset * 2 - state.padding * 2)

    top =
      if has_border,
        do: [render_top_border(chars, rect.width, state.title, border_style_map, title_style_map)],
        else: []

    pad_top =
      if state.padding > 0,
        do:
          render_padding_rows(
            chars,
            rect.width,
            state.padding,
            has_border,
            base_style,
            border_style_map
          ),
        else: []

    content =
      render_content_rows(
        chars,
        rect.width,
        content_height,
        state.padding,
        has_border,
        base_style,
        border_style_map
      )

    pad_bot = pad_top
    bot = if has_border, do: [render_bottom_border(chars, rect.width, border_style_map)], else: []

    top ++ pad_top ++ content ++ pad_bot ++ bot
  end

  @doc """
  Merges `props` into `state`, so every option is live-updatable.

  Keys absent from `props` keep their current value.

      iex> state = Drafter.Widget.Box.mount(%{title: "One"})
      iex> Drafter.Widget.Box.update(%{title: "Two", padding: 3}, state).title
      "Two"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The box is not focusable and
  never consumes input; children handle their own events.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_top_border(chars, width, title, border_style, title_style) do
    inner_width = max(0, width - 2)

    if title && String.length(title) > 0 do
      title_text = " #{title} "
      title_len = String.length(title_text)
      left_len = min(2, inner_width)
      right_len = max(0, inner_width - left_len - title_len)

      segments = [
        Segment.new(chars.tl, border_style),
        Segment.new(String.duplicate(chars.h, left_len), border_style),
        Segment.new(title_text, title_style),
        Segment.new(String.duplicate(chars.h, right_len), border_style),
        Segment.new(chars.tr, border_style)
      ]

      Strip.new(segments)
    else
      segments = [
        Segment.new(chars.tl, border_style),
        Segment.new(String.duplicate(chars.h, inner_width), border_style),
        Segment.new(chars.tr, border_style)
      ]

      Strip.new(segments)
    end
  end

  defp render_bottom_border(chars, width, border_style) do
    inner_width = max(0, width - 2)

    segments = [
      Segment.new(chars.bl, border_style),
      Segment.new(String.duplicate(chars.h, inner_width), border_style),
      Segment.new(chars.br, border_style)
    ]

    Strip.new(segments)
  end

  defp render_padding_rows(chars, width, padding, has_border, base_style, border_style) do
    inner_width = max(0, if(has_border, do: width - 2, else: width))

    Enum.map(1..padding, fn _ ->
      if has_border do
        segments = [
          Segment.new(chars.v, border_style),
          Segment.new(String.duplicate(" ", inner_width), base_style),
          Segment.new(chars.v, border_style)
        ]

        Strip.new(segments)
      else
        Strip.new([Segment.new(String.duplicate(" ", width), base_style)])
      end
    end)
  end

  defp render_content_rows(chars, width, height, _padding, has_border, base_style, border_style) do
    inner_width = max(0, if(has_border, do: width - 2, else: width))

    Enum.map(1..max(1, height), fn _ ->
      if has_border do
        segments = [
          Segment.new(chars.v, border_style),
          Segment.new(String.duplicate(" ", inner_width), base_style),
          Segment.new(chars.v, border_style)
        ]

        Strip.new(segments)
      else
        Strip.new([Segment.new(String.duplicate(" ", width), base_style)])
      end
    end)
  end
end
