defmodule Drafter.Widget.Log do
  @moduledoc """
  Renders a scrollable plain-text log panel that accepts streamed line output.

  Lines are appended via `{:write, line}` or `{:write_lines, lines}` events.
  When `:auto_scroll` is enabled (default), the view tracks the newest lines.
  Alternatively a file path can be provided; the widget builds a byte-offset
  index for efficient random access into large files without loading them fully
  into memory.

  Keyboard navigation is supported when the widget has focus:
  `↑`/`↓` scroll by one line, `Page Up`/`Page Down` by ten, `Home`/`End` jump
  to the top and bottom respectively.

  ## Options

    * `:lines` - initial list of strings (default `[]`)
    * `:file_path` - path to a file; indexed and read on demand
    * `:max_lines` - maximum number of lines kept in memory (default `1000`)
    * `:auto_scroll` - follow new output: `true` (default) / `false`
    * `:wrap` - wrap long lines: `true` (default) / `false`
    * `:highlight` - apply basic token highlighting: `true` / `false` (default)
    * `:border` - draw a box border: `true` / `false` (default)
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      log(lines: ["Starting...", "Done."], auto_scroll: true)
      log(file_path: "/var/log/app.log", highlight: true)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Text

  defstruct [
    :lines,
    :max_lines,
    :auto_scroll,
    :wrap,
    :style,
    :classes,
    :app_module,
    :scroll_offset,
    :file_path,
    :total_lines,
    :line_offsets,
    :highlight,
    :border
  ]

  @impl Drafter.Widget
  def mount(props) do
    file_path = Map.get(props, :file_path)
    max_lines = Map.get(props, :max_lines, 1000)
    auto_scroll = Map.get(props, :auto_scroll, true)
    wrap = Map.get(props, :wrap, true)

    initial_state = %__MODULE__{
      lines: [],
      max_lines: max_lines,
      auto_scroll: auto_scroll,
      wrap: wrap,
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      scroll_offset: 0,
      file_path: file_path,
      total_lines: 0,
      line_offsets: [],
      highlight: Map.get(props, :highlight, false),
      border: Map.get(props, :border, false)
    }

    if file_path && File.exists?(file_path) do
      build_file_index(initial_state, file_path)
    else
      lines = Map.get(props, :lines, []) |> Enum.take(max_lines)
      %{initial_state | lines: lines, total_lines: length(lines)}
    end
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    classes = state.classes
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:log, state, computed_opts)

    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {35, 38, 45}
    border_color = {60, 65, 75}

    line_style = %{fg: fg, bg: bg}

    if state.border do
      render_with_border(state, rect, fg, bg, border_color, line_style)
    else
      render_plain(state, rect, line_style)
    end
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 10)

  def component_tag, do: :log

  def from_component_opts(_args, opts) do
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
      c when is_binary(c) -> String.to_atom(c)
      c when is_atom(c) -> c
    end)
    %{
      lines: Keyword.get(opts, :lines, []),
      file_path: Keyword.get(opts, :file_path),
      max_lines: Keyword.get(opts, :max_lines, 1000),
      auto_scroll: Keyword.get(opts, :auto_scroll, true),
      wrap: Keyword.get(opts, :wrap, true),
      highlight: Keyword.get(opts, :highlight, false),
      border: Keyword.get(opts, :border, false),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      file_path: mount_props.file_path,
      lines: mount_props.lines,
      app_module: mount_props.app_module
    }
  end

  defp render_plain(state, rect, line_style) do
    visible_lines = get_visible_lines(state, rect.height)

    all_strips =
      Enum.flat_map(visible_lines, fn line ->
        wrapped =
          if state.wrap do
            Text.wrap(line, rect.width)
          else
            [Text.truncate(line, rect.width)]
          end

        Enum.map(wrapped, fn wrapped_line ->
          segments =
            if state.highlight do
              highlight_line(wrapped_line, rect.width, line_style)
            else
              padded = String.pad_trailing(wrapped_line, rect.width, " ")
              [Segment.new(padded, line_style)]
            end

          Strip.new(segments)
        end)
      end)

    strips = if length(all_strips) > 0, do: all_strips, else: []

    padding_needed = max(0, rect.height - length(strips))
    empty_line = String.duplicate(" ", rect.width)

    padding_strips =
      List.duplicate(Strip.new([Segment.new(empty_line, line_style)]), padding_needed)

    Enum.take(strips ++ padding_strips, rect.height)
  end

  defp render_with_border(state, rect, _fg, bg, border_color, line_style) do
    inner_width = max(0, rect.width - 2)
    inner_height = max(0, rect.height - 2)

    border_style = %{fg: border_color, bg: bg}

    top_border =
      Strip.new([
        Segment.new("┌", border_style),
        Segment.new(String.duplicate("─", inner_width), border_style),
        Segment.new("┐", border_style)
      ])

    bottom_border =
      Strip.new([
        Segment.new("└", border_style),
        Segment.new(String.duplicate("─", inner_width), border_style),
        Segment.new("┘", border_style)
      ])

    visible_lines = get_visible_lines(state, inner_height)

    content_strips =
      Enum.flat_map(visible_lines, fn line ->
        wrapped =
          if state.wrap do
            Text.wrap(line, inner_width)
          else
            [Text.truncate(line, inner_width)]
          end

        Enum.map(wrapped, fn wrapped_line ->
          segments =
            if state.highlight do
              highlight_line(wrapped_line, inner_width, line_style)
            else
              padded = String.pad_trailing(wrapped_line, inner_width, " ")
              [Segment.new(padded, line_style)]
            end

          Strip.new(
            [Segment.new("│", border_style)] ++ segments ++ [Segment.new("│", border_style)]
          )
        end)
      end)

    content_strips = Enum.take(content_strips, inner_height)

    padding_needed = max(0, inner_height - length(content_strips))
    empty_content = String.duplicate(" ", inner_width)

    padding_strips =
      List.duplicate(
        Strip.new([
          Segment.new("│", border_style),
          Segment.new(empty_content, line_style),
          Segment.new("│", border_style)
        ]),
        padding_needed
      )

    ([top_border] ++ content_strips ++ padding_strips ++ [bottom_border])
    |> Enum.take(rect.height)
  end

  defp highlight_line(line, width, base_style) do
    patterns = [
      {~r/\[(\d+)\]/, {150, 200, 255}},
      {~r/'([^']*)'/, {200, 180, 100}},
      {~r/"([^"]*)"/, {200, 180, 100}},
      {~r/\b(fear|Fear)\b/, {255, 150, 150}},
      {~r/\b(true|false|nil)\b/, {180, 130, 220}},
      {~r/\b(\d+\.?\d*)\b/, {150, 220, 150}}
    ]

    segments = parse_with_highlights(line, patterns, base_style)
    total_width = segments |> Enum.map(&String.length(&1.text)) |> Enum.sum()
    padding_width = max(0, width - total_width)

    if padding_width > 0 do
      segments ++ [Segment.new(String.duplicate(" ", padding_width), base_style)]
    else
      segments
    end
  end

  defp parse_with_highlights(text, patterns, base_style) do
    combined_pattern =
      patterns
      |> Enum.map(fn {regex, _} -> Regex.source(regex) end)
      |> Enum.join("|")

    combined_regex = Regex.compile!("(#{combined_pattern})")

    parts = Regex.split(combined_regex, text, include_captures: true)

    Enum.map(parts, fn part ->
      color =
        Enum.find_value(patterns, base_style.fg, fn {regex, color} ->
          if Regex.match?(regex, part), do: color, else: nil
        end)

      Segment.new(part, %{base_style | fg: color})
    end)
  end

  @impl Drafter.Widget
  def handle_event(event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case event do
      {:write, line} when is_binary(line) ->
        new_lines = add_line(state, line)
        new_state = %{state | lines: new_lines}
        new_state = if state.auto_scroll, do: scroll_to_bottom(new_state), else: new_state
        {:ok, new_state}

      {:write_lines, lines} when is_list(lines) ->
        new_lines =
          Enum.reduce(lines, state.lines, fn line, acc ->
            add_line(%{state | lines: acc}, line)
          end)

        new_state = %{state | lines: new_lines}
        new_state = if state.auto_scroll, do: scroll_to_bottom(new_state), else: new_state
        {:ok, new_state}

      :clear ->
        {:ok, %{state | lines: [], scroll_offset: 0}}

      {:key, :end} ->
        {:ok, scroll_to_bottom(state)}

      {:key, :home} ->
        {:ok, %{state | scroll_offset: 0}}

      {:key, :page_down} ->
        {:ok, scroll_down(state, 10)}

      {:key, :page_up} ->
        {:ok, scroll_up(state, 10)}

      {:key, :down} ->
        {:ok, scroll_down(state, 1)}

      {:key, :up} ->
        {:ok, scroll_up(state, 1)}

      _ ->
        {:noreply, state}
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_file_path = Map.get(props, :file_path)
    needs_rebuild = new_file_path && new_file_path != state.file_path

    new_state = %{
      state
      | max_lines: Map.get(props, :max_lines, state.max_lines),
        auto_scroll: Map.get(props, :auto_scroll, state.auto_scroll),
        wrap: Map.get(props, :wrap, state.wrap),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        file_path: new_file_path || state.file_path,
        highlight: Map.get(props, :highlight, state.highlight),
        border: Map.get(props, :border, state.border)
    }

    if needs_rebuild && new_file_path && File.exists?(new_file_path) do
      build_file_index(new_state, new_file_path)
    else
      new_lines = Map.get(props, :lines)

      if new_lines && new_lines != state.lines do
        %{
          new_state
          | lines: new_lines |> Enum.take(new_state.max_lines),
            total_lines: length(new_lines)
        }
      else
        new_state
      end
    end
  end

  defp add_line(state, line) do
    new_lines = state.lines ++ [line]
    Enum.take(new_lines, -state.max_lines)
  end

  defp get_visible_lines(state, visible_count) do
    if state.file_path do
      get_visible_lines_from_file(state, visible_count)
    else
      total_lines = length(state.lines)
      start_index = max(0, total_lines - visible_count - state.scroll_offset)
      end_index = min(total_lines, start_index + visible_count)

      Enum.slice(state.lines, start_index, end_index - start_index)
    end
  end

  defp get_visible_lines_from_file(state, visible_count) do
    total_lines = state.total_lines
    start_line = max(0, total_lines - visible_count - state.scroll_offset)
    end_line = min(total_lines, start_line + visible_count)

    read_lines_from_file(state.file_path, state.line_offsets, start_line, end_line)
  end

  defp read_lines_from_file(file_path, line_offsets, start_line, end_line) do
    if File.exists?(file_path) do
      start_offset = Enum.at(line_offsets, start_line, 0)
      end_offset = Enum.at(line_offsets, min(end_line, length(line_offsets) - 1), :eof)

      start_byte = if is_integer(start_offset), do: start_offset, else: 0
      end_byte = if is_integer(end_offset), do: end_offset, else: :eof

      file_size = File.stat!(file_path).size
      actual_end = if end_byte == :eof, do: file_size, else: min(end_byte, file_size)

      if actual_end > start_byte do
        File.open!(file_path, [:read, :binary], fn file ->
          :file.position(file, start_byte)
          {:ok, data} = :file.read(file, actual_end - start_byte)

          data
          |> String.split("\n")
          |> Enum.take(end_line - start_line)
        end)
      else
        []
      end
    else
      []
    end
  end

  defp build_file_index(state, file_path) do
    if File.exists?(file_path) do
      line_offsets =
        File.stream!(file_path, [], 1024 * 8)
        |> Enum.reduce({[0], 0}, fn chunk, {offsets, current_offset} ->
          lines = String.split(chunk, "\n")
          num_newlines = length(lines) - 1

          new_offsets =
            if num_newlines > 0 do
              {new_lines_in_chunk, _} = Enum.split(lines, num_newlines)
              chunk_without_last = Enum.join(new_lines_in_chunk, "\n") <> "\n"
              chunk_size = byte_size(chunk_without_last)
              offsets ++ [current_offset + chunk_size]
            else
              offsets
            end

          {new_offsets, current_offset + byte_size(chunk)}
        end)
        |> elem(0)

      total_lines = length(line_offsets) - 1

      %{state | line_offsets: line_offsets, total_lines: total_lines, scroll_offset: 0}
    else
      state
    end
  end

  defp scroll_to_bottom(state) do
    %{state | scroll_offset: 0}
  end

  defp scroll_down(state, amount) do
    new_offset = max(0, state.scroll_offset - amount)
    %{state | scroll_offset: new_offset}
  end

  defp scroll_up(state, amount) do
    max_offset =
      if state.file_path,
        do: max(0, state.total_lines - 10),
        else: max(0, length(state.lines) - 10)

    new_offset = min(max_offset, state.scroll_offset + amount)
    %{state | scroll_offset: new_offset}
  end
end
