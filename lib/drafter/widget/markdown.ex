defmodule Drafter.Widget.Markdown do
  @moduledoc """
  Renders a subset of Markdown to the terminal with themed styling.

  Supported syntax: `#` and `##` headings, `**bold**`, `*italic*`, and
  `` `inline code` ``. Block elements are styled via the theme system using
  the `:h1`, `:h2`, and `:text` theme parts. A configurable horizontal
  padding is applied inside the widget boundaries.

  ## Options

    * `:content` - Markdown string to render (default `""`)
    * `:padding` - left and right padding in columns (default `1`)
    * `:style` - base style map merged with computed theme styles

  ## Usage

      markdown(content: "# Title\\n\\nSome **bold** and *italic* text with `code`.")
      markdown(content: readme_text, padding: 2)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  def mount(props) do
    %{
      content: Map.get(props, :content, ""),
      style: Map.get(props, :style, %{}),
      padding: Map.get(props, :padding, 1)
    }
  end

  def render(state, rect) do
    render_markdown(state, rect)
  end

  def update(props, state) do
    Map.merge(state, props)
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_markdown(state, rect) do
    padding = state.padding
    content_width = rect.width - padding * 2

    if content_width <= 0 do
      []
    else
      lines = parse_markdown(state.content, content_width)

      lines
      |> Enum.map(fn {segments_spec, base_part} ->
        base_computed = Computed.for_part(:markdown, state, base_part)
        base_style = Map.merge(state.style, Computed.to_segment_style(base_computed))

        segments =
          case segments_spec do
            text when is_binary(text) ->
              [Segment.new(text, base_style)]

            specs when is_list(specs) ->
              Enum.map(specs, fn {text, inline_style} ->
                final_style = apply_inline_style(base_style, inline_style)
                Segment.new(text, final_style)
              end)
          end

        if padding > 0 do
          padding_segment = Segment.new(String.duplicate(" ", padding), base_style)
          Strip.new([padding_segment] ++ segments ++ [padding_segment])
        else
          Strip.new(segments)
        end
      end)
    end
  end

  def preferred_height(args, opts) do
    lines = String.split(args || "", "\n") |> length()
    Keyword.get(opts, :height, max(lines, 3))
  end

  def component_tag, do: :markdown

  def from_component_opts(content, opts) do
    %{
      content: content || Keyword.get(opts, :content, ""),
      style: Keyword.get(opts, :style, %{}),
      padding: Keyword.get(opts, :padding, 1)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{content: mount_props.content}
  end

  defp apply_inline_style(base_style, :bold), do: Map.put(base_style, :bold, true)
  defp apply_inline_style(base_style, :italic), do: Map.put(base_style, :italic, true)
  defp apply_inline_style(base_style, :code),
    do: Map.merge(base_style, %{bg: {60, 60, 60}, fg: {200, 200, 100}})
  defp apply_inline_style(base_style, :normal), do: base_style

  defp parse_markdown(content, width) do
    content
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      parse_line(line, width)
    end)
  end

  defp parse_line("## " <> heading, _width) do
    segments = parse_inline_formatting(heading)
    [{segments, :h2}]
  end

  defp parse_line("# " <> heading, _width) do
    segments = parse_inline_formatting(heading)
    [{segments, :h1}]
  end

  defp parse_line("", _width) do
    [{[{"", :normal}], :text}]
  end

  defp parse_line(line, _width) do
    segments = parse_inline_formatting(line)
    [{segments, :text}]
  end

  defp parse_inline_formatting(text) do
    pattern = ~r/(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/

    parts = Regex.split(pattern, text, include_captures: true)

    Enum.flat_map(parts, fn part ->
      cond do
        part == "" ->
          []

        String.starts_with?(part, "**") and String.ends_with?(part, "**") ->
          inner = String.slice(part, 2..-3//1)
          [{inner, :bold}]

        String.starts_with?(part, "*") and String.ends_with?(part, "*") ->
          inner = String.slice(part, 1..-2//1)
          [{inner, :italic}]

        String.starts_with?(part, "`") and String.ends_with?(part, "`") ->
          inner = String.slice(part, 1..-2//1)
          [{inner, :code}]

        true ->
          [{part, :normal}]
      end
    end)
  end
end
