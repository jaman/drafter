defmodule Drafter.Widget.Placeholder do
  @moduledoc """
  Renders a coloured placeholder block useful during development and layout design.

  Each placeholder is assigned a distinct pastel background colour derived from
  a number embedded in its text label. Text is centered vertically and horizontally
  inside the block, and an optional border can be drawn around the content area.

  ## Component tag

  Tag `:placeholder`, built by `Drafter.App` as `{:placeholder, opts}`:

      placeholder(opts)

  `placeholder/1` takes a keyword list only — there is no positional argument, so
  the label must be given as `text:` (or `label:`, which the element accepts as
  an alias).

  ## Options

    * `:text` - `t:String.t/0` label drawn in the middle row. Default
      `"Placeholder"`. The first run of digits in the text picks the pastel colour:
      `"Placeholder 3"` takes the third entry, text with no digits takes the first.
    * `:label` - `t:String.t/0` alias for `:text`, read only by
      `from_component_opts/2` and taking precedence over `:text`. Default: the value
      of `:text`.
    * `:padding` - `t:non_neg_integer/0` padding applied on all four sides when
      computing the content area. Default `2`. Nothing is drawn once
      `2 * padding` reaches the rect width or height.
    * `:align` - `:left | :center | :right`. Default `:center`. Stored on the state
      and returned by `mount/1`, but `render/2` always centres the text.
    * `:border` - `t:boolean/0`, draw a box border around the content area. Default
      `false`.
    * `:style` - `t:map/0` of style attributes applied to every segment. Default
      through `mount/1` is the auto-generated `%{fg: ..., bg: ...}` pastel pair;
      default through the component tag is `%{}`, which discards the pastel colour.

  Only `:text` is live-updatable through the component tree:
  `update_props_from_mount/3` returns `:text` alone. `update/2` called directly
  merges any key.

  ## Usage

      placeholder(text: "Placeholder 1")
      placeholder(text: "Placeholder 2", border: true, padding: 4)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}

  @pastel_colors [
    {77, 17, 68},
    {94, 34, 51},
    {111, 60, 60},
    {128, 85, 43},
    {128, 119, 9},
    {85, 119, 51},
    {43, 119, 77},
    {26, 111, 102},
    {9, 102, 111},
    {9, 85, 111},
    {34, 60, 102},
    {60, 34, 85},
    {85, 34, 60},
    {102, 34, 34},
    {102, 68, 34},
    {85, 85, 34}
  ]

  @type t :: %{
          text: String.t(),
          style: map(),
          padding: non_neg_integer(),
          align: :left | :center | :right,
          border: boolean()
        }

  @doc """
  Builds the widget state from `props`.

  Reads `:text` (default `"Placeholder"`), `:style` (default: a pastel
  `%{fg: rgb, bg: rgb}` pair chosen from the digits in the text), `:padding`
  (default `2`), `:align` (default `:center`) and `:border` (default `false`).

      iex> Drafter.Widget.Placeholder.mount(%{text: "Placeholder 1"})
      %{align: :center, border: false, padding: 2, style: %{bg: {77, 17, 68}, fg: {230, 230, 230}}, text: "Placeholder 1"}

      iex> Drafter.Widget.Placeholder.mount(%{text: "x", style: %{}, padding: 0, border: true})
      %{align: :center, border: true, padding: 0, style: %{}, text: "x"}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    placeholder_text = Map.get(props, :text, "Placeholder")
    color_index = extract_number_from_text(placeholder_text) - 1
    bg_color = Enum.at(@pastel_colors, rem(color_index, length(@pastel_colors)))

    fg_color = contrasting_text_color(bg_color)

    %{
      text: placeholder_text,
      style: Map.get(props, :style, %{fg: fg_color, bg: bg_color}),
      padding: Map.get(props, :padding, 2),
      align: Map.get(props, :align, :center),
      border: Map.get(props, :border, false)
    }
  end

  @doc """
  Draws the block into `rect`.

  Returns `[]` when `2 * padding` leaves no content width or height. Without a
  border the result has one strip per content row, with the text centred on the
  middle row. With a border the result has `content_height + 2` strips: a top rule,
  the bordered rows, and a bottom rule.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    render_placeholder(state, rect)
  end

  @doc """
  Merges `props` into `state` and returns the result.

  Every key in `props` replaces the one on the state, including `:style`, so the
  pastel colour chosen at mount is only kept while `:style` stays absent.

      iex> state = Drafter.Widget.Placeholder.mount(%{text: "x", style: %{}})
      iex> Drafter.Widget.Placeholder.update(%{text: "y", border: true}, state)
      %{align: :center, border: true, padding: 2, style: %{}, text: "y"}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The widget is not focusable
  and never consumes input.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  def handle_event(_event, state) do
    {:noreply, state}
  end

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `3`.

      iex> Drafter.Widget.Placeholder.preferred_height(nil, [])
      3

      iex> Drafter.Widget.Placeholder.preferred_height(nil, height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 3)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Placeholder.component_tag()
      :placeholder
  """
  @spec component_tag() :: :placeholder
  def component_tag, do: :placeholder

  @doc """
  Builds the props map for a `{:placeholder, opts}` element.

  The positional argument is ignored. Reads `:label` first and falls back to
  `:text`, both defaulting to `"Placeholder"`; then `:padding` (default `2`),
  `:align` (default `:center`), `:border` (default `false`) and `:style`
  (default `%{}`). Because `:style` is always present in the result, a placeholder
  built from the component tag never picks up the pastel colour `mount/1` would
  otherwise generate.

      iex> Drafter.Widget.Placeholder.from_component_opts(nil, [])
      %{align: :center, border: false, padding: 2, style: %{}, text: "Placeholder"}

      iex> Drafter.Widget.Placeholder.from_component_opts(nil, label: "Left", text: "Right")
      %{align: :center, border: false, padding: 2, style: %{}, text: "Left"}
  """
  @spec from_component_opts(term(), keyword()) :: t()
  def from_component_opts(_args, opts) do
    %{
      text: Keyword.get(opts, :label, Keyword.get(opts, :text, "Placeholder")),
      padding: Keyword.get(opts, :padding, 2),
      align: Keyword.get(opts, :align, :center),
      border: Keyword.get(opts, :border, false),
      style: Keyword.get(opts, :style, %{})
    }
  end

  @doc """
  Narrows a re-render to `:text`, the only prop that reaches an already-mounted
  placeholder through the component tree.

      iex> props = Drafter.Widget.Placeholder.from_component_opts(nil, text: "New", border: true)
      iex> Drafter.Widget.Placeholder.update_props_from_mount(props, %{}, [])
      %{text: "New"}
  """
  @spec update_props_from_mount(t(), term(), keyword()) :: %{text: String.t()}
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{text: mount_props.text}
  end

  defp render_placeholder(state, rect) do
    padding = state.padding
    content_width = rect.width - padding * 2
    content_height = rect.height - padding * 2

    if content_width <= 0 or content_height <= 0 do
      []
    else
      render_content(state, content_width, content_height, padding)
    end
  end

  defp render_content(state, content_width, content_height, padding) do
    if state.border do
      render_with_border(state, content_width, content_height, padding)
    else
      render_without_border(state, content_width, content_height, padding)
    end
  end

  defp render_with_border(state, content_width, content_height, padding) do
    top_border = "┌" <> String.duplicate("─", content_width) <> "┐"
    bottom_border = "└" <> String.duplicate("─", content_width) <> "┘"
    text_lines = wrap_text(state.text, content_width - 2)
    text_y = div(content_height - 2, 2)

    Enum.map(0..(content_height + 1), fn row ->
      text =
        border_row_text(
          row,
          content_height,
          text_y,
          text_lines,
          top_border,
          bottom_border,
          content_width
        )

      padded_strip(Segment.new(text, state.style), padding)
    end)
  end

  defp border_row_text(0, _ch, _ty, _tl, top, _bottom, _cw), do: top
  defp border_row_text(row, ch, _ty, _tl, _top, bottom, _cw) when row == ch + 1, do: bottom

  defp border_row_text(row, _ch, text_y, text_lines, _top, _bottom, content_width)
       when row == text_y + 1 and text_lines != [] do
    "│" <> String.pad_trailing(List.first(text_lines), content_width - 2) <> "│"
  end

  defp border_row_text(_row, _ch, _ty, _tl, _top, _bottom, content_width) do
    "│" <> String.duplicate(" ", content_width) <> "│"
  end

  defp padded_strip(segment, 0), do: Strip.new([segment])

  defp padded_strip(segment, padding) do
    padding_segment = Segment.new(String.duplicate(" ", padding))
    Strip.new([padding_segment, segment, padding_segment])
  end

  defp render_without_border(state, content_width, content_height, padding) do
    text_lines = wrap_text(state.text, content_width)
    center_row = div(content_height, 2)

    Enum.map(0..(content_height - 1)//1, fn row ->
      line_text = borderless_row_text(row, center_row, text_lines, content_width)
      segment = Segment.new(line_text, state.style)
      padded_strip_styled(segment, padding, state.style)
    end)
  end

  defp borderless_row_text(row, center_row, text_lines, content_width)
       when row == center_row and text_lines != [] do
    text = List.first(text_lines)
    text_length = String.length(text)

    if text_length <= content_width do
      padding_left = div(content_width - text_length, 2)
      padding_right = content_width - text_length - padding_left
      String.duplicate(" ", padding_left) <> text <> String.duplicate(" ", padding_right)
    else
      String.slice(text, 0, content_width)
    end
  end

  defp borderless_row_text(_row, _center_row, _text_lines, content_width) do
    String.duplicate(" ", content_width)
  end

  defp padded_strip_styled(segment, 0, _style), do: Strip.new([segment])

  defp padded_strip_styled(segment, padding, style) do
    padding_segment = Segment.new(String.duplicate(" ", padding), style)
    Strip.new([padding_segment, segment, padding_segment])
  end

  defp wrap_text(text, width) do
    if String.length(text) <= width do
      [text]
    else
      text
      |> String.graphemes()
      |> Enum.chunk_every(width)
      |> Enum.map(&Enum.join/1)
    end
  end

  defp extract_number_from_text(text) do
    case Regex.run(~r/(\d+)/, text) do
      [_, number_str] -> String.to_integer(number_str)
      _ -> 1
    end
  end

  defp contrasting_text_color({r, g, b}) do
    luminance = 0.299 * r + 0.587 * g + 0.114 * b

    if luminance < 128 do
      {230, 230, 230}
    else
      {30, 30, 30}
    end
  end
end
