defmodule Drafter.LayerCompositor do
  @moduledoc """
  Layered composition system for TUI rendering.

  Provides clean layer-based composition similar to modern graphics systems.
  Each layer renders independently and is composited together while preserving
  styling and transparency.

  Layer types (in render order):
  1. Background - Base theme colors, panels, backgrounds  
  2. Content - Text content, panels, cards
  3. Widgets - Interactive elements (buttons, inputs, etc.)
  4. Chrome - UI decorations (borders, scrollbars, focus indicators)
  """

  alias Drafter.Draw.{Segment, Strip}

  @type layer :: %{
          id: atom(),
          z_index: integer(),
          strips: [Strip.t()],
          bounds: %{x: integer(), y: integer(), width: integer(), height: integer()}
        }

  @type viewport :: %{width: integer(), height: integer()}
  @type composition_result :: [Strip.t()]

  @doc """
  Create a new layer for composition.

  ## Parameters
  - id: Unique identifier for the layer
  - strips: Rendered strips for this layer
  - bounds: Rendering bounds %{x: x, y: y, width: w, height: h}
  - z_index: Layer depth (higher = on top)
  """
  def create_layer(id, strips, bounds, z_index \\ 0, opacity \\ 1.0) do
    %{
      id: id,
      strips: strips || [],
      bounds: bounds,
      z_index: z_index,
      opacity: opacity
    }
  end

  @doc """
  Composite multiple layers into a final rendered view.

  Layers are composited in z_index order (lowest to highest).
  Each layer's content is placed at its bounds position.
  """
  def composite(layers, viewport) when is_list(layers) do
    sorted_layers = Enum.sort_by(layers, & &1.z_index)
    canvas = initialize_canvas(viewport)

    Enum.reduce(sorted_layers, canvas, fn layer, current_canvas ->
      composite_layer(current_canvas, layer, viewport)
    end)
  end

  @spec composite_incremental([map()], viewport(), [Strip.t()], MapSet.t(non_neg_integer())) ::
          [Strip.t()]
  def composite_incremental(layers, viewport, previous_composite, dirty_rows) do
    if MapSet.size(dirty_rows) == 0 do
      previous_composite
    else
      recompose_dirty_rows(layers, viewport, previous_composite, dirty_rows)
    end
  end

  defp recompose_dirty_rows(layers, viewport, previous_composite, dirty_rows) do
    prepared = prepare_layers_for(layers, dirty_rows)
    blank = blank_strip(viewport)
    prev_tuple = List.to_tuple(previous_composite)
    prev_count = tuple_size(prev_tuple)

    new_rows =
      Enum.reduce(dirty_rows, %{}, fn row, acc ->
        Map.put(acc, row, compose_row(prepared, viewport, row, blank))
      end)

    Enum.map(0..(viewport.height - 1)//1, fn row ->
      pick_row(Map.get(new_rows, row), row, prev_tuple, prev_count, blank)
    end)
  end

  defp prepare_layers_for(layers, dirty_rows) do
    layers
    |> Enum.filter(&intersects_rows?(&1, dirty_rows))
    |> Enum.sort_by(& &1.z_index)
    |> Enum.map(&prepare_layer/1)
  end

  defp intersects_rows?(%{bounds: bounds}, dirty_rows) do
    last = bounds.y + bounds.height - 1

    last >= bounds.y and
      Enum.any?(bounds.y..last//1, &MapSet.member?(dirty_rows, &1))
  end

  defp pick_row(nil, row, prev_tuple, prev_count, _blank) when row < prev_count,
    do: elem(prev_tuple, row)

  defp pick_row(nil, _row, _prev_tuple, _prev_count, blank), do: blank
  defp pick_row(strip, _row, _prev_tuple, _prev_count, _blank), do: strip

  defp prepare_layer(layer) do
    strips = layer.strips || []

    %{
      tuple: List.to_tuple(strips),
      count: length(strips),
      bounds: layer.bounds,
      opacity: layer_opacity(layer)
    }
  end

  defp layer_opacity(layer), do: Map.get(layer, :opacity) || 1.0

  defp compose_row(prepared, viewport, row, blank) do
    Enum.reduce(prepared, blank, fn %{tuple: tuple, count: count, bounds: bounds} = layer, acc ->
      layer_row = row - bounds.y

      if layer_row >= 0 and layer_row < count and
           row >= bounds.y and row < bounds.y + bounds.height and
           bounds.x < viewport.width do
        composite_strips_at_position(
          acc,
          elem(tuple, layer_row),
          bounds.x,
          viewport.width,
          layer.opacity
        )
      else
        acc
      end
    end)
  end

  defp blank_strip(viewport) do
    Strip.new([Segment.new(String.duplicate(" ", viewport.width), %{})])
  end

  @doc """
  Create a background layer with theme-based styling.
  """
  def background_layer(strips, bounds) do
    create_layer(:background, strips, bounds, 0)
  end

  @doc """
  Create a content layer for panels, text, etc.
  """
  def content_layer(id, strips, bounds) do
    create_layer(id, strips, bounds, 10)
  end

  @container_modules [
    Drafter.Widget.Box,
    Drafter.Widget.Card,
    Drafter.Widget.Collapsible,
    Drafter.Widget.ScrollableContainer
  ]

  @doc """
  Wrap a widget's strips in a layer at a depth derived from its id and module.

  Ids beginning with `"footer"` or `"header"` sit above content; container modules
  sit below it; everything else takes the default depth. The result is offset by
  `z_base`.
  """
  def widget_layer(widget_id, strips, bounds, z_base \\ 0, widget_module \\ nil, opacity \\ 1.0) do
    create_layer(
      widget_id,
      strips,
      bounds,
      z_base + depth_offset(widget_id, widget_module),
      opacity
    )
  end

  defp depth_offset(widget_id, widget_module) do
    name = id_to_string(widget_id)

    cond do
      String.starts_with?(name, "footer") -> 50
      String.starts_with?(name, "header") -> 40
      widget_module in @container_modules -> 10
      true -> 20
    end
  end

  defp id_to_string(id) when is_atom(id), do: Atom.to_string(id)
  defp id_to_string(id) when is_binary(id), do: id
  defp id_to_string(id), do: inspect(id)

  @doc """
  Create a chrome layer for UI decorations.
  """
  def chrome_layer(id, strips, bounds) do
    create_layer(id, strips, bounds, 30)
  end

  defp initialize_canvas(viewport) do
    empty_text = String.duplicate(" ", viewport.width)
    empty_segment = Segment.new(empty_text, %{})
    empty_strip = Strip.new([empty_segment])
    List.duplicate(empty_strip, viewport.height)
  end

  defp composite_layer(canvas, layer, viewport) do
    bounds = layer.bounds
    layer_strips = layer.strips || []
    layer_count = length(layer_strips)
    layer_tuple = List.to_tuple(layer_strips)
    opacity = layer_opacity(layer)

    canvas
    |> Enum.with_index()
    |> Enum.map(fn {canvas_strip, row_index} ->
      layer_row = row_index - bounds.y

      if layer_row >= 0 and layer_row < layer_count and
           row_index >= bounds.y and row_index < bounds.y + bounds.height and
           bounds.x < viewport.width do
        layer_strip = elem(layer_tuple, layer_row)
        composite_strips_at_position(canvas_strip, layer_strip, bounds.x, viewport.width, opacity)
      else
        canvas_strip
      end
    end)
  end

  defp composite_strips_at_position(canvas, layer_strip, x_offset, viewport_width, opacity) do
    layer_segments = layer_strip.segments || []

    cond do
      layer_segments == [] or x_offset < 0 or x_offset >= viewport_width ->
        canvas

      replaces_row?(layer_strip, layer_segments, x_offset, viewport_width, opacity) ->
        Strip.crop(layer_strip, viewport_width)

      true ->
        composite_overlay(canvas, layer_strip, layer_segments, x_offset, viewport_width, opacity)
    end
  end

  defp replaces_row?(layer_strip, layer_segments, x_offset, viewport_width, opacity) do
    opacity >= 1.0 and x_offset == 0 and Strip.width(layer_strip) >= viewport_width and
      not translucent?(layer_segments)
  end

  defp translucent?(segments) do
    Enum.any?(segments, fn %{style: style} ->
      Map.has_key?(style, :bg_alpha) or Map.has_key?(style, :fg_alpha)
    end)
  end

  defp composite_overlay(
         canvas_strip,
         layer_strip,
         layer_segments,
         x_offset,
         viewport_width,
         opacity
       ) do
    layer_width = Strip.width(layer_strip)
    actual_layer_width = min(x_offset + layer_width, viewport_width) - x_offset
    canvas_width = Strip.width(canvas_strip)

    if x_offset >= canvas_width or actual_layer_width <= 0 do
      canvas_strip
    else
      composite_segments_properly(
        canvas_strip.segments || [],
        layer_segments,
        x_offset,
        actual_layer_width,
        viewport_width,
        opacity
      )
    end
  end

  defp composite_segments_properly(
         canvas_segments,
         layer_segments,
         layer_x,
         layer_width,
         viewport_width,
         opacity
       ) do
    canvas_graphemes = build_grapheme_list(canvas_segments)
    layer_graphemes = build_grapheme_list(layer_segments)

    default_style = if canvas_segments != [], do: hd(canvas_segments).style, else: %{}

    layer_end = min(layer_x + layer_width, viewport_width)

    bounds = %{
      viewport_width: viewport_width,
      layer_x: layer_x,
      layer_end: layer_end,
      default_style: default_style,
      opacity: opacity
    }

    {final_graphemes, _, _} =
      composite_columns(0, bounds, canvas_graphemes, layer_graphemes, [])

    final_graphemes = Enum.reverse(final_graphemes)

    final_segments =
      final_graphemes
      |> Enum.chunk_by(fn {_col, _char, style} -> style end)
      |> Enum.map(fn chunk ->
        text = Enum.map_join(chunk, fn {_col, ch, _style} -> ch end)
        {_col, _char, style} = hd(chunk)
        Segment.new(text, style)
      end)

    Strip.new(final_segments)
  end

  defp composite_columns(col, %{viewport_width: width}, _canvas, _layer, acc) when col >= width do
    {acc, nil, nil}
  end

  defp composite_columns(col, bounds, canvas_graphemes, layer_graphemes, acc) do
    in_layer_region = col >= bounds.layer_x and col < bounds.layer_end

    {grapheme, style, width, new_canvas, new_layer} =
      resolve_column(
        in_layer_region,
        col,
        bounds.layer_x,
        canvas_graphemes,
        layer_graphemes,
        bounds.default_style,
        bounds.opacity
      )

    composite_columns(col + width, bounds, new_canvas, new_layer, [{col, grapheme, style} | acc])
  end

  @ansi_pattern ~r/\e\[[0-9;]*m/

  defp build_grapheme_list(segments) do
    {graphemes, _col} =
      Enum.reduce(segments, {[], 0}, fn segment, {acc, col} ->
        {part_acc, part_col, _} = add_segment_graphemes(segment, acc, col)
        {part_acc, part_col}
      end)

    Enum.reverse(graphemes)
  end

  defp add_segment_graphemes(%{text: text, style: style}, acc, col) do
    case :binary.match(text, "\e") do
      :nomatch ->
        expand_graphemes(text, acc, col, style)

      _ ->
        parts = Regex.split(@ansi_pattern, text, include_captures: true)
        process_ansi_parts(parts, acc, col, style, @ansi_pattern)
    end
  end

  defp process_ansi_parts(parts, acc, col, style, ansi_pattern) do
    Enum.reduce(parts, {acc, col, style}, fn part, {g_acc, current_col, current_style} ->
      if Regex.match?(ansi_pattern, part) do
        {g_acc, current_col, parse_ansi_to_style(part, current_style)}
      else
        expand_graphemes(part, g_acc, current_col, current_style)
      end
    end)
  end

  defp expand_graphemes(text, acc, col, style) do
    text
    |> String.graphemes()
    |> Enum.reduce({acc, col, style}, fn grapheme, {ga, cc, s} ->
      width = char_width(grapheme)
      {[{cc, grapheme, s, width} | ga], cc + width, s}
    end)
  end

  @ansi_style_map %{
    "1" => {:bold, true},
    "2" => {:dim, true},
    "3" => {:italic, true},
    "4" => {:underline, true},
    "7" => {:reverse, true}
  }

  @base_palette {
    {0, 0, 0},
    {205, 49, 49},
    {13, 188, 121},
    {229, 229, 16},
    {36, 114, 200},
    {188, 63, 188},
    {17, 168, 205},
    {229, 229, 229}
  }

  @bright_palette {
    {128, 128, 128},
    {241, 76, 76},
    {35, 209, 139},
    {245, 245, 67},
    {59, 142, 234},
    {214, 112, 214},
    {41, 184, 219},
    {255, 255, 255}
  }

  defp parse_ansi_to_style("\e[0m", _current_style), do: %{}
  defp parse_ansi_to_style("\e[m", _current_style), do: %{}

  defp parse_ansi_to_style(ansi_code, current_style) do
    ansi_code
    |> String.replace(~r/\e\[|m/, "")
    |> String.split(";")
    |> apply_codes(current_style)
  end

  defp apply_codes([], style), do: style

  defp apply_codes(["38", "2", r, g, b | rest], style) do
    apply_codes(rest, Map.put(style, :fg, rgb(r, g, b)))
  end

  defp apply_codes(["48", "2", r, g, b | rest], style) do
    apply_codes(rest, Map.put(style, :bg, rgb(r, g, b)))
  end

  defp apply_codes(["38", "5", n | rest], style) do
    apply_codes(rest, Map.put(style, :fg, xterm256(String.to_integer(n))))
  end

  defp apply_codes(["48", "5", n | rest], style) do
    apply_codes(rest, Map.put(style, :bg, xterm256(String.to_integer(n))))
  end

  defp apply_codes([code | rest], style), do: apply_codes(rest, apply_ansi_code(code, style))

  defp rgb(r, g, b), do: {String.to_integer(r), String.to_integer(g), String.to_integer(b)}

  defp apply_ansi_code("0", _style), do: %{}
  defp apply_ansi_code("39", style), do: Map.delete(style, :fg)
  defp apply_ansi_code("49", style), do: Map.delete(style, :bg)

  defp apply_ansi_code(code, style) do
    case Map.fetch(@ansi_style_map, code) do
      {:ok, {key, val}} -> Map.put(style, key, val)
      :error -> apply_palette_code(String.to_integer(code), style)
    end
  rescue
    ArgumentError -> style
  end

  defp apply_palette_code(n, style) when n in 30..37,
    do: Map.put(style, :fg, elem(@base_palette, n - 30))

  defp apply_palette_code(n, style) when n in 40..47,
    do: Map.put(style, :bg, elem(@base_palette, n - 40))

  defp apply_palette_code(n, style) when n in 90..97,
    do: Map.put(style, :fg, elem(@bright_palette, n - 90))

  defp apply_palette_code(n, style) when n in 100..107,
    do: Map.put(style, :bg, elem(@bright_palette, n - 100))

  defp apply_palette_code(_n, style), do: style

  defp xterm256(n) when n in 0..7, do: elem(@base_palette, n)
  defp xterm256(n) when n in 8..15, do: elem(@bright_palette, n - 8)

  defp xterm256(n) when n in 16..231 do
    c = n - 16
    {cube_step(div(c, 36)), cube_step(div(rem(c, 36), 6)), cube_step(rem(c, 6))}
  end

  defp xterm256(n) when n in 232..255 do
    level = 8 + (n - 232) * 10
    {level, level, level}
  end

  defp xterm256(_n), do: {0, 0, 0}

  defp cube_step(0), do: 0
  defp cube_step(i), do: 55 + i * 40

  defp resolve_column(
         true,
         col,
         layer_x,
         canvas_graphemes,
         layer_graphemes,
         default_style,
         opacity
       ) do
    layer_col = col - layer_x

    case pop_grapheme_at_col(layer_graphemes, layer_col) do
      {:ok, {g, s, w}, rest} ->
        beneath = style_at_col(canvas_graphemes, col, default_style)
        {_, new_canvas_rest} = skip_columns(canvas_graphemes, col, w)
        {g, blend_over(with_layer_opacity(s, opacity), beneath), w, new_canvas_rest, rest}

      :none ->
        pop_canvas_or_default(canvas_graphemes, col, layer_graphemes, default_style)
    end
  end

  defp resolve_column(
         false,
         col,
         _layer_x,
         canvas_graphemes,
         layer_graphemes,
         default_style,
         _opacity
       ) do
    pop_canvas_or_default(canvas_graphemes, col, layer_graphemes, default_style)
  end

  defp style_at_col(graphemes, col, default_style) do
    case pop_grapheme_at_col(graphemes, col) do
      {:ok, {_g, style, _w}, _rest} -> style
      :none -> default_style
    end
  end

  @doc """
  Composite a translucent style onto whatever it covers.

  An `:opacity` of `1.0` is opaque and `0.0` leaves only what is underneath.
  Returns `style` unchanged when it carries no `:opacity`; the key is removed from
  the returned style either way.
  """
  @spec blend_over(Segment.style(), Segment.style()) :: Segment.style()
  def blend_over(style, beneath) do
    style
    |> blend_channel_alpha(:bg, beneath)
    |> blend_channel_alpha(:fg, beneath)
    |> blend_layer_opacity(beneath)
  end

  defp blend_layer_opacity(style, beneath) do
    case Map.get(style, :opacity) do
      nil -> style
      alpha when is_number(alpha) and alpha >= 1.0 -> Map.delete(style, :opacity)
      alpha when is_number(alpha) -> apply_alpha(style, beneath, clamp_alpha(alpha))
      _ -> Map.delete(style, :opacity)
    end
  end

  defp blend_channel_alpha(style, key, beneath) do
    alpha_key = Segment.alpha_key(key)

    case Map.get(style, alpha_key) do
      nil ->
        style

      alpha when is_number(alpha) ->
        style |> blend_channel(key, beneath, clamp_alpha(alpha)) |> Map.delete(alpha_key)

      _ ->
        Map.delete(style, alpha_key)
    end
  end

  defp apply_alpha(style, beneath, alpha) do
    style
    |> Map.delete(:opacity)
    |> blend_channel(:bg, beneath, alpha)
    |> blend_channel(:fg, beneath, alpha)
  end

  defp blend_channel(style, key, beneath, alpha) do
    under = Map.get(beneath, key) || Map.get(beneath, :bg)

    case {Map.get(style, key), under} do
      {nil, _} -> style
      {_over, nil} -> style
      {over, below} -> Map.put(style, key, mix(over, below, alpha))
    end
  end

  defp mix({r1, g1, b1}, {r2, g2, b2}, alpha) do
    {round(r2 + (r1 - r2) * alpha), round(g2 + (g1 - g2) * alpha), round(b2 + (b1 - b2) * alpha)}
  end

  defp mix(over, _below, _alpha), do: over

  defp clamp_alpha(alpha), do: alpha |> max(0.0) |> min(1.0)

  defp with_layer_opacity(style, opacity) when opacity >= 1.0, do: style
  defp with_layer_opacity(style, opacity), do: Map.put_new(style, :opacity, opacity)

  defp pop_canvas_or_default(canvas_graphemes, col, layer_graphemes, default_style) do
    case pop_grapheme_at_col(canvas_graphemes, col) do
      {:ok, {g, s, w}, rest} -> {g, s, w, rest, layer_graphemes}
      :none -> {" ", default_style, 1, canvas_graphemes, layer_graphemes}
    end
  end

  defp pop_grapheme_at_col([{col, grapheme, style, width} | rest], target_col)
       when col == target_col do
    {:ok, {grapheme, style, width}, rest}
  end

  defp pop_grapheme_at_col([{col, _grapheme, _style, width} | rest], target_col)
       when col + width <= target_col do
    pop_grapheme_at_col(rest, target_col)
  end

  defp pop_grapheme_at_col(_, _), do: :none

  defp skip_columns(graphemes, start_col, width_to_skip) do
    end_col = start_col + width_to_skip
    remaining = Enum.drop_while(graphemes, fn {col, _g, _s, w} -> col + w <= end_col end)
    {:ok, remaining}
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)
end
