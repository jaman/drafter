defmodule Drafter.Widget.TextArea do
  @moduledoc """
  A multi-line text editor widget with cursor navigation, scrolling, and optional syntax highlighting.

  Renders inside a bordered box. An optional line-number gutter can be enabled. Syntax
  highlighting is available for `:elixir`, `:python`, `:javascript`, and `:js` via the
  `:language` option. Placeholder text is shown when the content is empty and the widget
  is not focused.

  ## Options

    * `:text` - initial text content (default: `""`)
    * `:placeholder` - hint text shown when empty and unfocused (default: `""`)
    * `:on_change` - `(String.t() -> term())` called on every edit
    * `:max_lines` - maximum number of lines permitted
    * `:width` - widget width in columns (default: `40`)
    * `:height` - widget height in rows including borders (default: `6`)
    * `:show_line_numbers` - render a line-number gutter (default: `false`)
    * `:language` - atom for syntax highlighting: `:elixir`, `:python`, `:javascript`, `:js`
    * `:style` - map of style overrides for the text content area
    * `:line_number_style` - map of style overrides for the gutter
    * `:read_only` - boolean, disables editing when `true` (default: `false`)
    * `:tab_behavior` - `:focus` (default) or `:indent`
    * `:tab_size` - number of spaces for tab indentation (default: `2`)
    * `:max_checkpoints` - undo/redo history depth (default: `50`)
    * `:highlight_cursor_line` - apply background tint to cursor line (default: `false`)

  ## Key bindings

    * Arrow keys - move cursor by character or line
    * `Shift+Arrow` - extend selection
    * `Ctrl+A` - select all
    * `Ctrl+C` - copy selection to clipboard
    * `Ctrl+X` - cut selection to clipboard
    * `Ctrl+V` - paste from clipboard
    * `Ctrl+Z` - undo
    * `Ctrl+Y` - redo
    * `Ctrl+Left/Right` - word navigation
    * `Home` / `End` - move to start/end of the current line
    * `Page Up` / `Page Down` - move cursor by viewport height
    * `Backspace` / `Delete` - delete character; joins lines at line boundaries
    * `Enter` - insert a new line at the cursor position

  ## Usage

      text_area(placeholder: "Notes...", height: 10, show_line_numbers: true, language: :elixir)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :char, :scroll]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.ThemeManager
  alias Drafter.Widget.Scrollbar
  alias Drafter.Widget.TextArea.{Clipboard, Cursor, Editing, History, Render, Selection}

  defstruct [
    :text,
    :lines,
    :cursor_line,
    :cursor_col,
    :scroll_offset,
    :h_scroll,
    :focused,
    :style,
    :placeholder_style,
    :focused_style,
    :selection_style,
    :on_change,
    :max_lines,
    :width,
    :height,
    :placeholder,
    :show_line_numbers,
    :line_number_style,
    :gutter_width,
    :language,
    :selection,
    :read_only,
    :trap_focus,
    :tab_behavior,
    :tab_size,
    :max_checkpoints,
    :highlight_cursor_line,
    :undo_stack,
    :redo_stack
  ]

  @type selection :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()} | nil

  @type t :: %__MODULE__{
          text: String.t(),
          lines: [String.t()],
          cursor_line: non_neg_integer(),
          cursor_col: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          h_scroll: non_neg_integer(),
          focused: boolean(),
          style: Segment.style(),
          placeholder_style: Segment.style(),
          focused_style: Segment.style(),
          selection_style: Segment.style(),
          on_change: (String.t() -> term()) | nil,
          max_lines: pos_integer() | nil,
          width: pos_integer(),
          height: pos_integer(),
          placeholder: String.t(),
          show_line_numbers: boolean(),
          line_number_style: Segment.style(),
          gutter_width: pos_integer(),
          language: atom() | nil,
          selection: selection(),
          read_only: boolean(),
          trap_focus: boolean() | :arrows,
          tab_behavior: :focus | :indent,
          tab_size: pos_integer(),
          max_checkpoints: pos_integer(),
          highlight_cursor_line: boolean(),
          undo_stack: list(),
          redo_stack: list()
        }

  @impl Drafter.Widget
  def mount(props) do
    text = Map.get(props, :text, "")
    lines = String.split(text, "\n")
    show_line_numbers = Map.get(props, :show_line_numbers, false)

    gutter_width =
      if show_line_numbers do
        num_lines = length(lines)
        num_digits = max(3, String.length(Integer.to_string(num_lines)))
        num_digits + 1
      else
        0
      end

    %__MODULE__{
      text: text,
      lines: lines,
      cursor_line: 0,
      cursor_col: 0,
      scroll_offset: 0,
      h_scroll: 0,
      focused: Map.get(props, :focused, false),
      style: Map.get(props, :style, %{fg: {200, 200, 200}, bg: {40, 40, 40}}),
      placeholder_style:
        Map.get(props, :placeholder_style, %{fg: {100, 100, 100}, bg: {40, 40, 40}}),
      focused_style: Map.get(props, :focused_style, %{fg: {255, 255, 255}, bg: {50, 100, 200}}),
      selection_style:
        Map.get(props, :selection_style, %{fg: {255, 255, 255}, bg: {0, 100, 200}}),
      on_change: Map.get(props, :on_change),
      max_lines: Map.get(props, :max_lines),
      width: Map.get(props, :width, 40),
      height: Map.get(props, :height, 6),
      placeholder: Map.get(props, :placeholder, ""),
      show_line_numbers: show_line_numbers,
      line_number_style:
        Map.get(props, :line_number_style, %{fg: {100, 150, 255}, bg: {35, 35, 35}}),
      gutter_width: gutter_width,
      language: Map.get(props, :language),
      selection: nil,
      read_only: Map.get(props, :read_only, false),
      trap_focus: Map.get(props, :trap_focus, false),
      tab_behavior: Map.get(props, :tab_behavior, :focus),
      tab_size: Map.get(props, :tab_size, 2),
      max_checkpoints: Map.get(props, :max_checkpoints, 50),
      highlight_cursor_line: Map.get(props, :highlight_cursor_line, false),
      undo_stack: [],
      redo_stack: []
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    normalized_state = normalize_state(state)
    gutter_width = normalized_state.gutter_width
    content_width = max(1, rect.width - 2 - gutter_width)
    content_height = rect.height - 2

    computed = Computed.for_widget(:text_area, normalized_state)
    effective_style = Computed.to_segment_style(computed)

    border_computed = Computed.for_part(:text_area, normalized_state, :border)
    border_style = Computed.to_segment_style(border_computed)

    gutter_computed = Computed.for_part(:text_area, normalized_state, :gutter)
    gutter_style = Computed.to_segment_style(gutter_computed)

    line_num_style = Map.merge(gutter_style, normalized_state.line_number_style)

    top_border =
      "┌" <>
        if gutter_width > 0 do
          String.duplicate("─", gutter_width) <> "┬"
        else
          ""
        end <> String.duplicate("─", content_width) <> "┐"

    bottom_border =
      "└" <>
        if gutter_width > 0 do
          String.duplicate("─", gutter_width) <> "┴"
        else
          ""
        end <> String.duplicate("─", content_width) <> "┘"

    scrollbar_thumb =
      Scrollbar.thumb_rows(normalized_state.scroll_offset, length(normalized_state.lines), content_height)

    inner_width = if scrollbar_thumb, do: max(1, content_width - 1), else: content_width
    scrollbar_styles = Scrollbar.styles(ThemeManager.get_current_theme())

    content_lines =
      Render.render_content(normalized_state, inner_width, content_height, effective_style)

    strips =
      [
        Strip.new([Segment.new(String.pad_trailing(top_border, rect.width), border_style)])
        | Enum.with_index(content_lines, fn {line, segments}, idx ->
            line_num = normalized_state.scroll_offset + idx + 1

            line_num_text =
              if gutter_width > 0,
                do: String.pad_leading(to_string(line_num), gutter_width - 1) <> " ",
                else: ""

            gutter_segment =
              if gutter_width > 0 do
                [Segment.new("│", border_style), Segment.new(line_num_text, line_num_style)]
              else
                [Segment.new("│", border_style)]
              end

            content_segments =
              if segments != nil do
                segments
              else
                [Segment.new(String.pad_trailing(line, inner_width), effective_style)]
              end

            seg_width =
              Enum.reduce(content_segments, 0, fn seg, acc -> acc + Segment.width(seg) end)

            scrollbar_segment =
              if scrollbar_thumb,
                do: [Scrollbar.segment(idx, scrollbar_thumb, scrollbar_styles)],
                else: []

            padding_width =
              max(0, rect.width - gutter_width - seg_width - 2 - length(scrollbar_segment))

            padding_segments =
              if padding_width > 0 do
                [Segment.new(String.duplicate(" ", padding_width), effective_style)]
              else
                []
              end

            all_segments =
              gutter_segment ++
                content_segments ++
                padding_segments ++ scrollbar_segment ++ [Segment.new("│", border_style)]

            Strip.new(all_segments)
          end)
      ] ++
        [
          Strip.new([
            Segment.new(String.pad_trailing(bottom_border, rect.width), border_style)
          ])
        ]

    strips
  end

  @impl Drafter.Widget
  def handle_scroll(:up, state) do
    new_offset = max(0, state.scroll_offset - 3)
    {:ok, %{state | scroll_offset: new_offset}}
  end

  def handle_scroll(:down, state) do
    content_height = max(1, state.height - 2)
    max_offset = max(0, length(state.lines) - content_height)
    new_offset = min(max_offset, state.scroll_offset + 3)
    {:ok, %{state | scroll_offset: new_offset}}
  end

  @impl Drafter.Widget
  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}

  def handle_event({:key, :escape}, %{focused: true, trap_focus: trap} = state)
      when trap in [true, :arrows] do
    {:ok, %{state | focused: false}}
  end

  def handle_event({:key, :up}, %{focused: true} = state),
    do: {:ok, state |> Selection.clear_selection() |> Cursor.move_up() |> Cursor.adjust_scroll()}

  def handle_event({:key, :down}, %{focused: true} = state),
    do: {:ok, state |> Selection.clear_selection() |> Cursor.move_down() |> Cursor.adjust_scroll()}

  def handle_event({:key, :left}, %{focused: true} = state),
    do: {:ok, state |> Selection.clear_selection() |> Cursor.move_left() |> Cursor.adjust_scroll()}

  def handle_event({:key, :right}, %{focused: true} = state),
    do: {:ok, state |> Selection.clear_selection() |> Cursor.move_right() |> Cursor.adjust_scroll()}

  def handle_event({:key, :home}, %{focused: true} = state),
    do: {:ok, %{state | cursor_col: 0, selection: nil}}

  def handle_event({:key, :end}, %{focused: true} = state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    {:ok, %{state | cursor_col: String.length(current_line), selection: nil}}
  end

  def handle_event({:key, :page_up}, %{focused: true} = state) do
    viewport_height = max(1, state.height - 2)
    new_line = max(0, state.cursor_line - viewport_height)
    new_col = min(state.cursor_col, String.length(Enum.at(state.lines, new_line, "")))
    {:ok, %{state | cursor_line: new_line, cursor_col: new_col, selection: nil} |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, :page_down}, %{focused: true} = state) do
    viewport_height = max(1, state.height - 2)
    new_line = min(length(state.lines) - 1, state.cursor_line + viewport_height)
    new_col = min(state.cursor_col, String.length(Enum.at(state.lines, new_line, "")))
    {:ok, %{state | cursor_line: new_line, cursor_col: new_col, selection: nil} |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, {:shift, :up}}, %{focused: true} = state),
    do: {:ok, Selection.extend_selection(state, :up)}

  def handle_event({:key, {:shift, :down}}, %{focused: true} = state),
    do: {:ok, Selection.extend_selection(state, :down)}

  def handle_event({:key, {:shift, :left}}, %{focused: true} = state),
    do: {:ok, Selection.extend_selection(state, :left)}

  def handle_event({:key, {:shift, :right}}, %{focused: true} = state),
    do: {:ok, Selection.extend_selection(state, :right)}

  def handle_event({:key, :a, [:ctrl]}, %{focused: true} = state),
    do: {:ok, Selection.select_all(state)}

  def handle_event({:key, :c, [:ctrl]}, %{focused: true} = state) do
    Clipboard.copy_selection(state)
    {:ok, state}
  end

  def handle_event({:key, :x, [:ctrl]}, %{focused: true} = state) do
    {tag, new_state} = Clipboard.handle_cut(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :v, [:ctrl]}, %{focused: true} = state) when state.read_only != true do
    {tag, new_state} = Clipboard.handle_paste(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :z, [:ctrl]}, %{focused: true} = state) do
    {tag, new_state} = History.handle_undo(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :y, [:ctrl]}, %{focused: true} = state) do
    {tag, new_state} = History.handle_redo(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, {:ctrl, :left}}, %{focused: true} = state) do
    {new_row, new_col} = Cursor.word_left(state.lines, state.cursor_line, state.cursor_col)
    {:ok, %{state | cursor_line: new_row, cursor_col: new_col, selection: nil} |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, {:ctrl, :right}}, %{focused: true} = state) do
    {new_row, new_col} = Cursor.word_right(state.lines, state.cursor_line, state.cursor_col)
    {:ok, %{state | cursor_line: new_row, cursor_col: new_col, selection: nil} |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, :backspace}, %{focused: true} = state) do
    {tag, new_state} = Editing.handle_backspace(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :delete}, %{focused: true} = state) do
    {tag, new_state} = Editing.handle_delete(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :enter}, %{focused: true} = state) do
    {tag, new_state} = Editing.handle_enter(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:key, :tab}, %{focused: true, tab_behavior: :indent} = state) do
    {tag, new_state} = Editing.handle_tab_indent(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:bracketed_paste, content}, %{focused: true} = state) do
    {tag, new_state} = Editing.insert_text(state, content)
    trigger_change(new_state)
    {tag, new_state}
  end

  def handle_event({:char, char}, %{focused: true} = state) when is_integer(char) do
    char_str = <<char::utf8>>
    handle_printable_char(state, char_str)
  end

  def handle_event({:key, key}, %{focused: true} = state) when is_atom(key) do
    handle_printable_char(state, Atom.to_string(key))
  end

  def handle_event({:mouse, %{type: :scroll, direction: dir}}, state) do
    handle_scroll(dir, state)
  end

  def handle_event(_event, state), do: {:noreply, state}

  @impl Drafter.Widget
  def update(props, state) do
    text = Map.get(props, :text, state.text)
    text_changed? = text != state.text
    lines = if text_changed?, do: String.split(text, "\n"), else: state.lines
    show_line_numbers = Map.get(props, :show_line_numbers, state.show_line_numbers)

    gutter_width =
      if show_line_numbers do
        num_lines = length(lines)
        num_digits = max(3, String.length(Integer.to_string(num_lines)))
        num_digits + 1
      else
        0
      end

    new_state =
      %{
        state
        | text: text,
          lines: lines,
          placeholder: Map.get(props, :placeholder, state.placeholder),
          focused: Map.get(props, :focused, state.focused),
          style: Map.get(props, :style, state.style),
          placeholder_style: Map.get(props, :placeholder_style, state.placeholder_style),
          focused_style: Map.get(props, :focused_style, state.focused_style),
          on_change: Map.get(props, :on_change, state.on_change),
          max_lines: Map.get(props, :max_lines, state.max_lines),
          width: Map.get(props, :width, state.width),
          height: Map.get(props, :height, state.height),
          show_line_numbers: show_line_numbers,
          line_number_style: Map.get(props, :line_number_style, state.line_number_style),
          gutter_width: gutter_width,
          language: Map.get(props, :language, state.language),
          read_only: Map.get(props, :read_only, state.read_only),
          trap_focus: Map.get(props, :trap_focus, state.trap_focus),
          tab_behavior: Map.get(props, :tab_behavior, state.tab_behavior),
          tab_size: Map.get(props, :tab_size, state.tab_size),
          max_checkpoints: Map.get(props, :max_checkpoints, state.max_checkpoints),
          highlight_cursor_line:
            Map.get(props, :highlight_cursor_line, state.highlight_cursor_line)
      }

    if text_changed?, do: reclamp_cursor(new_state), else: new_state
  end

  defp reclamp_cursor(state) do
    cursor_line = min(state.cursor_line, max(0, length(state.lines) - 1))
    line_len = String.length(Enum.at(state.lines, cursor_line, ""))

    %{state | cursor_line: cursor_line, cursor_col: min(state.cursor_col, line_len), selection: nil}
    |> Cursor.adjust_scroll()
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 6)

  def component_tag, do: :text_area

  def from_component_opts(_args, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 6})
    value = Drafter.Binding.get_bound_value(opts, app_state, "")
    %{
      text: value,
      placeholder: Keyword.get(opts, :placeholder, ""),
      width: rect.width,
      height: rect.height,
      on_change: Drafter.Binding.create_bound_callback(opts, :text),
      max_lines: Keyword.get(opts, :max_lines),
      show_line_numbers: Keyword.get(opts, :show_line_numbers, false),
      language: Keyword.get(opts, :language),
      style: Keyword.get(opts, :style, %{}),
      read_only: Keyword.get(opts, :read_only, false),
      trap_focus: Keyword.get(opts, :trap_focus, false),
      tab_behavior: Keyword.get(opts, :tab_behavior, :focus),
      tab_size: Keyword.get(opts, :tab_size, 2),
      highlight_cursor_line: Keyword.get(opts, :highlight_cursor_line, false)
    }
  end

  def update_props_from_mount(mount_props, existing_state, opts) do
    base = %{
      on_change: mount_props.on_change,
      max_lines: mount_props.max_lines,
      show_line_numbers: mount_props.show_line_numbers,
      language: mount_props.language,
      read_only: mount_props.read_only,
      trap_focus: mount_props.trap_focus,
      tab_behavior: mount_props.tab_behavior,
      tab_size: mount_props.tab_size,
      highlight_cursor_line: mount_props.highlight_cursor_line
    }
    base = if existing_state.width != mount_props.width do
      Map.put(base, :width, mount_props.width)
    else
      base
    end
    base = if existing_state.height != mount_props.height do
      Map.put(base, :height, mount_props.height)
    else
      base
    end
    base = if existing_state.placeholder != mount_props.placeholder do
      Map.put(base, :placeholder, mount_props.placeholder)
    else
      base
    end
    if (Keyword.has_key?(opts, :bind) or Keyword.has_key?(opts, :value)) and existing_state.text != mount_props.text do
      Map.put(base, :text, mount_props.text)
    else
      base
    end
  end

  defp handle_printable_char(state, char_str) do
    if Editing.printable_char?(char_str) and Editing.can_insert_char?(state) do
      {tag, new_state} = Editing.handle_char_input(state, char_str)
      trigger_change(new_state)
      {tag, new_state}
    else
      {:noreply, state}
    end
  end

  defp normalize_state(%__MODULE__{} = state), do: state
  defp normalize_state(props), do: mount(props)

  defp trigger_change(state) do
    if state.on_change do
      try do
        state.on_change.(state.text)
      rescue
        _error -> :ok
      end
    end
  end
end
