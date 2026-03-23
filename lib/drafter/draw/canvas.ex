defmodule Drafter.Draw.Canvas do
  @moduledoc """
  Coordinate-based drawing surface for terminal primitives.

  A canvas stores a sparse map of `{x, y}` cells, each holding a character and
  style. Drawing operations (`draw_hline/6`, `draw_vline/6`, `draw_line/6`,
  `draw_rect/7`, `fill_rect/7`, `draw_text/5`) are composable and return an
  updated canvas. Call `to_strips/1` to convert the canvas to a list of
  `Drafter.Draw.Strip` structs for rendering, or `merge/4` to composite one
  canvas onto another at an offset.
  """

  alias Drafter.Draw.{Segment, Strip, BoxDrawing}

  @type coordinate :: {non_neg_integer(), non_neg_integer()}
  @type style :: Segment.style()
  
  @type cell :: %{
    char: String.t(),
    style: style()
  }

  @type t :: %__MODULE__{
    width: pos_integer(),
    height: pos_integer(),
    cells: %{coordinate() => cell()}
  }

  defstruct [:width, :height, cells: %{}]

  @doc "Create a new canvas with specified dimensions"
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(width, height) when width > 0 and height > 0 do
    %__MODULE__{
      width: width,
      height: height,
      cells: %{}
    }
  end

  @doc "Set character at specific position"
  @spec set_char(t(), non_neg_integer(), non_neg_integer(), String.t(), style()) :: t()
  def set_char(%__MODULE__{width: width, height: height} = canvas, x, y, char, style \\ %{}) do
    if x < width and y < height do
      cell = %{char: char, style: style}
      cells = Map.put(canvas.cells, {x, y}, cell)
      %{canvas | cells: cells}
    else
      canvas
    end
  end

  @doc "Get character at specific position"
  @spec get_char(t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def get_char(%__MODULE__{cells: cells}, x, y) do
    case Map.get(cells, {x, y}) do
      %{char: char} -> char
      nil -> " "
    end
  end

  @doc "Draw horizontal line"
  @spec draw_hline(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), BoxDrawing.line_type(), style()) :: t()
  def draw_hline(canvas, x, y, length, line_style \\ :light, style \\ %{}) do
    char = BoxDrawing.get_char(line_style, :horizontal)
    draw_line_chars(canvas, x, y, length, 1, char, style)
  end

  @doc "Draw vertical line"
  @spec draw_vline(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), BoxDrawing.line_type(), style()) :: t()
  def draw_vline(canvas, x, y, length, line_style \\ :light, style \\ %{}) do
    char = BoxDrawing.get_char(line_style, :vertical)
    draw_line_chars(canvas, x, y, 1, length, char, style)
  end

  @doc "Draw a line from point A to point B"
  @spec draw_line(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), style()) :: t()
  def draw_line(canvas, x1, y1, x2, y2, style \\ %{}) do
    points = line_points(x1, y1, x2, y2)
    Enum.reduce(points, canvas, fn {x, y}, acc ->
      set_char(acc, x, y, "█", style)
    end)
  end

  @doc "Draw a rectangle outline"
  @spec draw_rect(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), BoxDrawing.line_type(), style()) :: t()
  def draw_rect(canvas, x, y, width, height, line_style \\ :light, style \\ %{}) do
    if width < 2 or height < 2 do
      canvas
    else
      chars = BoxDrawing.get_chars(line_style)
      
      canvas
      |> set_char(x, y, chars.top_left, style)
      |> draw_hline(x + 1, y, width - 2, line_style, style)
      |> set_char(x + width - 1, y, chars.top_right, style)
      |> draw_vline(x, y + 1, height - 2, line_style, style)
      |> draw_vline(x + width - 1, y + 1, height - 2, line_style, style)
      |> set_char(x, y + height - 1, chars.bottom_left, style)
      |> draw_hline(x + 1, y + height - 1, width - 2, line_style, style)
      |> set_char(x + width - 1, y + height - 1, chars.bottom_right, style)
    end
  end

  @doc "Fill a rectangle with character"
  @spec fill_rect(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), String.t(), style()) :: t()
  def fill_rect(canvas, x, y, width, height, char \\ " ", style \\ %{}) do
    Enum.reduce(0..(height - 1), canvas, fn dy, acc_canvas ->
      Enum.reduce(0..(width - 1), acc_canvas, fn dx, acc ->
        set_char(acc, x + dx, y + dy, char, style)
      end)
    end)
  end

  @doc "Draw text at position"
  @spec draw_text(t(), non_neg_integer(), non_neg_integer(), String.t(), style()) :: t()
  def draw_text(canvas, x, y, text, style \\ %{}) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {char, offset}, acc ->
      set_char(acc, x + offset, y, char, style)
    end)
  end

  @doc "Clear entire canvas"
  @spec clear(t()) :: t()
  def clear(canvas) do
    %{canvas | cells: %{}}
  end

  @doc "Clear rectangular area"
  @spec clear_rect(t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def clear_rect(canvas, x, y, width, height) do
    cells = Enum.reduce(0..(height - 1), canvas.cells, fn dy, acc_cells ->
      Enum.reduce(0..(width - 1), acc_cells, fn dx, acc ->
        Map.delete(acc, {x + dx, y + dy})
      end)
    end)
    
    %{canvas | cells: cells}
  end

  @doc "Convert canvas to strips for rendering"
  @spec to_strips(t()) :: [Strip.t()]
  def to_strips(%__MODULE__{width: width, height: height, cells: cells}) do
    Enum.map(0..(height - 1), fn y ->
      segments = build_line_segments(cells, y, width)
      Strip.new(segments)
    end)
  end

  @doc "Merge another canvas onto this one"
  @spec merge(t(), t(), non_neg_integer(), non_neg_integer()) :: t()
  def merge(base_canvas, overlay_canvas, offset_x \\ 0, offset_y \\ 0) do
    Enum.reduce(overlay_canvas.cells, base_canvas, fn {{x, y}, cell}, acc ->
      new_x = x + offset_x
      new_y = y + offset_y
      
      if new_x < acc.width and new_y < acc.height do
        cells = Map.put(acc.cells, {new_x, new_y}, cell)
        %{acc | cells: cells}
      else
        acc
      end
    end)
  end

  defp draw_line_chars(canvas, x, y, width, height, char, style) do
    Enum.reduce(0..(height - 1), canvas, fn dy, acc_canvas ->
      Enum.reduce(0..(width - 1), acc_canvas, fn dx, acc ->
        set_char(acc, x + dx, y + dy, char, style)
      end)
    end)
  end

  defp line_points(x1, y1, x2, y2) do
    ctx = %{
      x2: x2,
      y2: y2,
      dx: abs(x2 - x1),
      dy: abs(y2 - y1),
      sx: if(x1 < x2, do: 1, else: -1),
      sy: if(y1 < y2, do: 1, else: -1)
    }

    trace_line({x1, y1, ctx.dx - ctx.dy}, ctx, [])
  end

  defp trace_line({x, y, err}, ctx, points) do
    points = [{x, y} | points]

    if x == ctx.x2 and y == ctx.y2 do
      Enum.reverse(points)
    else
      e2 = 2 * err
      {new_x, new_err} = if e2 > -ctx.dy, do: {x + ctx.sx, err - ctx.dy}, else: {x, err}
      {new_y, final_err} = if e2 < ctx.dx, do: {y + ctx.sy, new_err + ctx.dx}, else: {y, new_err}

      trace_line({new_x, new_y, final_err}, ctx, points)
    end
  end

  defp build_line_segments(cells, y, width) do
    0..(width - 1)
    |> Enum.map(fn x ->
      case Map.get(cells, {x, y}) do
        %{char: char, style: style} -> Segment.new(char, style)
        nil -> Segment.plain(" ")
      end
    end)
    |> combine_adjacent_segments([])
  end

  defp combine_adjacent_segments([], acc), do: Enum.reverse(acc)
  
  defp combine_adjacent_segments([segment | rest], []) do
    combine_adjacent_segments(rest, [segment])
  end
  
  defp combine_adjacent_segments([segment | rest], [last | acc_rest] = acc) do
    if segment.style == last.style do
      combined = %{last | 
        text: last.text <> segment.text,
        width: last.width + segment.width
      }
      combine_adjacent_segments(rest, [combined | acc_rest])
    else
      combine_adjacent_segments(rest, [segment | acc])
    end
  end
end