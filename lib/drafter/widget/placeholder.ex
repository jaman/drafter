defmodule Drafter.Widget.Placeholder do
  @moduledoc """
  Renders a coloured placeholder block useful during development and layout design.

  Each placeholder is assigned a distinct pastel background colour derived from
  a number embedded in its text label. Text is centered vertically and horizontally
  inside the block, and an optional border can be drawn around the content area.

  ## Options

    * `:text` - label text displayed in the center (default `"Placeholder"`); embedding a digit selects the colour
    * `:padding` - horizontal padding in columns (default `2`)
    * `:align` - text alignment: `:left`, `:center` (default), `:right`
    * `:border` - draw a box border around the content: `true` / `false` (default)
    * `:style` - explicit style map; overrides the auto-generated background and foreground

  ## Usage

      placeholder("Placeholder 1")
      placeholder("Placeholder 2", border: true, padding: 4)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}

  @pastel_colors [
    # Purple
    {77, 17, 68},
    # Pink  
    {94, 34, 51},
    # Red
    {111, 60, 60},
    # Brown
    {128, 85, 43},
    # Yellow-green
    {128, 119, 9},
    # Green
    {85, 119, 51},
    # Teal
    {43, 119, 77},
    # Cyan
    {26, 111, 102},
    # Light blue
    {9, 102, 111},
    # Blue
    {9, 85, 111},
    # Dark blue
    {34, 60, 102},
    # Purple-blue
    {60, 34, 85},
    # Magenta
    {85, 34, 60},
    # Dark red
    {102, 34, 34},
    # Orange
    {102, 68, 34},
    # Olive
    {85, 85, 34}
  ]

  def mount(props) do
    # Get color based on placeholder number
    placeholder_text = Map.get(props, :text, "Placeholder")
    color_index = extract_number_from_text(placeholder_text) - 1
    bg_color = Enum.at(@pastel_colors, rem(color_index, length(@pastel_colors)))

    # Calculate contrasting text color
    fg_color = contrasting_text_color(bg_color)

    %{
      text: placeholder_text,
      style: Map.get(props, :style, %{fg: fg_color, bg: bg_color}),
      padding: Map.get(props, :padding, 2),
      align: Map.get(props, :align, :center),
      border: Map.get(props, :border, false)
    }
  end

  def render(state, rect) do
    render_placeholder(state, rect)
  end

  def update(props, state) do
    Map.merge(state, props)
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 3)

  def component_tag, do: :placeholder

  def from_component_opts(_args, opts) do
    %{
      text: Keyword.get(opts, :label, Keyword.get(opts, :text, "Placeholder")),
      padding: Keyword.get(opts, :padding, 2),
      align: Keyword.get(opts, :align, :center),
      border: Keyword.get(opts, :border, false),
      style: Keyword.get(opts, :style, %{})
    }
  end

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
    # Simple box border using ASCII characters
    top_border = "┌" <> String.duplicate("─", content_width) <> "┐"
    bottom_border = "└" <> String.duplicate("─", content_width) <> "┘"

    text_lines = wrap_text(state.text, content_width - 2)
    text_y = div(content_height - 2, 2)

    0..(content_height + 1)
    |> Enum.map(fn row ->
      cond do
        row == 0 ->
          # Top border
          segment = Segment.new(top_border, state.style)

          if padding > 0 do
            padding_segment = Segment.new(String.duplicate(" ", padding))
            Strip.new([padding_segment, segment, padding_segment])
          else
            Strip.new([segment])
          end

        row == content_height + 1 ->
          # Bottom border
          segment = Segment.new(bottom_border, state.style)

          if padding > 0 do
            padding_segment = Segment.new(String.duplicate(" ", padding))
            Strip.new([padding_segment, segment, padding_segment])
          else
            Strip.new([segment])
          end

        row == text_y + 1 and not Enum.empty?(text_lines) ->
          # Text content
          text = List.first(text_lines)
          padded_text = String.pad_trailing(text, content_width - 2)
          line_content = "│" <> padded_text <> "│"
          segment = Segment.new(line_content, state.style)

          if padding > 0 do
            padding_segment = Segment.new(String.duplicate(" ", padding))
            Strip.new([padding_segment, segment, padding_segment])
          else
            Strip.new([segment])
          end

        true ->
          # Empty content with side borders
          empty_content = "│" <> String.duplicate(" ", content_width) <> "│"
          segment = Segment.new(empty_content, state.style)

          if padding > 0 do
            padding_segment = Segment.new(String.duplicate(" ", padding))
            Strip.new([padding_segment, segment, padding_segment])
          else
            Strip.new([segment])
          end
      end
    end)
  end

  defp render_without_border(state, content_width, content_height, padding) do
    text_lines = wrap_text(state.text, content_width)
    center_row = div(content_height, 2)

    0..(content_height - 1)
    |> Enum.map(fn row ->
      line_text =
        if row == center_row and not Enum.empty?(text_lines) do
          # Center the text in the middle row
          text = List.first(text_lines)
          text_length = String.length(text)

          if text_length <= content_width do
            padding_left = div(content_width - text_length, 2)
            padding_right = content_width - text_length - padding_left
            String.duplicate(" ", padding_left) <> text <> String.duplicate(" ", padding_right)
          else
            String.slice(text, 0, content_width)
          end
        else
          # Fill with background-colored spaces
          String.duplicate(" ", content_width)
        end

      segment = Segment.new(line_text, state.style)

      if padding > 0 do
        padding_segment = Segment.new(String.duplicate(" ", padding), state.style)
        Strip.new([padding_segment, segment, padding_segment])
      else
        Strip.new([segment])
      end
    end)
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
    # Calculate luminance
    luminance = 0.299 * r + 0.587 * g + 0.114 * b

    # Use light text on dark backgrounds, dark text on light backgrounds
    if luminance < 128 do
      # Light text
      {230, 230, 230}
    else
      # Dark text
      {30, 30, 30}
    end
  end
end
