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

  ## Options

    * `:text` - string of characters to render (default `""`)
    * `:style` - map of style properties applied to all characters
    * `:align` - horizontal alignment within the available width: `:left` (default), `:center`, `:right`
    * `:font` - a name from `Drafter.Widget.Digits.Font.names/0`, or a font map; overrides `:size`
    * `:size` - coarse size when no `:font` is given: `:large` (default, 7×5) or `:small` (5×3)
    * `:renderer` - `:text` (default) draws cells; `:graphics` transmits an image on a terminal that supports kitty, iTerm2, or sixel, falling back to cells where none is available
    * `:bg_data` - optional list of numbers; when set, renders an area-chart fill behind the digits using per-cell bg colors (same composite as Grafana's graphMode: area stat panel)
    * `:color` - `{r, g, b}` fill color for the area chart (default `{0, 150, 255}`); digit glyphs are rendered with an auto-contrasting fg color

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

  @impl Drafter.Widget
  def update(props, state) do
    Map.merge(state, props)
  end

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

  def preferred_height(_args, opts) do
    opts
    |> Keyword.get(:font)
    |> Kernel.||(size_font(Keyword.get(opts, :size, :large)))
    |> Font.height()
  end

  def component_tag, do: :digits

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

  def image(state, rect, id) do
    with renderer when renderer != :text <- Map.get(state, :renderer, :text),
         cols when cols > 0 <- rect.width,
         rows when rows > 0 <- rect.height do
      paint_image(state, {cols, rows}, renderer, id)
    else
      _ -> nil
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
