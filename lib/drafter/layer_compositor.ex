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
  def create_layer(id, strips, bounds, z_index \\ 0) do
    %{
      id: id,
      strips: strips || [],
      bounds: bounds,
      z_index: z_index
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
    prepared = layers |> Enum.sort_by(& &1.z_index) |> Enum.map(&prepare_layer/1)
    blank = blank_strip(viewport)
    prev_tuple = List.to_tuple(previous_composite)
    prev_count = tuple_size(prev_tuple)

    new_rows =
      Enum.reduce(dirty_rows, %{}, fn row, acc ->
        Map.put(acc, row, compose_row(prepared, viewport, row, blank))
      end)

    Enum.map(0..(viewport.height - 1), fn row ->
      pick_row(Map.get(new_rows, row), row, prev_tuple, prev_count, blank)
    end)
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
      blank: bounds_blank(layer.bounds)
    }
  end

  defp compose_row(prepared, viewport, row, blank) do
    Enum.reduce(prepared, blank, fn %{tuple: tuple, count: count, bounds: bounds, blank: layer_blank}, acc ->
      layer_row = row - bounds.y

      in_bounds =
        row >= bounds.y and row < bounds.y + bounds.height and bounds.x < viewport.width

      cond do
        in_bounds and layer_row < count ->
          composite_strips_at_position(acc, elem(tuple, layer_row), bounds.x, viewport.width)

        in_bounds ->
          composite_strips_at_position(acc, layer_blank, bounds.x, viewport.width)

        true ->
          acc
      end
    end)
  end

  defp bounds_blank(bounds) do
    width = max(Map.get(bounds, :width, 0), 0)
    Strip.new([Segment.new(String.duplicate(" ", width), %{})])
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

  @doc """
  Create a widget layer for interactive elements.
  """
  @container_modules [
    Drafter.Widget.Box,
    Drafter.Widget.Card,
    Drafter.Widget.Collapsible,
    Drafter.Widget.ScrollableContainer
  ]

  def widget_layer(widget_id, strips, bounds, z_base \\ 0, widget_module \\ nil) do
    z_index =
      cond do
        :erlang.atom_to_binary(widget_id) |> String.starts_with?("footer") -> z_base + 50
        :erlang.atom_to_binary(widget_id) |> String.starts_with?("header") -> z_base + 40
        widget_module in @container_modules -> z_base + 10
        true -> z_base + 20
      end

    create_layer(widget_id, strips, bounds, z_index)
  end

  @doc """
  Create a chrome layer for UI decorations.
  """
  def chrome_layer(id, strips, bounds) do
    create_layer(id, strips, bounds, 30)
  end

  # Private functions

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
    layer_blank = bounds_blank(bounds)

    canvas
    |> Enum.with_index()
    |> Enum.map(fn {canvas_strip, row_index} ->
      layer_row = row_index - bounds.y

      in_bounds =
        row_index >= bounds.y and row_index < bounds.y + bounds.height and
          bounds.x < viewport.width

      cond do
        in_bounds and layer_row < layer_count ->
          composite_strips_at_position(canvas_strip, elem(layer_tuple, layer_row), bounds.x, viewport.width)

        in_bounds ->
          composite_strips_at_position(canvas_strip, layer_blank, bounds.x, viewport.width)

        true ->
          canvas_strip
      end
    end)
  end

  defp composite_strips_at_position(canvas_strip, layer_strip, x_offset, viewport_width) do
    layer_segments = layer_strip.segments || []

    cond do
      layer_segments == [] or x_offset < 0 or x_offset >= viewport_width ->
        canvas_strip

      x_offset == 0 and Strip.width(layer_strip) >= viewport_width ->
        Strip.crop(layer_strip, viewport_width)

      true ->
        composite_overlay(canvas_strip, layer_strip, layer_segments, x_offset, viewport_width)
    end
  end

  defp composite_overlay(canvas_strip, layer_strip, layer_segments, x_offset, viewport_width) do
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
        viewport_width
      )
    end
  end

  defp composite_segments_properly(
         canvas_segments,
         layer_segments,
         layer_x,
         layer_width,
         viewport_width
       ) do
    canvas_graphemes = build_grapheme_list(canvas_segments)
    layer_graphemes = build_grapheme_list(layer_segments)

    default_style = if canvas_segments != [], do: hd(canvas_segments).style, else: %{}

    layer_end = min(layer_x + layer_width, viewport_width)

    {final_graphemes, _, _} =
      composite_columns(
        0,
        viewport_width,
        layer_x,
        layer_end,
        canvas_graphemes,
        layer_graphemes,
        default_style,
        []
      )

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

  defp composite_columns(
         col,
         viewport_width,
         _layer_x,
         _layer_end,
         _canvas,
         _layer,
         _default_style,
         acc
       )
       when col >= viewport_width do
    {acc, nil, nil}
  end

  defp composite_columns(
         col,
         viewport_width,
         layer_x,
         layer_end,
         canvas_graphemes,
         layer_graphemes,
         default_style,
         acc
       ) do
    in_layer_region = col >= layer_x and col < layer_end

    {grapheme, style, width, new_canvas, new_layer} =
      resolve_column(
        in_layer_region,
        col,
        layer_x,
        canvas_graphemes,
        layer_graphemes,
        default_style
      )

    new_acc = [{col, grapheme, style} | acc]
    next_col = col + width

    composite_columns(
      next_col,
      viewport_width,
      layer_x,
      layer_end,
      new_canvas,
      new_layer,
      default_style,
      new_acc
    )
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

  @ansi_fg_map %{
    "30" => {0, 0, 0},
    "31" => {205, 49, 49},
    "32" => {13, 188, 121},
    "33" => {229, 229, 16},
    "34" => {36, 114, 200},
    "35" => {188, 63, 188},
    "36" => {17, 168, 205},
    "37" => {229, 229, 229},
    "90" => {128, 128, 128}
  }

  defp parse_ansi_to_style("\e[0m", _current_style), do: %{}

  defp parse_ansi_to_style(ansi_code, current_style) do
    code_str = String.replace(ansi_code, ~r/\e\[|m/, "")
    codes = String.split(code_str, ";")

    Enum.reduce(codes, current_style, fn code, style ->
      apply_ansi_code(code, codes, style)
    end)
  end

  defp apply_ansi_code(code, codes, style) do
    cond do
      Map.has_key?(@ansi_style_map, code) ->
        {key, val} = Map.fetch!(@ansi_style_map, code)
        Map.put(style, key, val)

      Map.has_key?(@ansi_fg_map, code) ->
        Map.put(style, :fg, Map.fetch!(@ansi_fg_map, code))

      true ->
        parse_extended_color(code, codes, style)
    end
  end

  defp parse_extended_color(_code, codes, style) do
    case codes do
      ["38", "2", r, g, b | _] ->
        Map.put(style, :fg, {String.to_integer(r), String.to_integer(g), String.to_integer(b)})

      ["48", "2", r, g, b | _] ->
        Map.put(style, :bg, {String.to_integer(r), String.to_integer(g), String.to_integer(b)})

      _ ->
        style
    end
  end

  defp resolve_column(true, col, layer_x, canvas_graphemes, layer_graphemes, default_style) do
    layer_col = col - layer_x

    case pop_grapheme_at_col(layer_graphemes, layer_col) do
      {:ok, {g, s, w}, rest} ->
        {_, new_canvas_rest} = skip_columns(canvas_graphemes, col, w)
        {g, s, w, new_canvas_rest, rest}

      :none ->
        pop_canvas_or_default(canvas_graphemes, col, layer_graphemes, default_style)
    end
  end

  defp resolve_column(false, col, _layer_x, canvas_graphemes, layer_graphemes, default_style) do
    pop_canvas_or_default(canvas_graphemes, col, layer_graphemes, default_style)
  end

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
