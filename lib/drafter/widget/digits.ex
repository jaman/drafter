defmodule Drafter.Widget.Digits do
  @moduledoc """
  Renders text as large characters, drawn with box outlines or with pixels
  packed into braille, quadrant, or half-block cells.

  Covers the digits `0`–`9`, the full alphabet, and common punctuation. Lower
  case falls back to the upper-case form, and a character no font can draw
  renders as blanks of the same width.

  The glyphs live in `Drafter.Widget.Digits.Font`, which also accepts FIGlet
  fonts loaded at runtime. See the [large text guide](large_text.md) for the
  catalogue and how to choose between fonts.

  ## Component tag

  Tag `:digits`, built by `Drafter.App` as `{:digits, value, opts}`:

      digits(value, opts)

  The positional argument is passed through `to_string/1` to become `:text`, so
  it may be any term implementing `String.Chars`. All other props come from
  `opts`.

  ## Options

    * `:text` - `t:String.t/0` of characters to render. Default `""`. Supplied
      positionally through the `digits/2` element, passed through `to_string/1`.
      Empty text renders nothing at all
    * `:style` - `t:map/0` of style properties applied to all characters. Default
      `%{}`
    * `:align` - horizontal alignment within the available width: `:left` (default),
      `:center`, `:right`
    * `:font` - a name from `Drafter.Widget.Digits.Font.names/0`, or a font map.
      Default `nil`. Overrides `:size` when set
    * `:size` - coarse size when no `:font` is given: `:large` (default, the
      `:block` font) or `:small` (the `:compact` font)
    * `:renderer` - `:text` (default) draws cells; any other value transmits an
      image on a terminal supporting kitty, iTerm2, or sixel, falling back to cells
      where none is available
    * `:bg_data` - list of numbers. Default `nil`. When set, an area-chart fill is
      drawn behind the digits using per-cell background colours
    * `:color` - `{r, g, b}` fill colour for the area chart. Default
      `{0, 150, 255}`. Digit glyphs are drawn in an auto-contrasting foreground
    * `:bg_min` - value mapped to the bottom of the `:bg_data` area fill. Default `0`
    * `:bg_max` - value mapped to the top of the `:bg_data` area fill. Default `nil`,
      which uses the largest sampled value, or `1` when `:bg_data` is empty

  `update/2` merges the props map into the state, so every option is live, and a
  re-render passes all of them through.

  ## Widget value

  `Drafter.get_widget_value/1` returns the rendered `:text` as a `t:String.t/0`,
  because the value extractor reads the `:text` field.

  ## Data channel

  When the widget is declared with a data buffer, `apply_data_buffer/3` sets `:text`
  to `to_string/1` of the last item in the buffer.

  ## Usage

      digits("12:34", size: :large, style: %{fg: {0, 200, 100}})
      digits("99%", size: :small, align: :center)
      digits("CPU 42", font: :braille)
      digits("Vellum", font: :slant, renderer: :graphics)
      digits("42%", bg_data: history, color: {0, 180, 120}, size: :large, align: :center)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  alias Drafter.Widget.Digits.{Font, Image}

  defp selected_font(state) do
    Font.get(font_name(state))
  end

  defp font_name(state) do
    Map.get(state, :font) || size_font(Map.get(state, :size, :large))
  end

  defp size_font(:small), do: :compact
  defp size_font(_large), do: :block

  defp glyph(font, character), do: Font.glyph(font, character)

  @type t :: %{
          text: String.t(),
          style: map(),
          align: :left | :center | :right,
          size: :large | :small,
          font: atom() | map() | nil,
          renderer: atom(),
          bg_data: [number()] | nil,
          color: {0..255, 0..255, 0..255},
          bg_min: number(),
          bg_max: number() | nil
        }

  @doc """
  Builds the digits state from `props`. The state is a plain map, not a struct.

      iex> d = Drafter.Widget.Digits.mount(%{text: "42", size: :small})
      iex> {d.text, d.size, d.font, d.align}
      {"42", :small, nil, :left}

      iex> Drafter.Widget.Digits.mount(%{})
      %{text: "", style: %{}, align: :left, size: :large, font: nil, renderer: :text, bg_data: nil, color: {0, 150, 255}, bg_min: 0, bg_max: nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %{
      text: Map.get(props, :text, ""),
      style: Map.get(props, :style, %{}),
      align: Map.get(props, :align, :left),
      size: Map.get(props, :size, :large),
      font: Map.get(props, :font),
      renderer: Map.get(props, :renderer, :text),
      bg_data: Map.get(props, :bg_data),
      color: Map.get(props, :color, {0, 150, 255}),
      bg_min: Map.get(props, :bg_min, 0),
      bg_max: Map.get(props, :bg_max)
    }
  end

  @doc """
  Draws the large characters into `rect`.

  Returns `[]` for empty `:text`. Otherwise it emits one strip per row of the
  selected font's height, positioned horizontally according to `:align`. With
  `:bg_data` set, each cell also carries the area-chart background colour for its
  column.

      iex> Drafter.Widget.Digits.render(Drafter.Widget.Digits.mount(%{}), %{x: 0, y: 0, width: 20, height: 7})
      []
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    digits = String.graphemes(state.text)

    if Enum.empty?(digits) do
      []
    else
      case state.bg_data do
        nil -> render_digits(digits, state, rect)
        data -> render_with_bg(digits, data, state, rect)
      end
    end
  end

  @doc """
  Merges `props` into `state`, so every option is live-updatable.

      iex> d = Drafter.Widget.Digits.mount(%{text: "1"})
      iex> Drafter.Widget.Digits.update(%{text: "2", align: :center}, d).text
      "2"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The widget is not focusable
  and never consumes input.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(_event, state) do
    {:noreply, state}
  end

  @braille_base 0x2800
  @braille_dot_offsets %{
    {0, 0} => 0x01,
    {0, 1} => 0x02,
    {0, 2} => 0x04,
    {0, 3} => 0x40,
    {1, 0} => 0x08,
    {1, 1} => 0x10,
    {1, 2} => 0x20,
    {1, 3} => 0x80
  }

  @doc """
  The row height of the font `opts` selects.

  `opts[:font]` wins; otherwise `opts[:size]` picks `:block` for `:large` (the
  default) and `:compact` for `:small`.

      iex> Drafter.Widget.Digits.preferred_height("42", size: :small)
      3

      iex> Drafter.Widget.Digits.preferred_height("42", [])
      5
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts) do
    opts
    |> Keyword.get(:font)
    |> Kernel.||(size_font(Keyword.get(opts, :size, :large)))
    |> Font.height()
  end

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Digits.component_tag()
      :digits
  """
  @spec component_tag() :: :digits
  def component_tag, do: :digits

  @doc """
  Turns the `{:digits, value, opts}` element into a props map for `mount/1`.

  `value` becomes `:text` through `to_string/1`, so it may be any term implementing
  `String.Chars`.

      iex> props = Drafter.Widget.Digits.from_component_opts(42, align: :center)
      iex> {props.text, props.align, props.size, props.color, props.bg_min}
      {"42", :center, :large, {0, 150, 255}, 0}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(value, opts) do
    %{
      text: to_string(value),
      style: Keyword.get(opts, :style, %{}),
      align: Keyword.get(opts, :align, :left),
      size: Keyword.get(opts, :size, :large),
      font: Keyword.get(opts, :font),
      renderer: Keyword.get(opts, :renderer, :text),
      bg_data: Keyword.get(opts, :bg_data),
      color: Keyword.get(opts, :color, {0, 150, 255}),
      bg_min: Keyword.get(opts, :bg_min, 0),
      bg_max: Keyword.get(opts, :bg_max)
    }
  end

  @doc """
  Passes every option through to `update/2` on a re-render, so nothing about a
  digits widget is mount-only.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      text: mount_props.text,
      size: mount_props.size,
      font: mount_props.font,
      style: mount_props.style,
      align: mount_props.align,
      renderer: mount_props.renderer,
      bg_data: mount_props.bg_data,
      color: mount_props.color,
      bg_min: mount_props.bg_min,
      bg_max: mount_props.bg_max
    }
  end

  @doc """
  Builds the terminal-graphics payload for the text, or `nil`.

  Returns `nil` when `:renderer` is `:text`, when `rect` has no area, or when no
  supported graphics protocol is available. Otherwise returns
  `{paint, clear, placement}`, where `placement` is
  `%{dx: 0, dy: 0, cols: rect.width, rows: rect.height}`.
  """
  @spec image(t(), Drafter.Widget.rect(), term()) :: {iodata(), iodata(), map()} | nil
  def image(state, rect, id) do
    with renderer when renderer != :text <- Map.get(state, :renderer, :text),
         cols when cols > 0 <- rect.width,
         rows when rows > 0 <- rect.height do
      paint_image(state, {cols, rows}, renderer, id)
    else
      _ -> nil
    end
  end

  @doc """
  Whether these digits are drawing a transmitted image rather than cells.

  True when `:renderer` is anything but `:text` and the terminal has a graphics
  protocol to draw it with.
  """
  @spec image_active?(t()) :: boolean()
  @impl Drafter.Widget
  def image_active?(state) do
    case Map.get(state, :renderer, :text) do
      :text -> false
      renderer -> Image.protocol(image_renderer(renderer)) != nil
    end
  end

  defp paint_image(state, {cols, rows}, renderer, id) do
    color =
      Map.get(
        Computed.to_segment_style(Computed.for_widget(:digits, state, style: state.style)),
        :fg
      )

    case Image.render(state.text, {cols, rows}, color, image_renderer(renderer), id) do
      nil -> nil
      {paint, clear} -> {paint, clear, %{dx: 0, dy: 0, cols: cols, rows: rows}}
    end
  end

  defp image_renderer(:graphics), do: :auto
  defp image_renderer(renderer), do: renderer

  @doc """
  Sets `:text` to `to_string/1` of the newest item in the widget's data buffer.

  Everything buffered before the last item is discarded. An empty buffer leaves the
  state alone.
  """
  @spec apply_data_buffer(t(), Drafter.RingBuffer.t(), Drafter.Widget.rect()) :: t()
  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    case Drafter.RingBuffer.last(buffer) do
      nil -> state
      value -> %{state | text: to_string(value)}
    end
  end

  defp render_with_bg(digits, data, state, rect) do
    font = selected_font(state)

    computed = Computed.for_widget(:digits, state, style: state.style)
    digit_fg = Map.get(Computed.to_segment_style(computed), :fg)

    glyph_width = Enum.reduce(digits, 0, &(&2 + Font.glyph_width(font, &1)))
    left_offset = alignment_offset(state.align, rect.width, glyph_width)
    top_offset = max(0, div(rect.height - font.height, 2))
    glyph_map = build_glyph_map(digits, font, left_offset, top_offset)
    braille_map = build_braille_map(data, rect, state)

    Enum.map(0..(rect.height - 1)//1, fn row ->
      segments =
        Enum.map(
          0..(rect.width - 1)//1,
          &render_bg_cell(glyph_map, braille_map, row, &1, digit_fg, state.color)
        )

      Strip.new(segments)
    end)
  end

  defp alignment_offset(:center, width, glyph_width), do: max(0, div(width - glyph_width, 2))
  defp alignment_offset(:right, width, glyph_width), do: max(0, width - glyph_width)
  defp alignment_offset(_, _width, _glyph_width), do: 0

  defp render_bg_cell(glyph_map, braille_map, row, col, digit_fg, line_color) do
    glyph_char = Map.get(glyph_map, {row, col})
    braille = Map.get(braille_map, {col, row})

    cond do
      glyph_char && glyph_char != " " ->
        Segment.new(glyph_char, if(digit_fg, do: %{fg: digit_fg}, else: %{}))

      braille ->
        Segment.new(braille, %{fg: line_color})

      true ->
        Segment.new(" ", %{})
    end
  end

  defp build_braille_map(data, rect, state) do
    pixel_width = rect.width * 2
    pixel_height = rect.height * 4
    sampled = sample_data(data, pixel_width)
    min_val = state.bg_min || 0
    max_val = state.bg_max || Enum.max(sampled, fn -> 1 end)
    range = max(max_val - min_val, 1)

    sampled
    |> Enum.with_index(fn v, x ->
      y_norm = (v - min_val) / range * (pixel_height - 1)
      {x, pixel_height - 1 - (y_norm |> round() |> min(pixel_height - 1) |> max(0))}
    end)
    |> Enum.filter(fn {x, y} -> x >= 0 and x < pixel_width and y >= 0 and y < pixel_height end)
    |> Enum.group_by(fn {x, y} -> {div(x, 2), div(y, 4)} end)
    |> Map.new(fn {key, pixels} ->
      bits =
        Enum.reduce(pixels, 0, fn {x, y}, acc ->
          acc + Map.get(@braille_dot_offsets, {rem(x, 2), rem(y, 4)}, 0)
        end)

      {key, <<@braille_base + bits::utf8>>}
    end)
  end

  defp build_glyph_map(digits, font, left_offset, top_offset) do
    digits
    |> Enum.reduce({%{}, left_offset}, fn digit, {map, col_offset} ->
      rows = glyph(font, digit)
      row_map = place_pattern(rows, map, col_offset, top_offset)
      {row_map, col_offset + Font.glyph_width(font, digit)}
    end)
    |> elem(0)
  end

  defp place_pattern(pattern, map, col_offset, top_offset) do
    pattern
    |> Enum.with_index()
    |> Enum.reduce(map, fn {row_str, row_idx}, acc ->
      place_row(row_str, acc, col_offset, top_offset + row_idx)
    end)
  end

  defp place_row(row_str, acc, col_offset, row_key) do
    row_str
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {ch, c}, inner ->
      Map.put(inner, {row_key, col_offset + c}, ch)
    end)
  end

  defp sample_data(data, width) do
    len = length(data)

    cond do
      len == 0 ->
        List.duplicate(0, width)

      len == width ->
        data

      true ->
        Enum.map(0..(width - 1)//1, fn i ->
          idx = round(i * (len - 1) / max(width - 1, 1))
          Enum.at(data, idx)
        end)
    end
  end

  defp render_digits(digits, state, rect) do
    computed = Computed.for_widget(:digits, state, style: state.style)
    effective_style = Computed.to_segment_style(computed)

    font = selected_font(state)
    digit_height = font.height

    digit_rows =
      0..(digit_height - 1)//1
      |> Enum.map(fn row ->
        line_text =
          Enum.map_join(digits, fn digit ->
            Enum.at(glyph(font, digit), row, String.duplicate(" ", Font.glyph_width(font, digit)))
          end)

        segment = Segment.new(line_text, effective_style)
        strip = Strip.new([segment])

        case state.align do
          :center -> align_center(strip, rect.width, effective_style)
          :right -> align_right(strip, rect.width, effective_style)
          _ -> align_left(strip, rect.width, effective_style)
        end
      end)

    if rect.height <= digit_height do
      Enum.take(digit_rows, rect.height)
    else
      empty_strip = Strip.new([Segment.new(String.duplicate(" ", rect.width), effective_style)])
      top_pad = div(rect.height - digit_height, 2)
      bottom_pad = rect.height - digit_height - top_pad
      top_rows = List.duplicate(empty_strip, top_pad)
      bottom_rows = List.duplicate(empty_strip, bottom_pad)
      top_rows ++ digit_rows ++ bottom_rows
    end
  end

  defp align_left(strip, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      padding_width = width - strip_width
      padding = Segment.new(String.duplicate(" ", padding_width), bg_style)
      Strip.new(strip.segments ++ [padding])
    end
  end

  defp align_center(strip, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      total_padding = width - strip_width
      left_padding = div(total_padding, 2)
      right_padding = total_padding - left_padding
      left_seg = Segment.new(String.duplicate(" ", left_padding), bg_style)
      right_seg = Segment.new(String.duplicate(" ", right_padding), bg_style)
      Strip.new([left_seg] ++ strip.segments ++ [right_seg])
    end
  end

  defp align_right(strip, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      padding_width = width - strip_width
      padding = Segment.new(String.duplicate(" ", padding_width), bg_style)
      Strip.new([padding] ++ strip.segments)
    end
  end
end
