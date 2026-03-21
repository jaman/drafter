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

    * Arrow keys — move cursor by character or line
    * `Shift+Arrow` — extend selection
    * `Ctrl+A` — select all
    * `Ctrl+C` — copy selection to clipboard
    * `Ctrl+X` — cut selection to clipboard
    * `Ctrl+V` — paste from clipboard
    * `Ctrl+Z` — undo
    * `Ctrl+Y` — redo
    * `Ctrl+Left/Right` — word navigation
    * `Home` / `End` — move to start/end of the current line
    * `Page Up` / `Page Down` — move cursor by viewport height
    * `Backspace` / `Delete` — delete character; joins lines at line boundaries
    * `Enter` — insert a new line at the cursor position

  ## Usage

      text_area(placeholder: "Notes...", height: 10, show_line_numbers: true, language: :elixir)
  """

  use Drafter.Widget,
    handles: [:keyboard, :char],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :text,
    :lines,
    :cursor_line,
    :cursor_col,
    :scroll_offset,
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
          tab_behavior: :focus | :indent,
          tab_size: pos_integer(),
          max_checkpoints: pos_integer(),
          highlight_cursor_line: boolean(),
          undo_stack: list(),
          redo_stack: list()
        }

  @python_keywords ~w(def class if else elif for while return import from as try except finally with raise pass break continue lambda yield async await and or not in is True False None)
  @elixir_keywords ~w(def defp defmodule do end if else cond case when fn for with import alias require use true false nil and or not in)
  @javascript_keywords ~w(function const let var if else for while return import export from class extends new this true false null undefined async await try catch finally throw typeof instanceof)

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
    normalized_state =
      if is_struct(state, __MODULE__) do
        state
      else
        mount(state)
      end

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

    content_lines =
      render_content(normalized_state, content_width, content_height, effective_style)

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
                if String.length(line) > 0 do
                  if normalized_state.language do
                    highlight_line(line, normalized_state.language, effective_style)
                  else
                    [Segment.new(line, effective_style)]
                  end
                else
                  []
                end
              end

            padding_width = rect.width - gutter_width - String.length(line) - 2

            padding_segments =
              if padding_width > 0 do
                [Segment.new(String.duplicate(" ", padding_width), effective_style)]
              else
                []
              end

            all_segments =
              gutter_segment ++
                content_segments ++ padding_segments ++ [Segment.new("│", border_style)]

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
  def handle_event(event, state) do
    case event do
      {:key, :up} when state.focused ->
        {:ok, state |> clear_selection() |> do_move_cursor_up() |> adjust_scroll()}

      {:key, :down} when state.focused ->
        {:ok, state |> clear_selection() |> do_move_cursor_down() |> adjust_scroll()}

      {:key, :left} when state.focused ->
        {:ok, state |> clear_selection() |> do_move_cursor_left() |> adjust_scroll()}

      {:key, :right} when state.focused ->
        {:ok, state |> clear_selection() |> do_move_cursor_right() |> adjust_scroll()}

      {:key, :home} when state.focused ->
        {:ok, %{state | cursor_col: 0, selection: nil}}

      {:key, :end} when state.focused ->
        current_line = Enum.at(state.lines, state.cursor_line, "")
        {:ok, %{state | cursor_col: String.length(current_line), selection: nil}}

      {:key, :page_up} when state.focused ->
        viewport_height = max(1, state.height - 2)
        new_line = max(0, state.cursor_line - viewport_height)
        line_length = String.length(Enum.at(state.lines, new_line, ""))
        new_col = min(state.cursor_col, line_length)

        {:ok,
         %{state | cursor_line: new_line, cursor_col: new_col, selection: nil}
         |> adjust_scroll()}

      {:key, :page_down} when state.focused ->
        viewport_height = max(1, state.height - 2)
        new_line = min(length(state.lines) - 1, state.cursor_line + viewport_height)
        line_length = String.length(Enum.at(state.lines, new_line, ""))
        new_col = min(state.cursor_col, line_length)

        {:ok,
         %{state | cursor_line: new_line, cursor_col: new_col, selection: nil}
         |> adjust_scroll()}

      {:key, {:shift, :up}} when state.focused ->
        {:ok, extend_selection(state, :up)}

      {:key, {:shift, :down}} when state.focused ->
        {:ok, extend_selection(state, :down)}

      {:key, {:shift, :left}} when state.focused ->
        {:ok, extend_selection(state, :left)}

      {:key, {:shift, :right}} when state.focused ->
        {:ok, extend_selection(state, :right)}

      {:key, 1} when state.focused ->
        {:ok, select_all(state)}

      {:key, 3} when state.focused ->
        copy_selection(state)
        {:ok, state}

      {:key, 24} when state.focused ->
        handle_cut(state)

      {:key, 22} when state.focused and not state.read_only ->
        handle_paste(state)

      {:key, 26} when state.focused ->
        handle_undo(state)

      {:key, 25} when state.focused ->
        handle_redo(state)

      {:key, {:ctrl, :left}} when state.focused ->
        new_pos = word_left(state.lines, state.cursor_line, state.cursor_col)
        {new_row, new_col} = new_pos
        {:ok, %{state | cursor_line: new_row, cursor_col: new_col, selection: nil} |> adjust_scroll()}

      {:key, {:ctrl, :right}} when state.focused ->
        new_pos = word_right(state.lines, state.cursor_line, state.cursor_col)
        {new_row, new_col} = new_pos
        {:ok, %{state | cursor_line: new_row, cursor_col: new_col, selection: nil} |> adjust_scroll()}

      {:key, :backspace} when state.focused ->
        handle_backspace(state)

      {:key, :delete} when state.focused ->
        handle_delete(state)

      {:key, :enter} when state.focused ->
        handle_enter(state)

      {:key, :tab} when state.focused and state.tab_behavior == :indent ->
        handle_tab_indent(state)

      {:char, char} when state.focused and is_integer(char) ->
        char_str = <<char::utf8>>

        if printable_char?(char_str) and can_insert_char?(state) do
          handle_char_input(state, char_str)
        else
          {:noreply, state}
        end

      {:key, key} when state.focused and is_atom(key) ->
        char = Atom.to_string(key)

        if printable_char?(char) and can_insert_char?(state) do
          handle_char_input(state, char)
        else
          {:noreply, state}
        end

      {:focus} ->
        {:ok, %{state | focused: true}}

      {:blur} ->
        {:ok, %{state | focused: false}}

      _ ->
        {:noreply, state}
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    text = Map.get(props, :text, state.text)
    lines = if text != state.text, do: String.split(text, "\n"), else: state.lines
    show_line_numbers = Map.get(props, :show_line_numbers, state.show_line_numbers)

    gutter_width =
      if show_line_numbers do
        num_lines = length(lines)
        num_digits = max(3, String.length(Integer.to_string(num_lines)))
        num_digits + 1
      else
        0
      end

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
        tab_behavior: Map.get(props, :tab_behavior, state.tab_behavior),
        tab_size: Map.get(props, :tab_size, state.tab_size),
        max_checkpoints: Map.get(props, :max_checkpoints, state.max_checkpoints),
        highlight_cursor_line:
          Map.get(props, :highlight_cursor_line, state.highlight_cursor_line)
    }
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

  defp render_content(state, content_width, content_height, effective_style) do
    lines = state.lines
    focused = state.focused
    placeholder = state.placeholder

    if Enum.all?(lines, &(&1 == "")) and not focused and placeholder != "" do
      placeholder_lines =
        String.split(placeholder, "\n")
        |> Enum.map(fn line ->
          padded = String.pad_trailing(String.slice(line, 0, content_width), content_width)
          {padded, nil}
        end)
        |> Enum.take(content_height)

      padding_needed = max(0, content_height - length(placeholder_lines))

      placeholder_lines ++
        List.duplicate({String.duplicate(" ", content_width), nil}, padding_needed)
    else
      visible_lines =
        lines
        |> Enum.slice(state.scroll_offset, content_height)
        |> Enum.with_index(state.scroll_offset)
        |> Enum.map(fn {line, line_index} ->
          line_content = String.slice(line, 0, content_width)
          is_cursor_line = focused and line_index == state.cursor_line

          cursor_line_style =
            if state.highlight_cursor_line and is_cursor_line do
              tint_bg(effective_style, -15)
            else
              effective_style
            end

          segments =
            build_line_segments(
              state,
              line_content,
              line_index,
              content_width,
              cursor_line_style,
              effective_style
            )

          display_line =
            if is_cursor_line do
              insert_cursor_in_line(line_content, state.cursor_col, content_width)
            else
              String.pad_trailing(line_content, content_width)
            end

          {display_line, segments}
        end)

      padding_needed = max(0, content_height - length(visible_lines))

      visible_lines ++
        List.duplicate({String.duplicate(" ", content_width), nil}, padding_needed)
    end
  end

  defp build_line_segments(state, line_content, line_index, content_width, cursor_line_style, _effective_style) do
    focused = state.focused
    is_cursor_line = focused and line_index == state.cursor_line
    has_selection = state.selection != nil and focused

    cond do
      has_selection ->
        build_selection_segments(state, line_content, line_index, content_width, cursor_line_style)

      is_cursor_line ->
        build_cursor_segments(line_content, state.cursor_col, content_width, cursor_line_style)

      state.language != nil ->
        highlight_line(line_content, state.language, cursor_line_style)

      true ->
        [Segment.new(String.pad_trailing(line_content, content_width), cursor_line_style)]
    end
  end

  defp build_cursor_segments(line, cursor_col, content_width, style) do
    padded = String.pad_trailing(line, content_width)
    cursor_pos = min(cursor_col, content_width - 1)
    line_len = String.length(padded)

    if cursor_pos >= 0 and cursor_pos < line_len do
      before_text = String.slice(padded, 0, cursor_pos)
      cursor_char = String.slice(padded, cursor_pos, 1)
      after_text = String.slice(padded, cursor_pos + 1, line_len)

      cursor_style = %{fg: {0, 0, 0}, bg: {255, 255, 255}}

      [
        Segment.new(before_text, style),
        Segment.new(cursor_char, cursor_style),
        Segment.new(after_text, style)
      ]
      |> Enum.reject(&(&1.text == ""))
    else
      [
        Segment.new(padded, style),
        Segment.new(" ", %{fg: {0, 0, 0}, bg: {255, 255, 255}})
      ]
    end
  end

  defp build_selection_segments(state, line_content, line_index, content_width, base_style) do
    {sel_start_row, sel_start_col, sel_end_row, sel_end_col} = normalize_selection(state.selection)
    padded = String.pad_trailing(line_content, content_width)
    line_len = String.length(padded)

    cond do
      line_index < sel_start_row or line_index > sel_end_row ->
        if state.language != nil do
          highlight_line(padded, state.language, base_style)
        else
          [Segment.new(padded, base_style)]
        end

      true ->
        col_start =
          if line_index == sel_start_row, do: sel_start_col, else: 0

        col_end =
          if line_index == sel_end_row, do: min(sel_end_col, line_len), else: line_len

        before_text = String.slice(padded, 0, col_start)
        selected_text = String.slice(padded, col_start, col_end - col_start)
        after_text = String.slice(padded, col_end, line_len - col_end)

        is_cursor_line = state.focused and line_index == state.cursor_line
        cursor_col = state.cursor_col

        cursor_style = %{fg: {0, 0, 0}, bg: {255, 255, 255}}
        sel_style = state.selection_style

        segments = []

        segments =
          if before_text != "" do
            segments ++ [Segment.new(before_text, base_style)]
          else
            segments
          end

        segments =
          if selected_text != "" and is_cursor_line do
            build_selected_with_cursor(selected_text, col_start, cursor_col, sel_style, cursor_style, segments)
          else
            if selected_text != "" do
              segments ++ [Segment.new(selected_text, sel_style)]
            else
              segments
            end
          end

        segments =
          if after_text != "" and is_cursor_line and cursor_col >= col_end do
            after_cursor_pos = cursor_col - col_end
            after_len = String.length(after_text)

            if after_cursor_pos < after_len do
              before_c = String.slice(after_text, 0, after_cursor_pos)
              cursor_c = String.slice(after_text, after_cursor_pos, 1)
              after_c = String.slice(after_text, after_cursor_pos + 1, after_len)

              segs = if before_c != "", do: segments ++ [Segment.new(before_c, base_style)], else: segments
              segs = segs ++ [Segment.new(cursor_c, cursor_style)]
              if after_c != "", do: segs ++ [Segment.new(after_c, base_style)], else: segs
            else
              segments ++ [Segment.new(after_text, base_style)]
            end
          else
            if after_text != "" do
              segments ++ [Segment.new(after_text, base_style)]
            else
              segments
            end
          end

        segments
    end
  end

  defp build_selected_with_cursor(selected_text, col_start, cursor_col, sel_style, cursor_style, acc) do
    sel_len = String.length(selected_text)
    relative_cursor = cursor_col - col_start

    if relative_cursor >= 0 and relative_cursor < sel_len do
      before_c = String.slice(selected_text, 0, relative_cursor)
      cursor_c = String.slice(selected_text, relative_cursor, 1)
      after_c = String.slice(selected_text, relative_cursor + 1, sel_len)

      segs = if before_c != "", do: acc ++ [Segment.new(before_c, sel_style)], else: acc
      segs = segs ++ [Segment.new(cursor_c, cursor_style)]
      if after_c != "", do: segs ++ [Segment.new(after_c, sel_style)], else: segs
    else
      acc ++ [Segment.new(selected_text, sel_style)]
    end
  end

  defp insert_cursor_in_line(line, cursor_col, max_width) do
    padded_line = String.pad_trailing(line, max_width)
    cursor_pos = min(cursor_col, max_width - 1)

    if cursor_pos >= 0 and cursor_pos < String.length(padded_line) do
      {before, after_text} = String.split_at(padded_line, cursor_pos)
      after_char = String.slice(after_text, 1..-1//1) || ""
      before <> "█" <> after_char
    else
      padded_line <> "█"
    end
  end

  defp tint_bg(style, delta) do
    case Map.get(style, :bg) do
      {r, g, b} ->
        clamped = fn v -> max(0, min(255, v + delta)) end
        Map.put(style, :bg, {clamped.(r), clamped.(g), clamped.(b)})

      _ ->
        style
    end
  end

  defp normalize_selection({anchor_row, anchor_col, active_row, active_col}) do
    if {anchor_row, anchor_col} <= {active_row, active_col} do
      {anchor_row, anchor_col, active_row, active_col}
    else
      {active_row, active_col, anchor_row, anchor_col}
    end
  end

  defp clear_selection(state), do: %{state | selection: nil}

  defp select_all(state) do
    last_line = length(state.lines) - 1
    last_col = String.length(Enum.at(state.lines, last_line, ""))

    %{state | selection: {0, 0, last_line, last_col}, cursor_line: last_line, cursor_col: last_col}
  end

  defp extend_selection(state, direction) do
    anchor =
      case state.selection do
        nil -> {state.cursor_line, state.cursor_col}
        {ar, ac, _, _} -> {ar, ac}
      end

    moved_state = apply_cursor_move(state, direction)
    {anchor_row, anchor_col} = anchor

    %{moved_state
      | selection: {anchor_row, anchor_col, moved_state.cursor_line, moved_state.cursor_col}}
  end

  defp apply_cursor_move(state, :up), do: do_move_cursor_up(state) |> adjust_scroll()
  defp apply_cursor_move(state, :down), do: do_move_cursor_down(state) |> adjust_scroll()
  defp apply_cursor_move(state, :left), do: do_move_cursor_left(state) |> adjust_scroll()
  defp apply_cursor_move(state, :right), do: do_move_cursor_right(state) |> adjust_scroll()

  defp do_move_cursor_up(state) do
    if state.cursor_line > 0 do
      new_line = state.cursor_line - 1
      line_length = String.length(Enum.at(state.lines, new_line, ""))
      %{state | cursor_line: new_line, cursor_col: min(state.cursor_col, line_length)}
    else
      state
    end
  end

  defp do_move_cursor_down(state) do
    if state.cursor_line < length(state.lines) - 1 do
      new_line = state.cursor_line + 1
      line_length = String.length(Enum.at(state.lines, new_line, ""))
      %{state | cursor_line: new_line, cursor_col: min(state.cursor_col, line_length)}
    else
      state
    end
  end

  defp do_move_cursor_left(state) do
    if state.cursor_col > 0 do
      %{state | cursor_col: state.cursor_col - 1}
    else
      if state.cursor_line > 0 do
        prev_line = Enum.at(state.lines, state.cursor_line - 1, "")
        %{state | cursor_line: state.cursor_line - 1, cursor_col: String.length(prev_line)}
      else
        state
      end
    end
  end

  defp do_move_cursor_right(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")

    if state.cursor_col < String.length(current_line) do
      %{state | cursor_col: state.cursor_col + 1}
    else
      if state.cursor_line < length(state.lines) - 1 do
        %{state | cursor_line: state.cursor_line + 1, cursor_col: 0}
      else
        state
      end
    end
  end

  defp word_left(lines, row, 0) when row > 0 do
    prev_line = Enum.at(lines, row - 1, "")
    {row - 1, String.length(prev_line)}
  end

  defp word_left(_lines, row, 0), do: {row, 0}

  defp word_left(lines, row, col) do
    line = Enum.at(lines, row, "")
    chars = line |> String.slice(0, col) |> String.graphemes() |> Enum.reverse()
    {skipped_word, remaining} = take_while_count(chars, &word_char?/1)
    {skipped_non_word, _} = take_while_count(remaining, &(not word_char?(&1)))
    new_col = col - skipped_word - skipped_non_word
    {row, max(0, new_col)}
  end

  defp word_right(lines, row, col) do
    line = Enum.at(lines, row, "")
    line_len = String.length(line)

    if col >= line_len and row < length(lines) - 1 do
      {row + 1, 0}
    else
      chars = line |> String.slice(col, line_len - col) |> String.graphemes()
      {skipped_non_word, remaining} = take_while_count(chars, &(not word_char?(&1)))
      {skipped_word, _} = take_while_count(remaining, &word_char?/1)
      new_col = col + skipped_non_word + skipped_word
      {row, min(new_col, line_len)}
    end
  end

  defp take_while_count(list, pred), do: take_while_count(list, pred, 0)

  defp take_while_count([], _pred, count), do: {count, []}

  defp take_while_count([h | t], pred, count) do
    if pred.(h), do: take_while_count(t, pred, count + 1), else: {count, [h | t]}
  end

  defp word_char?(char), do: Regex.match?(~r/\w/, char)

  defp handle_backspace(state) do
    if state.selection != nil do
      {:ok, push_undo(state) |> delete_selection()}
    else
      if state.read_only do
        {:noreply, state}
      else
        do_backspace(state)
      end
    end
  end

  defp do_backspace(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    state = push_undo(state)

    cond do
      state.cursor_col > 0 ->
        {before, after_text} = String.split_at(current_line, state.cursor_col)
        new_line_content = String.slice(before, 0..-2//1) <> after_text
        new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

        new_state = %{
          state
          | lines: new_lines,
            cursor_col: state.cursor_col - 1,
            text: Enum.join(new_lines, "\n")
        }

        trigger_change(new_state)
        {:ok, new_state}

      state.cursor_line > 0 ->
        prev_line = Enum.at(state.lines, state.cursor_line - 1, "")
        joined_line = prev_line <> current_line

        new_lines =
          state.lines
          |> List.replace_at(state.cursor_line - 1, joined_line)
          |> List.delete_at(state.cursor_line)

        new_state =
          %{
            state
            | lines: new_lines,
              cursor_line: state.cursor_line - 1,
              cursor_col: String.length(prev_line),
              text: Enum.join(new_lines, "\n")
          }
          |> adjust_scroll()

        trigger_change(new_state)
        {:ok, new_state}

      true ->
        {:ok, state}
    end
  end

  defp handle_delete(state) do
    if state.selection != nil do
      {:ok, push_undo(state) |> delete_selection()}
    else
      if state.read_only do
        {:noreply, state}
      else
        do_delete(state)
      end
    end
  end

  defp do_delete(state) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    state = push_undo(state)

    cond do
      state.cursor_col < String.length(current_line) ->
        {before, after_text} = String.split_at(current_line, state.cursor_col)
        new_line_content = before <> String.slice(after_text, 1..-1//1)
        new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

        new_state = %{state | lines: new_lines, text: Enum.join(new_lines, "\n")}

        trigger_change(new_state)
        {:ok, new_state}

      state.cursor_line < length(state.lines) - 1 ->
        next_line = Enum.at(state.lines, state.cursor_line + 1, "")
        joined_line = current_line <> next_line

        new_lines =
          state.lines
          |> List.replace_at(state.cursor_line, joined_line)
          |> List.delete_at(state.cursor_line + 1)

        new_state = %{state | lines: new_lines, text: Enum.join(new_lines, "\n")}

        trigger_change(new_state)
        {:ok, new_state}

      true ->
        {:ok, state}
    end
  end

  defp handle_enter(state) do
    if state.read_only do
      {:noreply, state}
    else
      state = if state.selection != nil, do: push_undo(state) |> delete_selection(), else: push_undo(state)
      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)

      new_lines =
        state.lines
        |> List.replace_at(state.cursor_line, before)
        |> List.insert_at(state.cursor_line + 1, after_text)

      new_state =
        %{
          state
          | lines: new_lines,
            cursor_line: state.cursor_line + 1,
            cursor_col: 0,
            text: Enum.join(new_lines, "\n")
        }
        |> adjust_scroll()

      trigger_change(new_state)
      {:ok, new_state}
    end
  end

  defp handle_tab_indent(state) do
    if state.read_only do
      {:noreply, state}
    else
      spaces = String.duplicate(" ", state.tab_size)
      state = push_undo(state)
      state = if state.selection != nil, do: delete_selection(state), else: state

      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)
      new_line_content = before <> spaces <> after_text
      new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

      new_state = %{
        state
        | lines: new_lines,
          cursor_col: state.cursor_col + state.tab_size,
          text: Enum.join(new_lines, "\n")
      }

      trigger_change(new_state)
      {:ok, new_state}
    end
  end

  defp handle_char_input(state, char_str) do
    if state.read_only do
      {:noreply, state}
    else
      state = push_undo(state)
      state = if state.selection != nil, do: delete_selection(state), else: state
      insert_char(state, char_str)
    end
  end

  defp insert_char(state, char) do
    current_line = Enum.at(state.lines, state.cursor_line, "")
    {before, after_text} = String.split_at(current_line, state.cursor_col)
    new_line_content = before <> char <> after_text

    new_lines = List.replace_at(state.lines, state.cursor_line, new_line_content)

    new_state = %{
      state
      | lines: new_lines,
        cursor_col: state.cursor_col + 1,
        text: Enum.join(new_lines, "\n")
    }

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp delete_selection(state) do
    {start_row, start_col, end_row, end_col} = normalize_selection(state.selection)

    start_line = Enum.at(state.lines, start_row, "")
    end_line = Enum.at(state.lines, end_row, "")

    before_text = String.slice(start_line, 0, start_col)
    after_text = String.slice(end_line, end_col, String.length(end_line) - end_col)

    merged_line = before_text <> after_text

    lines_before = Enum.slice(state.lines, 0, start_row)
    lines_after = Enum.slice(state.lines, end_row + 1, length(state.lines))

    new_lines = lines_before ++ [merged_line] ++ lines_after

    %{
      state
      | lines: new_lines,
        cursor_line: start_row,
        cursor_col: start_col,
        selection: nil,
        text: Enum.join(new_lines, "\n")
    }
    |> adjust_scroll()
  end

  defp selected_text(state) do
    case state.selection do
      nil ->
        ""

      selection ->
        {start_row, start_col, end_row, end_col} = normalize_selection(selection)

        if start_row == end_row do
          line = Enum.at(state.lines, start_row, "")
          String.slice(line, start_col, end_col - start_col)
        else
          first_line = Enum.at(state.lines, start_row, "")
          last_line = Enum.at(state.lines, end_row, "")
          first_part = String.slice(first_line, start_col, String.length(first_line) - start_col)
          last_part = String.slice(last_line, 0, end_col)

          middle_lines =
            state.lines
            |> Enum.slice(start_row + 1, end_row - start_row - 1)

          ([first_part] ++ middle_lines ++ [last_part]) |> Enum.join("\n")
        end
    end
  end

  defp copy_selection(state) do
    text = selected_text(state)
    if text != "", do: clipboard_copy(text)
  end

  defp handle_cut(state) do
    if state.selection == nil or state.read_only do
      {:ok, state}
    else
      copy_selection(state)
      new_state = push_undo(state) |> delete_selection()
      trigger_change(new_state)
      {:ok, new_state}
    end
  end

  defp handle_paste(state) do
    text = clipboard_paste()

    if text == "" do
      {:ok, state}
    else
      state = push_undo(state)
      state = if state.selection != nil, do: delete_selection(state), else: state

      pasted_lines = String.split(text, "\n")
      current_line = Enum.at(state.lines, state.cursor_line, "")
      {before, after_text} = String.split_at(current_line, state.cursor_col)

      new_lines =
        case pasted_lines do
          [single] ->
            new_line = before <> single <> after_text
            List.replace_at(state.lines, state.cursor_line, new_line)

          [first | rest] ->
            last = List.last(rest)
            middle = Enum.slice(rest, 0, length(rest) - 1)
            first_line = before <> first
            last_line = last <> after_text

            lines_before = Enum.slice(state.lines, 0, state.cursor_line)
            lines_after = Enum.slice(state.lines, state.cursor_line + 1, length(state.lines))

            lines_before ++ [first_line] ++ middle ++ [last_line] ++ lines_after
        end

      new_cursor_line = state.cursor_line + length(pasted_lines) - 1
      last_pasted = List.last(pasted_lines)

      new_cursor_col =
        if length(pasted_lines) == 1 do
          state.cursor_col + String.length(last_pasted)
        else
          String.length(last_pasted)
        end

      new_state =
        %{
          state
          | lines: new_lines,
            cursor_line: new_cursor_line,
            cursor_col: new_cursor_col,
            text: Enum.join(new_lines, "\n")
        }
        |> adjust_scroll()

      trigger_change(new_state)
      {:ok, new_state}
    end
  end

  defp clipboard_copy(text) do
    case :os.type() do
      {:unix, :darwin} ->
        System.cmd("pbcopy", [], input: text, stderr_to_stdout: true)

      {:unix, _} ->
        System.cmd("xclip", ["-selection", "clipboard"], input: text, stderr_to_stdout: true)

      _ ->
        :ok
    end
  end

  defp clipboard_paste do
    try do
      case :os.type() do
        {:unix, :darwin} ->
          {output, 0} = System.cmd("pbpaste", [])
          output

        {:unix, _} ->
          {output, 0} = System.cmd("xclip", ["-selection", "clipboard", "-o"], [])
          output

        _ ->
          ""
      end
    rescue
      _ -> ""
    catch
      _, _ -> ""
    end
  end

  defp snapshot(state), do: {state.lines, state.cursor_line, state.cursor_col}

  defp push_undo(state) do
    snap = snapshot(state)
    trimmed = Enum.take([snap | state.undo_stack], state.max_checkpoints)
    %{state | undo_stack: trimmed, redo_stack: []}
  end

  defp handle_undo(state) do
    case state.undo_stack do
      [] ->
        {:ok, state}

      [prev | rest] ->
        current_snap = snapshot(state)
        {prev_lines, prev_row, prev_col} = prev

        new_state =
          %{
            state
            | lines: prev_lines,
              cursor_line: prev_row,
              cursor_col: prev_col,
              text: Enum.join(prev_lines, "\n"),
              undo_stack: rest,
              redo_stack: [current_snap | state.redo_stack],
              selection: nil
          }
          |> adjust_scroll()

        trigger_change(new_state)
        {:ok, new_state}
    end
  end

  defp handle_redo(state) do
    case state.redo_stack do
      [] ->
        {:ok, state}

      [next | rest] ->
        current_snap = snapshot(state)
        {next_lines, next_row, next_col} = next

        new_state =
          %{
            state
            | lines: next_lines,
              cursor_line: next_row,
              cursor_col: next_col,
              text: Enum.join(next_lines, "\n"),
              redo_stack: rest,
              undo_stack: [current_snap | state.undo_stack],
              selection: nil
          }
          |> adjust_scroll()

        trigger_change(new_state)
        {:ok, new_state}
    end
  end

  defp adjust_scroll(state) do
    content_height = state.height - 2

    cond do
      state.cursor_line < state.scroll_offset ->
        %{state | scroll_offset: state.cursor_line}

      state.cursor_line >= state.scroll_offset + content_height ->
        %{state | scroll_offset: state.cursor_line - content_height + 1}

      true ->
        state
    end
  end

  defp printable_char?(char) do
    String.length(char) == 1 and String.printable?(char) and char not in ["\t", "\r"]
  end

  defp highlight_line(line, language, base_style) do
    keywords = get_keywords(language)
    bg = base_style[:bg] || {40, 40, 40}

    keyword_color = {200, 120, 220}
    string_color = {180, 200, 100}
    comment_color = {100, 120, 100}
    number_color = {180, 150, 100}
    function_color = {100, 180, 220}

    tokens = tokenize_line(line, language)

    Enum.map(tokens, fn {type, text} ->
      color =
        case type do
          :keyword ->
            if text in keywords, do: keyword_color, else: base_style[:fg] || {200, 200, 200}

          :string ->
            string_color

          :comment ->
            comment_color

          :number ->
            number_color

          :function ->
            function_color

          _ ->
            base_style[:fg] || {200, 200, 200}
        end

      Segment.new(text, %{fg: color, bg: bg})
    end)
  end

  defp get_keywords(:python), do: @python_keywords
  defp get_keywords(:elixir), do: @elixir_keywords
  defp get_keywords(:javascript), do: @javascript_keywords
  defp get_keywords(:js), do: @javascript_keywords
  defp get_keywords(_), do: []

  defp tokenize_line(line, language) do
    comment_prefix =
      case language do
        :python -> "#"
        :elixir -> "#"
        :javascript -> "//"
        :js -> "//"
        _ -> "#"
      end

    if String.contains?(line, comment_prefix) do
      [before_comment, comment_text] = String.split(line, comment_prefix, parts: 2)
      tokenize_code(before_comment, language) ++ [{:comment, comment_prefix <> comment_text}]
    else
      tokenize_code(line, language)
    end
  end

  defp tokenize_code(code, language) do
    keywords = get_keywords(language)

    pattern = ~r/("[^"]*"|'[^']*'|\b\d+\.?\d*\b|\b\w+\b(?=\s*\()?|\b\w+\b|[^\s\w"']+|\s+)/

    Regex.scan(pattern, code)
    |> Enum.map(fn [match] ->
      cond do
        String.starts_with?(match, "\"") or String.starts_with?(match, "'") ->
          {:string, match}

        Regex.match?(~r/^\d+\.?\d*$/, match) ->
          {:number, match}

        Regex.match?(~r/^\w+$/, match) and match in keywords ->
          {:keyword, match}

        Regex.match?(~r/^\w+$/, match) ->
          {:identifier, match}

        true ->
          {:other, match}
      end
    end)
  end

  defp can_insert_char?(state) do
    case state.max_lines do
      nil -> true
      max_lines -> length(state.lines) < max_lines
    end
  end

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
