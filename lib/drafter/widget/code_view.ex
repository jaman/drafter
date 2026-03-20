defmodule Drafter.Widget.CodeView do
  @moduledoc """
  Renders a scrollable, syntax-highlighted code viewer with keyboard and drag navigation.

  Source text is provided directly via `:source` or loaded from disk via `:path`.
  When `:path` is given the file is read at mount time and the language is inferred
  from the extension when possible. Syntax highlighting is performed by the
  the `tree-sitter` CLI when available, falling back to the built-in
  Elixir highlighter for `.ex` and `.exs` files.

  Keyboard controls (when focused):
  - `↑` / `↓` — scroll one line
  - `Page Up` / `Page Down` — scroll ten lines
  - `←` / `→` — horizontal scroll by five columns
  - Mouse wheel — vertical scroll by three lines
  - Click and drag — pan both axes simultaneously

  ## Options

    * `:source` - source code string to display
    * `:path` - file path to load; file is read at mount and on path change
    * `:language` - syntax language atom, e.g. `:elixir`, `:exs` (default `:text`)
    * `:show_line_numbers` - display a line number gutter: `true` / `false` (default)

  ## Usage

      code_view(source: File.read!("lib/my_app.ex"), language: :elixir, show_line_numbers: true)
      code_view(path: "/etc/hosts")
  """

  use Drafter.Widget,
    handles: [:scroll, :keyboard, :drag],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager
  alias Drafter.Syntax.{TSFeatures, Highlighter, ElixirHighlighter}

  @page_size 10

  defstruct [
    :lines,
    :highlights,
    :language,
    :path,
    :scroll_offset,
    :h_scroll_offset,
    :focused,
    :show_line_numbers,
    :hex_view
  ]

  @impl Drafter.Widget
  def mount(props) do
    path = Map.get(props, :path)
    language = Map.get(props, :language, :text)
    show_line_numbers = Map.get(props, :show_line_numbers, false)
    hex_view = Map.get(props, :hex_view, false)

    {lines, highlights} = load_content(path, Map.get(props, :source, ""), language, hex_view)

    %__MODULE__{
      lines: lines,
      highlights: highlights,
      language: language,
      path: path,
      scroll_offset: 0,
      h_scroll_offset: 0,
      focused: false,
      show_line_numbers: show_line_numbers,
      hex_view: hex_view
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    theme = ThemeManager.get_current_theme()
    syntax_colors = theme.syntax || %{}
    line_num_width = if state.show_line_numbers, do: line_number_width(length(state.lines)), else: 0
    content_width = max(1, rect.width - line_num_width)

    state.lines
    |> Enum.with_index(1)
    |> Enum.drop(state.scroll_offset)
    |> Enum.take(rect.height)
    |> Enum.map(fn {line, line_number} ->
      render_line(line, line_number, line_num_width, content_width, state.highlights, syntax_colors, theme, state.h_scroll_offset)
    end)
  end

  @impl Drafter.Widget
  def handle_scroll(:up, state) do
    {:ok, %{state | scroll_offset: max(0, state.scroll_offset - 3)}}
  end

  def handle_scroll(:down, state) do
    max_offset = max(0, length(state.lines) - 1)
    {:ok, %{state | scroll_offset: min(max_offset, state.scroll_offset + 3)}}
  end

  @impl Drafter.Widget
  def handle_key(:up, state) do
    {:ok, %{state | scroll_offset: max(0, state.scroll_offset - 1)}}
  end

  def handle_key(:down, state) do
    max_offset = max(0, length(state.lines) - 1)
    {:ok, %{state | scroll_offset: min(max_offset, state.scroll_offset + 1)}}
  end

  def handle_key(:page_up, state) do
    {:ok, %{state | scroll_offset: max(0, state.scroll_offset - @page_size)}}
  end

  def handle_key(:page_down, state) do
    max_offset = max(0, length(state.lines) - 1)
    {:ok, %{state | scroll_offset: min(max_offset, state.scroll_offset + @page_size)}}
  end

  def handle_key(:left, state) do
    {:ok, %{state | h_scroll_offset: max(0, state.h_scroll_offset - 5)}}
  end

  def handle_key(:right, state) do
    max_line_length = state.lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    max_h_offset = max(0, max_line_length - 20)
    {:ok, %{state | h_scroll_offset: min(max_h_offset, state.h_scroll_offset + 5)}}
  end

  def handle_key(_key, state), do: {:ok, state}

  @impl Drafter.Widget
  def handle_drag(_x, _y, state), do: {:ok, state}

  @impl Drafter.Widget
  def update(props, state) do
    path = Map.get(props, :path, state.path)
    hex_view = Map.get(props, :hex_view, state.hex_view)
    source = Map.get(props, :source)
    path_changed = path != state.path
    hex_changed = hex_view != state.hex_view
    source_changed = source && source != "" && source != Enum.join(state.lines, "\n")

    if path_changed || source_changed || hex_changed do
      language = Map.get(props, :language, state.language)
      raw_source =
        cond do
          path && (path_changed || hex_changed) ->
            case File.read(path) do
              {:ok, content} -> content
              _ -> ""
            end
          source -> source
          true -> Enum.join(state.lines, "\n")
        end
      {lines, highlights} = content_to_lines(raw_source, language, path, hex_view)

      %{state |
        lines: lines,
        highlights: highlights,
        language: language,
        path: path,
        hex_view: hex_view,
        scroll_offset: 0,
        h_scroll_offset: 0
      }
    else
      state
    end
  end

  defp load_content(nil, source, language, hex_view) do
    content_to_lines(source, language, nil, hex_view)
  end

  defp load_content(path, _source, language, hex_view) do
    raw =
      case File.read(path) do
        {:ok, content} -> content
        _ -> ""
      end
    content_to_lines(raw, language, path, hex_view)
  end

  defp content_to_lines(raw, _language, _path, true) do
    lines = hex_dump_lines(raw)
    {lines, nil}
  end

  defp content_to_lines(raw, language, path, _hex_view) do
    lines = String.split(raw, "\n")
    highlights = compute_highlights(raw, language, path)
    {lines, highlights}
  end

  defp hex_dump_lines(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {row_bytes, row_index} ->
      offset = Integer.to_string(row_index * 16, 16) |> String.pad_leading(8, "0")
      hex_left =
        row_bytes
        |> Enum.take(8)
        |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
        |> Enum.join(" ")
      hex_right =
        row_bytes
        |> Enum.drop(8)
        |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
        |> Enum.join(" ")
      hex_left_padded = String.pad_trailing(hex_left, 23)
      hex_right_padded = String.pad_trailing(hex_right, 23)
      ascii =
        row_bytes
        |> Enum.map(fn b -> if b >= 32 and b <= 126, do: <<b>>, else: "." end)
        |> Enum.join()
      "#{offset}  #{hex_left_padded}  #{hex_right_padded}  |#{ascii}|"
    end)
  end

  defp compute_highlights(source, language, path) do
    captures =
      cond do
        path && Drafter.Syntax.TreeSitterDaemon.available?() ->
          Drafter.Syntax.TreeSitterDaemon.highlight_file(path)

        Drafter.Syntax.TreeSitterDaemon.available?() ->
          Drafter.Syntax.TreeSitterDaemon.highlight(source, language)

        language in [:elixir, :exs] ->
          ElixirHighlighter.highlight(source, language)

        true ->
          []
      end

    if captures == [], do: nil, else: TSFeatures.build(captures)
  end

  defp line_number_width(total_lines) do
    total_lines |> Integer.to_string() |> String.length() |> Kernel.+(1)
  end

  defp render_line(line, line_number, line_num_width, content_width, highlights, syntax_colors, theme, h_scroll_offset) do
    bg = theme.background
    num_segments =
      if line_num_width > 0 do
        num_str = line_number |> Integer.to_string() |> String.pad_leading(line_num_width - 1)
        muted_color = theme.text_muted || {128, 128, 128}
        [Segment.new(num_str <> " ", %{fg: muted_color, bg: bg})]
      else
        []
      end

    spans = if highlights, do: TSFeatures.get_spans(highlights, line_number), else: []
    content_segments = build_content_segments(line, spans, syntax_colors, theme, bg)
    content_segments = apply_h_scroll(content_segments, h_scroll_offset, content_width, bg)
    Strip.new(num_segments ++ content_segments)
  end

  defp build_content_segments(line, [], syntax_colors, theme, bg) do
    default_color = Map.get(syntax_colors, :default, theme.foreground)
    [Segment.new(line, %{fg: default_color, bg: bg})]
  end

  defp build_content_segments(line, spans, syntax_colors, theme, bg) do
    default_color = Map.get(syntax_colors, :default, theme.foreground)
    line_length = String.length(line)

    sorted_spans =
      spans
      |> Enum.map(fn
        {sc, :eol, type} -> {sc, line_length, type}
        span -> span
      end)
      |> Enum.sort_by(fn {sc, _ec, _type} -> sc end)

    {segments, last_pos} =
      Enum.reduce(sorted_spans, {[], 0}, fn {sc, ec, capture_type}, {segs, pos} ->
        sc = max(sc, pos)
        ec = min(ec, line_length)

        segs =
          if sc > pos do
            gap_text = String.slice(line, pos, sc - pos)
            segs ++ [Segment.new(gap_text, %{fg: default_color, bg: bg})]
          else
            segs
          end

        segs =
          if ec > sc do
            span_text = String.slice(line, sc, ec - sc)
            color = Highlighter.resolve_color(Atom.to_string(capture_type), syntax_colors)
            style = if color, do: %{fg: color, bg: bg}, else: %{fg: default_color, bg: bg}
            segs ++ [Segment.new(span_text, style)]
          else
            segs
          end

        {segs, max(pos, ec)}
      end)

    segments =
      if last_pos < line_length do
        tail = String.slice(line, last_pos, line_length - last_pos)
        segments ++ [Segment.new(tail, %{fg: default_color, bg: bg})]
      else
        segments
      end

    if segments == [], do: [Segment.new(line, %{fg: default_color, bg: bg})], else: segments
  end

  defp apply_h_scroll(segments, 0, _content_width, _bg), do: segments

  defp apply_h_scroll(segments, h_offset, content_width, bg) do
    {scrolled, _} =
      Enum.reduce(segments, {[], h_offset}, fn seg, {acc, remaining_skip} ->
        visual_len = String.length(seg.text)

        cond do
          remaining_skip >= visual_len ->
            {acc, remaining_skip - visual_len}

          remaining_skip > 0 ->
            text = String.slice(seg.text, remaining_skip, visual_len)
            {acc ++ [%{seg | text: text}], 0}

          true ->
            {acc ++ [seg], 0}
        end
      end)

    total_width = scrolled |> Enum.map(fn seg -> String.length(seg.text) end) |> Enum.sum()

    if total_width < content_width do
      scrolled ++ [Segment.new(String.duplicate(" ", content_width - total_width), %{bg: bg})]
    else
      scrolled
    end
  end
end
