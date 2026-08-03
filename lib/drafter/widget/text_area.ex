defmodule Drafter.Widget.TextArea do
  @moduledoc """
  A multi-line text editor widget with cursor navigation, scrolling, and optional syntax highlighting.

  Renders inside a bordered box. An optional line-number gutter can be enabled. Syntax
  highlighting is available for `:elixir`, `:python`, `:javascript`, and `:js` via the
  `:language` option. Placeholder text is shown when the content is empty and the widget
  is not focused.

  ## Component tag

  Tag `:text_area`, built by `Drafter.App` as `{:text_area, opts}`:

      text_area(opts)

  There is no positional argument. The text goes through `Drafter.Binding`:
  passing `bind: :some_key` seeds the content from that app-state key and writes
  every edit back to it, and `:on_change` is built from the same binding.
  `:width` and `:height` are always taken from the rect the parent allocated.

  ## Options

    * `:text` - `t:String.t/0` initial content. Default `""`. Split on `"\\n"` into
      `:lines`. Through the element the content comes from `:bind` instead.
    * `:bind` - app-state key atom for two-way binding of the text. Default: none.
    * `:placeholder` - `t:String.t/0` hint shown while the content is empty and the
      widget unfocused. Default `""`.
    * `:on_change` - `(String.t() -> term())` called with the full text after every
      edit. Default `nil`. Through the element it comes from
      `Drafter.Binding.create_bound_callback/2`. An exception it raises is
      swallowed.
    * `:max_lines` - `t:pos_integer/0` cap on the number of lines. Default `nil`,
      unlimited.
    * `:width` - `t:pos_integer/0` widget width in columns. Default `40` when
      mounting directly, and the allocated rect width through the element.
    * `:height` - `t:pos_integer/0` widget height in rows including both borders.
      Default `6` when mounting directly, and the allocated rect height through the
      element. Only `handle_scroll/2` reads it; `render/2` uses the rect.
    * `:show_line_numbers` - `t:boolean/0`, draw a line-number gutter. Default
      `false`. The gutter is as wide as the digit count of the line total, at least
      three, plus one.
    * `:language` - `:elixir | :python | :javascript | :js` for syntax
      highlighting. Default `nil`, no highlighting.
    * `:style` - `t:map/0` of style overrides for the content area. Default
      `%{fg: {200, 200, 200}, bg: {40, 40, 40}}` when mounting directly, and `%{}`
      through the element.
    * `:read_only` - `t:boolean/0`. Default `false`. Blocks cut, paste and
      character input; cursor movement and copy still work.
    * `:trap_focus` - `true | :arrows | false`. Default `false`. When `true` or
      `:arrows`, `escape` blurs the editor.
    * `:tab_behavior` - `:focus | :indent`. Default `:focus`, which lets `tab`
      fall through to focus movement; `:indent` inserts `:tab_size` spaces.
    * `:tab_size` - `t:pos_integer/0` spaces inserted for a tab. Default `2`.
    * `:highlight_cursor_line` - `t:boolean/0`, tint the cursor's row. Default
      `false`.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`. Every editing
      binding requires it.

  These are read by `mount/1` only; the `text_area/1` element does not forward
  them:

    * `:placeholder_style` - style map for the placeholder text. Default
      `%{fg: {100, 100, 100}, bg: {40, 40, 40}}`.
    * `:focused_style` - style map applied while the widget has focus. Default
      `%{fg: {255, 255, 255}, bg: {50, 100, 200}}`.
    * `:selection_style` - style map for the selected range. Default
      `%{fg: {255, 255, 255}, bg: {0, 100, 200}}`. `update/2` does not accept it
      either, so it is fixed at mount.
    * `:line_number_style` - style map for the gutter. Default
      `%{fg: {100, 150, 255}, bg: {35, 35, 35}}`.
    * `:max_checkpoints` - undo/redo history depth. Default `50`.

  `mount/1` always starts the cursor at line `0`, column `0`, with no selection,
  no scroll and empty undo and redo stacks; those cannot be seeded from props.
  `update/2` accepts every option above except `:selection_style`, and re-clamps
  the cursor and clears the selection whenever `:text` actually changes. Through
  the component tree `update_props_from_mount/3` always passes `:on_change`,
  `:max_lines`, `:show_line_numbers`, `:language`, `:read_only`, `:trap_focus`,
  `:tab_behavior`, `:tab_size` and `:highlight_cursor_line`; `:width`, `:height`
  and `:placeholder` only when they changed, and `:text` only when `opts` carries
  `:bind` or `:value` and the text differs.

  ## Widget value

  `Drafter.get_widget_value/1` returns the current text, and
  `Drafter.set_widget_value/2` replaces it.

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
    * `Escape` - blur the editor, when `:trap_focus` is `true` or `:arrows`
    * `Tab` - insert `:tab_size` spaces, only when `:tab_behavior` is `:indent`

  All of these require the widget to be focused; unfocused, every event other than
  `{:focus}`, `{:blur}` and the mouse wheel returns `{:noreply, state}`.

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

  @type selection ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()} | nil

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

  @doc """
  Builds the widget state from `props`.

  Every option listed in the module doc is read here with the default stated there.
  `:text` is split into `:lines`, `:gutter_width` is derived from
  `:show_line_numbers` and the line count, and the cursor, scroll, selection and
  history all start empty.

      iex> state = Drafter.Widget.TextArea.mount(%{text: "a\\nb"})
      iex> {state.lines, state.cursor_line, state.cursor_col, state.gutter_width}
      {["a", "b"], 0, 0, 0}

      iex> state = Drafter.Widget.TextArea.mount(%{show_line_numbers: true})
      iex> state.gutter_width
      4

      iex> state = Drafter.Widget.TextArea.mount(%{})
      iex> {state.width, state.height, state.tab_behavior, state.tab_size, state.max_checkpoints}
      {40, 6, :focus, 2, 50}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the bordered editor into `rect`.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. Returns the top border, `rect.height - 2` content rows and the bottom
  border, so the result is `rect.height` strips. The content area is
  `rect.width - 2 - gutter_width` columns, one narrower again when a scrollbar is
  needed, which happens as soon as the line count exceeds the content height.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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
      Scrollbar.thumb_rows(
        normalized_state.scroll_offset,
        length(normalized_state.lines),
        content_height
      )

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

  @doc """
  Scrolls the viewport by three lines per wheel step, without moving the cursor.

  Always returns `{:ok, new_state}`. Scrolling up stops at `0`; scrolling down
  stops at `line_count - (height - 2)`, using the state's `:height`, not the rect.
  Works whether or not the widget is focused.

      iex> state = Drafter.Widget.TextArea.mount(%{text: Enum.join(1..20, "\\n")})
      iex> {:ok, down} = Drafter.Widget.TextArea.handle_scroll(:down, state)
      iex> down.scroll_offset
      3

      iex> state = Drafter.Widget.TextArea.mount(%{text: "a\\nb"})
      iex> {:ok, down} = Drafter.Widget.TextArea.handle_scroll(:down, state)
      iex> down.scroll_offset
      0
  """
  @spec handle_scroll(:up | :down, t()) :: {:ok, t()}
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

  @doc """
  Handles the editor's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  `{:focus}`, `{:blur}` and `{:mouse, %{type: :scroll}}` are handled in any state.
  Every binding listed in the module doc, along with `{:char, code}` and
  `{:bracketed_paste, text}`, requires `:focused`; anything else returns
  `{:noreply, state}`.

  Cursor moves, selection changes, undo, redo and copy return `{:ok, new_state}`.
  Edits return whatever the editing helper reports, `{:ok, state}` or
  `{:noreply, state}`, and call `:on_change` with the full text. A cut, paste or
  character input on a `:read_only` editor returns `{:noreply, state}`.

      iex> state = Drafter.Widget.TextArea.mount(%{focused: true})
      iex> {:ok, typed} = Drafter.Widget.TextArea.handle_event({:char, ?a}, state)
      iex> {typed.text, typed.cursor_col}
      {"a", 1}

      iex> state = Drafter.Widget.TextArea.mount(%{text: "hi", focused: true, read_only: true})
      iex> Drafter.Widget.TextArea.handle_event({:char, ?a}, state) == {:noreply, state}
      true

      iex> state = Drafter.Widget.TextArea.mount(%{text: "hi"})
      iex> Drafter.Widget.TextArea.handle_event({:char, ?a}, state) == {:noreply, state}
      true

      iex> state = Drafter.Widget.TextArea.mount(%{text: "ab\\ncd", focused: true})
      iex> {:ok, moved} = Drafter.Widget.TextArea.handle_event({:key, :down}, state)
      iex> moved.cursor_line
      1
  """
  @spec handle_event(term(), t()) :: {:ok, t()} | {:noreply, t()}
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
    do:
      {:ok, state |> Selection.clear_selection() |> Cursor.move_down() |> Cursor.adjust_scroll()}

  def handle_event({:key, :left}, %{focused: true} = state),
    do:
      {:ok, state |> Selection.clear_selection() |> Cursor.move_left() |> Cursor.adjust_scroll()}

  def handle_event({:key, :right}, %{focused: true} = state),
    do:
      {:ok, state |> Selection.clear_selection() |> Cursor.move_right() |> Cursor.adjust_scroll()}

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

    {:ok,
     %{state | cursor_line: new_line, cursor_col: new_col, selection: nil}
     |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, :page_down}, %{focused: true} = state) do
    viewport_height = max(1, state.height - 2)
    new_line = min(length(state.lines) - 1, state.cursor_line + viewport_height)
    new_col = min(state.cursor_col, String.length(Enum.at(state.lines, new_line, "")))

    {:ok,
     %{state | cursor_line: new_line, cursor_col: new_col, selection: nil}
     |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, direction, [:shift]}, %{focused: true} = state)
      when direction in [:up, :down, :left, :right],
      do: {:ok, Selection.extend_selection(state, direction)}

  def handle_event({:key, :left, [:ctrl]}, %{focused: true} = state) do
    {new_row, new_col} = Cursor.word_left(state.lines, state.cursor_line, state.cursor_col)

    {:ok,
     %{state | cursor_line: new_row, cursor_col: new_col, selection: nil}
     |> Cursor.adjust_scroll()}
  end

  def handle_event({:key, :right, [:ctrl]}, %{focused: true} = state) do
    {new_row, new_col} = Cursor.word_right(state.lines, state.cursor_line, state.cursor_col)

    {:ok,
     %{state | cursor_line: new_row, cursor_col: new_col, selection: nil}
     |> Cursor.adjust_scroll()}
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

  def handle_event({:key, key, mods}, %{focused: true} = state) when is_list(mods) do
    clipboard_action(clipboard_binding(key, mods), state)
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

  defp clipboard_binding(key, mods) do
    Enum.find([:copy, :cut, :paste, :select_all], &Drafter.Clipboard.key?(&1, key, mods))
  end

  defp clipboard_action(:select_all, state), do: {:ok, Selection.select_all(state)}

  defp clipboard_action(:copy, state) do
    Clipboard.copy_selection(state)
    {:ok, state}
  end

  defp clipboard_action(:cut, %{read_only: true} = state), do: {:noreply, state}

  defp clipboard_action(:cut, state) do
    {tag, new_state} = Clipboard.handle_cut(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  defp clipboard_action(:paste, %{read_only: true} = state), do: {:noreply, state}

  defp clipboard_action(:paste, state) do
    {tag, new_state} = Clipboard.handle_paste(state)
    trigger_change(new_state)
    {tag, new_state}
  end

  defp clipboard_action(nil, state), do: {:noreply, state}

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  Accepts every option except `:selection_style`, and never touches the cursor,
  scroll offsets, selection or history directly. A `:text` that differs from the
  current one re-splits `:lines`, re-clamps the cursor into the new content, clears
  the selection and re-adjusts the scroll offset; identical text leaves all of that
  alone. `:gutter_width` is recomputed on every call.

      iex> state = Drafter.Widget.TextArea.mount(%{text: "one\\ntwo\\nthree"})
      iex> state = %{state | cursor_line: 2, cursor_col: 3}
      iex> updated = Drafter.Widget.TextArea.update(%{text: "a"}, state)
      iex> {updated.lines, updated.cursor_line, updated.cursor_col}
      {["a"], 0, 1}

      iex> state = Drafter.Widget.TextArea.mount(%{text: "a"})
      iex> Drafter.Widget.TextArea.update(%{show_line_numbers: true}, state).gutter_width
      4
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

    %{
      state
      | cursor_line: cursor_line,
        cursor_col: min(state.cursor_col, line_len),
        selection: nil
    }
    |> Cursor.adjust_scroll()
  end

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `6`, borders
  included.

      iex> Drafter.Widget.TextArea.preferred_height(nil, [])
      6

      iex> Drafter.Widget.TextArea.preferred_height(nil, height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 6)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.TextArea.component_tag()
      :text_area
  """
  @spec component_tag() :: :text_area
  def component_tag, do: :text_area

  @doc """
  Builds the props map for a `{:text_area, opts}` element.

  The positional argument is ignored. `:text` comes from
  `Drafter.Binding.get_bound_value/3`, so `bind: :key` seeds it from
  `opts[:__app_state__]` and plain `value:` is used otherwise, defaulting to `""`.
  `:on_change` is the binding's writer. `:width` and `:height` always come from
  `opts[:__rect__]`, itself defaulting to `%{width: 40, height: 6}`, and a
  `:width` or `:height` in `opts` is ignored. `:style` defaults to `%{}` here
  rather than to the palette `mount/1` would supply, and the four other style maps
  and `:max_checkpoints` are not forwarded at all.

      iex> props = Drafter.Widget.TextArea.from_component_opts(nil, placeholder: "Notes")
      iex> {props.text, props.placeholder, props.width, props.height, props.style}
      {"", "Notes", 40, 6, %{}}

      iex> opts = [bind: :body, __app_state__: %{body: "hello"}, __rect__: %{width: 20, height: 4}]
      iex> props = Drafter.Widget.TextArea.from_component_opts(nil, opts)
      iex> {props.text, props.width, props.height, is_function(props.on_change, 1)}
      {"hello", 20, 4, true}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
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

  @doc """
  Narrows a re-render to the props that may safely change after mount.

  Always passes `:on_change`, `:max_lines`, `:show_line_numbers`, `:language`,
  `:read_only`, `:trap_focus`, `:tab_behavior`, `:tab_size` and
  `:highlight_cursor_line`. Adds `:width`, `:height` and `:placeholder` only when
  they differ from the mounted state, and `:text` only when `opts` carries `:bind`
  or `:value` and the text differs — so an unbound editor keeps what the user
  typed.

      iex> props = Drafter.Widget.TextArea.from_component_opts(nil, [])
      iex> state = Drafter.Widget.TextArea.mount(props)
      iex> Drafter.Widget.TextArea.update_props_from_mount(props, state, []) |> Map.has_key?(:text)
      false

      iex> opts = [bind: :body, __app_state__: %{body: "hello"}]
      iex> props = Drafter.Widget.TextArea.from_component_opts(nil, opts)
      iex> state = Drafter.Widget.TextArea.mount(%{text: "old", width: 40, height: 6})
      iex> Drafter.Widget.TextArea.update_props_from_mount(props, state, opts).text
      "hello"
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
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

    base =
      if existing_state.width != mount_props.width do
        Map.put(base, :width, mount_props.width)
      else
        base
      end

    base =
      if existing_state.height != mount_props.height do
        Map.put(base, :height, mount_props.height)
      else
        base
      end

    base =
      if existing_state.placeholder != mount_props.placeholder do
        Map.put(base, :placeholder, mount_props.placeholder)
      else
        base
      end

    if (Keyword.has_key?(opts, :bind) or Keyword.has_key?(opts, :value)) and
         existing_state.text != mount_props.text do
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
