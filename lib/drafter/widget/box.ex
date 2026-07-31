defmodule Drafter.Widget.Box do
  @moduledoc """
  A container widget that draws a titled border around its children.

  Supports single, double, rounded, and thick border styles. The title is
  rendered in the top border. Use the `box/2` helper in `Drafter.App`.
  """

  @behaviour Drafter.Widget

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

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

  def update(props, state) do
    Map.merge(state, props)
  end

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
