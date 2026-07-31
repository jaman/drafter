defmodule Drafter.Widget.RichLog do
  @moduledoc """
  Renders a scrollable log panel where each line can carry per-line style metadata.

  Lines are plain strings or `{text, meta}` tuples. The `meta` map may include
  `:color`, `:background`, `:bold`, `:dim`, `:italic`, and `:underline` keys to
  style individual entries. When `:reverse` is `true` (default), the newest
  line appears at the bottom and the view auto-scrolls to follow new output.
  Optional line-number gutters are controlled by `:show_line_numbers`.

  Append lines via `{:write, content}` or `{:write_lines, lines}` events.
  Send `:clear` to reset the buffer.

  ## Options

    * `:lines` - initial list of strings or `{text, meta}` tuples (default `[]`)
    * `:max_lines` - maximum lines kept in memory (default `1000`)
    * `:auto_scroll` - follow new output: `true` (default) / `false`
    * `:wrap` - wrap long lines: `true` (default) / `false`
    * `:reverse` - newest line at the bottom: `true` (default) / `false`
    * `:show_line_numbers` - display a line number gutter: `true` / `false` (default)
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      rich_log(lines: [
        {"INFO  Connected", %{color: {100, 200, 100}}},
        {"ERROR Timeout",   %{color: {255, 80, 80}, bold: true}}
      ])
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.RingBuffer
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
    :show_line_numbers,
    :reverse
  ]

  @type rich_line :: {String.t(), list()}

  @impl Drafter.Widget
  def mount(props) do
    max_lines = Map.get(props, :max_lines, 1000)
    auto_scroll = Map.get(props, :auto_scroll, true)
    wrap = Map.get(props, :wrap, true)
    show_line_numbers = Map.get(props, :show_line_numbers, false)
    reverse = Map.get(props, :reverse, true)

    %__MODULE__{
      lines: props |> Map.get(:lines, []) |> normalize_lines(max_lines),
      max_lines: max_lines,
      auto_scroll: auto_scroll,
      wrap: wrap,
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      scroll_offset: 0,
      show_line_numbers: show_line_numbers,
      reverse: reverse
    }
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

    computed = Computed.for_widget(:rich_log, state, computed_opts)

    default_fg = computed[:color] || {200, 200, 200}
    default_bg = computed[:background] || {30, 30, 30}

    line_number_width =
      if state.show_line_numbers, do: String.length("#{length(state.lines)}") + 2, else: 0

    content_width = rect.width - line_number_width

    visible_lines = get_visible_lines(state, rect.height)

    rows =
      Enum.flat_map(
        Enum.with_index(visible_lines),
        fn {line, idx} ->
          render_rich_line(
            line,
            idx,
            state,
            content_width,
            line_number_width,
            default_fg,
            default_bg
          )
        end
      )

    blank =
      Strip.new([
        Segment.new(String.duplicate(" ", rect.width), %{fg: default_fg, bg: default_bg})
      ])

    rows
    |> Enum.map(&Strip.new/1)
    |> fit_to_height(rect.height, blank, state.reverse)
  end

  defp fit_to_height(strips, height, blank, reverse) do
    overflow = length(strips) - height

    cond do
      overflow > 0 and reverse -> Enum.drop(strips, overflow)
      overflow > 0 -> Enum.take(strips, height)
      true -> strips ++ List.duplicate(blank, -overflow)
    end
  end

  @impl Drafter.Widget
  def handle_event(event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    dispatch_rich_log_event(event, state)
  end

  defp dispatch_rich_log_event({:write, content}, state)
       when is_binary(content) or is_tuple(content) do
    new_state = %{state | lines: add_line(state, content)}
    {:ok, if(state.auto_scroll, do: scroll_to_bottom(new_state), else: new_state)}
  end

  defp dispatch_rich_log_event({:write_lines, lines}, state) when is_list(lines) do
    new_lines =
      Enum.reduce(lines, state.lines, fn line, acc -> add_line(%{state | lines: acc}, line) end)

    new_state = %{state | lines: new_lines}
    {:ok, if(state.auto_scroll, do: scroll_to_bottom(new_state), else: new_state)}
  end

  defp dispatch_rich_log_event(:clear, state), do: {:ok, %{state | lines: [], scroll_offset: 0}}
  defp dispatch_rich_log_event({:key, :end}, state), do: {:ok, scroll_to_bottom(state)}
  defp dispatch_rich_log_event({:key, :home}, state), do: {:ok, %{state | scroll_offset: 0}}
  defp dispatch_rich_log_event({:key, :page_down}, state), do: {:ok, scroll_down(state, 10)}
  defp dispatch_rich_log_event({:key, :page_up}, state), do: {:ok, scroll_up(state, 10)}
  defp dispatch_rich_log_event({:key, :down}, state), do: {:ok, scroll_down(state, 1)}
  defp dispatch_rich_log_event({:key, :up}, state), do: {:ok, scroll_up(state, 1)}
  defp dispatch_rich_log_event(_, state), do: {:noreply, state}

  @impl Drafter.Widget
  def update(props, state) do
    max_lines = Map.get(props, :max_lines, state.max_lines)

    %{
      state
      | lines: props |> Map.get(:lines, state.lines) |> normalize_lines(max_lines),
        max_lines: max_lines,
        auto_scroll: Map.get(props, :auto_scroll, state.auto_scroll),
        wrap: Map.get(props, :wrap, state.wrap),
        show_line_numbers: Map.get(props, :show_line_numbers, state.show_line_numbers),
        reverse: Map.get(props, :reverse, state.reverse),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 10)

  def component_tag, do: :rich_log

  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      lines: Keyword.get(opts, :lines, []),
      max_lines: Keyword.get(opts, :max_lines, 1000),
      auto_scroll: Keyword.get(opts, :auto_scroll, true),
      wrap: Keyword.get(opts, :wrap, true),
      reverse: Keyword.get(opts, :reverse, true),
      show_line_numbers: Keyword.get(opts, :show_line_numbers, false),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    Map.take(mount_props, [:lines, :max_lines, :auto_scroll, :wrap, :reverse, :show_line_numbers])
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    %{
      state
      | lines: buffer |> RingBuffer.last_n(state.max_lines) |> normalize_lines(state.max_lines)
    }
  end

  defp add_line(state, line) do
    new_lines = state.lines ++ [parse_line(line)]
    Enum.take(new_lines, -state.max_lines)
  end

  defp normalize_lines(lines, max_lines) do
    lines
    |> Enum.map(&parse_line/1)
    |> Enum.take(-max_lines)
  end

  defp parse_line({line, meta}) when is_binary(line) and is_map(meta), do: {line, meta}
  defp parse_line(line) when is_binary(line), do: {line, %{}}
  defp parse_line(other), do: {to_string(other), %{}}

  defp get_visible_lines(state, visible_count) do
    total_lines = length(state.lines)

    lines_to_show =
      if state.reverse do
        start_index = max(0, total_lines - visible_count - state.scroll_offset)
        end_index = min(total_lines, start_index + visible_count)
        Enum.slice(state.lines, start_index, end_index - start_index)
      else
        start_index = min(state.scroll_offset, max(0, total_lines - visible_count))
        end_index = min(total_lines, start_index + visible_count)
        Enum.slice(state.lines, start_index, end_index - start_index)
      end

    lines_to_show
  end

  defp render_rich_line(
         {text, meta},
         line_index,
         state,
         width,
         line_number_width,
         default_fg,
         default_bg
       ) do
    fg = Map.get(meta, :color, default_fg)
    bg = Map.get(meta, :background, default_bg)
    bold = Map.get(meta, :bold, false)
    dim = Map.get(meta, :dim, false)
    italic = Map.get(meta, :italic, false)
    underline = Map.get(meta, :underline, false)

    base_style = %{fg: fg, bg: bg}

    line_style =
      base_style
      |> Map.put(:bold, bold)
      |> Map.put(:dim, dim)
      |> Map.put(:italic, italic)
      |> Map.put(:underline, underline)

    line_number =
      if state.show_line_numbers do
        total_lines = length(state.lines)

        actual_index =
          if state.reverse do
            total_lines - line_index
          else
            line_index + 1
          end

        num = String.pad_trailing("#{actual_index} ", line_number_width, " ")
        num_style = %{fg: {100, 100, 100}, bg: bg}
        [Segment.new(num, num_style)]
      else
        []
      end

    wrapped =
      if state.wrap do
        Text.wrap(text, width)
      else
        [Text.truncate(text, width)]
      end

    gutter =
      List.duplicate(
        Segment.new(String.duplicate(" ", line_number_width), %{bg: bg}),
        min(1, line_number_width)
      )

    wrapped
    |> Enum.with_index()
    |> Enum.map(fn {wrapped_line, row} ->
      prefix = if row == 0, do: line_number, else: gutter
      prefix ++ [Segment.new(pad_to_width(wrapped_line, width), line_style)]
    end)
  end

  defp pad_to_width(text, width) do
    text <> String.duplicate(" ", max(0, width - Text.display_width(text)))
  end

  defp scroll_to_bottom(state) do
    %{state | scroll_offset: 0}
  end

  defp scroll_down(state, amount) do
    new_offset = max(0, state.scroll_offset - amount)
    %{state | scroll_offset: new_offset}
  end

  defp scroll_up(state, amount) do
    %{state | scroll_offset: state.scroll_offset + amount}
  end
end
