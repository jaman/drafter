defmodule Drafter.Widget.TextInput do
  @moduledoc """
  A single-line text input widget with cursor navigation, text selection, and clipboard support.

  Renders inside a bordered box and shows a blinking-style cursor block when focused.
  Placeholder text is displayed when the field is empty and unfocused. Validation errors
  appear below the input border in red when the field has been touched (blurred at least once).

  ## Component tag

  Tag `:text_input`, built by `Drafter.App` as `{:text_input, opts}`:

      text_input(opts)

  There is no positional argument. The value goes through `Drafter.Binding`:
  passing `bind: :some_key` seeds the text from that app-state key and writes
  every keystroke back to it. `:width` is always the allocated rect width less
  two columns for the border.

  ## Options

    * `:text` - `t:String.t/0` initial value. Default `""`. Through the element the
      value comes from `:bind` instead.
    * `:placeholder` - `t:String.t/0` hint shown while the field is empty and
      unfocused. Default `""`.
    * `:bind` - app state key atom for two-way binding; the key is written on every
      keystroke. Default: none.
    * `:id` - atom identifier for programmatic access via
      `Drafter.get_widget_value/1`. Default: none.
    * `:on_change` - `({String.t(), validation_result()} -> term())` called on every
      keystroke, cursor move and selection change. Default `nil`. Through the
      element it is built by `Drafter.Binding.create_text_input_callback/1`, which
      returns `nil` when neither `:bind` nor `:on_change` is given. An exception it
      raises is swallowed.
    * `:on_submit` - atom event name or
      `({String.t(), validation_result()} -> term())` called when `enter` is
      pressed. Default `nil`. Setting it makes `enter` clear the field.
    * `:keep_focus` - `t:boolean/0`, refocus the widget after `:on_submit` fires.
      Default `false`. Read by `from_component_opts/2` only.
    * `:validators` - list of `Drafter.Validation` validators run on blur. Default
      `nil`.
    * `:disabled` - `t:boolean/0`; the field takes focus but ignores every other
      event. Default `false`.
    * `:readonly` - `t:boolean/0`; same handling as `:disabled`. Default `false`.
    * `:password` - `t:boolean/0`, render each character as `•`. Default `false`.
    * `:restrict` - a `t:Regex.t/0` or a string pattern compiled with
      `Regex.compile!/1`; only matching characters may be typed. Default `nil`.
    * `:type` - `:text | :integer | :number`. Default `:text`. `:integer` allows
      `0-9` and `-`, `:number` also allows `.`, and both apply on top of
      `:restrict`.
    * `:select_on_focus` - `t:boolean/0`, select the whole value on focus. Default
      `false`.
    * `:style` - `t:map/0` of style overrides passed to the theme computation.
      Default `%{}`.
    * `:class` - theme class atom or list of them, normalised by
      `Drafter.Util.normalize_classes/1` and reaching `mount/1` as `:classes`.
      Default `[]`.
    * `:max_length` - `t:pos_integer/0` cap on the number of characters. Default
      `nil`, no cap. Read by `mount/1` and `update/2` only; the `text_input/1`
      element does not forward it.
    * `:width` - `t:pos_integer/0` inner width the scroll offset works against.
      Default `40` when mounting directly. A `:width` in `opts` is ignored by the
      element, which always uses the allocated rect width less the two border
      columns.
    * `:cursor_position`, `:scroll_offset`, `:selection_start`, `:selection_end`,
      `:focused`, `:touched`, `:error` - read by `mount/1` with defaults `0`, `0`,
      `nil`, `nil`, `false`, `false` and `nil`.

  `update/2` accepts every key above except `:cursor_position` and
  `:scroll_offset`, and ignores `:text` entirely while the field is focused so
  typing is never overwritten by a re-render. Through the component tree
  `update_props_from_mount/3` always passes `:on_change`, `:on_submit`,
  `:classes`, `:validators`, `:disabled`, `:readonly`, `:password`, `:restrict`,
  `:type` and `:select_on_focus`; `:width` and `:placeholder` only when they
  changed, and `:text` only when `opts` carries `:bind` or `:value` and the text
  differs.

  ## Widget value

  `Drafter.get_widget_value/1` returns the current text, and
  `Drafter.set_widget_value/2` replaces it.

  ## Key bindings

    * Arrow keys — move cursor one character left/right
    * `Ctrl+←` / `Ctrl+→` — jump by word
    * `Shift+←` / `Shift+→` / `Shift+Home` / `Shift+End` — extend selection
    * `Ctrl+A` — select all
    * `Ctrl+C` / `Ctrl+X` / `Ctrl+V` — copy, cut, paste
    * `Ctrl+U` — delete from cursor to start of line
    * `Ctrl+K` — delete from cursor to end of line
    * `Ctrl+W` — delete word to the left of cursor
    * `Backspace` / `Delete` — delete character or selection
    * `Enter` — call `:on_submit` and clear the field; bubbles when no
      `:on_submit` is set
    * `Home` / `End` — move cursor to start/end of text

  A `:disabled` or `:readonly` field accepts `{:focus}`, `{:blur}` and `:activate`
  and returns `{:noreply, state}` for everything else.

  ## Usage

      text_input(placeholder: "Email address", on_submit: :login, validators: [:required, :email])
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :char, :click, :drag]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback
  alias Drafter.Widget.TextInput.{Clipboard, Rendering, Selection, Validation, WordNav}

  defstruct [
    :text,
    :placeholder,
    :cursor_position,
    :scroll_offset,
    :focused,
    :style,
    :classes,
    :on_change,
    :on_submit,
    :max_length,
    :width,
    :selection_start,
    :selection_end,
    :app_module,
    :validators,
    :error,
    :touched,
    :disabled,
    :readonly,
    :password,
    :restrict,
    :type,
    :select_on_focus
  ]

  @type validation_result :: {:ok, String.t()} | {:error, [String.t()]}

  @type t :: %__MODULE__{
          text: String.t(),
          placeholder: String.t(),
          cursor_position: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          focused: boolean(),
          style: map(),
          classes: [atom()],
          on_change: ({String.t(), validation_result()} -> term()) | nil,
          on_submit: ({String.t(), validation_result()} -> term()) | nil,
          max_length: pos_integer() | nil,
          width: pos_integer(),
          selection_start: non_neg_integer() | nil,
          selection_end: non_neg_integer() | nil,
          app_module: module() | nil,
          validators: [Drafter.Validation.validator()] | nil,
          error: String.t() | nil,
          touched: boolean(),
          disabled: boolean(),
          readonly: boolean(),
          password: boolean(),
          restrict: Regex.t() | nil,
          type: :text | :integer | :number,
          select_on_focus: boolean()
        }

  @doc """
  Builds the widget state from `props`.

  Every option listed in the module doc is read here with the default stated there.
  `:restrict` is compiled to a `t:Regex.t/0` when it is given as a string.

      iex> state = Drafter.Widget.TextInput.mount(%{})
      iex> {state.text, state.cursor_position, state.width, state.type, state.focused}
      {"", 0, 40, :text, false}

      iex> state = Drafter.Widget.TextInput.mount(%{text: "hi", placeholder: "name"})
      iex> {state.text, state.placeholder, state.max_length, state.error}
      {"hi", "name", nil, nil}

      iex> Drafter.Widget.TextInput.mount(%{restrict: "^[a-z]$"}).restrict |> Regex.source()
      "^[a-z]$"
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      text: Map.get(props, :text, ""),
      placeholder: Map.get(props, :placeholder, ""),
      cursor_position: Map.get(props, :cursor_position, 0),
      scroll_offset: Map.get(props, :scroll_offset, 0),
      focused: Map.get(props, :focused, false),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      on_change: Map.get(props, :on_change),
      on_submit: Map.get(props, :on_submit),
      max_length: Map.get(props, :max_length),
      width: Map.get(props, :width, 40),
      selection_start: Map.get(props, :selection_start),
      selection_end: Map.get(props, :selection_end),
      app_module: Map.get(props, :app_module),
      validators: Map.get(props, :validators),
      error: Map.get(props, :error),
      touched: Map.get(props, :touched, false),
      disabled: Map.get(props, :disabled, false),
      readonly: Map.get(props, :readonly, false),
      password: Map.get(props, :password, false),
      restrict: Validation.compile_restrict(Map.get(props, :restrict)),
      type: Map.get(props, :type, :text),
      select_on_focus: Map.get(props, :select_on_focus, false)
    }
  end

  @doc """
  Draws the bordered field into `rect`, always returning exactly `rect.height`
  strips.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. The first three strips are the top border, the content row and the bottom
  border; a non-`nil` `:error` adds a fourth in red. Shorter output is padded with
  blank rows and longer output is truncated, so a rect under three rows high loses
  the bottom of the box. The content is `min(state.width, rect.width - 2)` columns
  wide, drawn from `:scroll_offset`, with the cursor block shown only while
  focused.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    normalized_state =
      if is_struct(state, __MODULE__) do
        state
      else
        mount(state)
      end

    width = Map.get(normalized_state, :width, 40)
    content_width = min(width, rect.width - 2)
    display_text = Rendering.get_display_text(normalized_state, content_width)

    top_border = "┌" <> String.duplicate("─", content_width) <> "┐"
    bottom_border = "└" <> String.duplicate("─", content_width) <> "┘"

    focused = Map.get(normalized_state, :focused, false)
    classes = Map.get(normalized_state, :classes, [])
    app_module = Map.get(normalized_state, :app_module)
    error = Map.get(normalized_state, :error)
    disabled = Map.get(normalized_state, :disabled, false)

    state_classes = if disabled, do: [:disabled | classes], else: classes
    state_classes = if error, do: [:error | state_classes], else: state_classes

    computed_opts = [style: normalized_state.style, classes: state_classes]

    computed_opts =
      if app_module, do: Keyword.put(computed_opts, :app_module, app_module), else: computed_opts

    computed = Computed.for_widget(:text_input, normalized_state, computed_opts)
    border_computed = Computed.for_part(:text_input, normalized_state, :border, computed_opts)

    content_style = Computed.to_segment_style(computed)
    border_style = Computed.to_segment_style(border_computed)
    bg_style = %{fg: content_style[:fg], bg: border_style[:bg]}
    selection_style = Map.merge(content_style, %{reverse: true})

    content_segments =
      if Selection.has_selection?(normalized_state) do
        Selection.render_with_selection(
          normalized_state,
          display_text,
          content_width,
          content_style,
          selection_style
        )
      else
        cursor_pos = Rendering.get_visible_cursor_position(normalized_state, content_width)
        padded_text = String.pad_trailing(display_text, content_width)

        if focused do
          Rendering.insert_cursor(padded_text, cursor_pos, content_style)
        else
          [Segment.new(padded_text, content_style)]
        end
      end

    strips = [
      Strip.new([
        Segment.new(top_border, border_style),
        Segment.new(
          String.duplicate(" ", max(0, rect.width - String.length(top_border))),
          bg_style
        )
      ]),
      Strip.new(
        [
          Segment.new("│", border_style)
        ] ++
          content_segments ++
          [
            Segment.new("│", border_style),
            Segment.new(String.duplicate(" ", max(0, rect.width - content_width - 2)), bg_style)
          ]
      ),
      Strip.new([
        Segment.new(bottom_border, border_style),
        Segment.new(
          String.duplicate(" ", max(0, rect.width - String.length(bottom_border))),
          bg_style
        )
      ])
    ]

    error_strips =
      if error do
        error_style = %{fg: {186, 60, 91}}
        [Strip.new([Segment.new("  " <> error, error_style)])]
      else
        []
      end

    all_strips = strips ++ error_strips

    target_height = rect.height
    current_height = length(all_strips)

    if current_height < target_height do
      empty_line = Strip.from_text(String.duplicate(" ", rect.width))
      padding_lines = List.duplicate(empty_line, target_height - current_height)
      all_strips ++ padding_lines
    else
      Enum.take(all_strips, target_height)
    end
  end

  @doc """
  Handles the field's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  Routing goes in three stages. A `:disabled` or `:readonly` field only handles
  `{:focus}`, `{:blur}` and `:activate`, and returns `{:noreply, state}` for
  everything else. An unfocused field additionally handles a mouse up, `:validate`
  and `:clear_error`. A focused field handles the full set of key bindings listed
  in the module doc, `{:char, code}`, `{:bracketed_paste, text}`, mouse up and
  drag.

  Most handled events return `{:ok, new_state}`; `enter` with an `:on_submit`
  returns `{:ok, cleared_state, actions}`; `ctrl` with an unhandled key and `enter`
  without an `:on_submit` return `{:bubble, state}`; a keystroke the restriction
  rejects, a backspace at position zero and a delete at the end return
  `{:noreply, state}`.

      iex> state = Drafter.Widget.TextInput.mount(%{focused: true})
      iex> {:ok, typed} = Drafter.Widget.TextInput.handle_event({:char, ?a}, state)
      iex> {typed.text, typed.cursor_position}
      {"a", 1}

      iex> state = Drafter.Widget.TextInput.mount(%{focused: true, type: :integer})
      iex> Drafter.Widget.TextInput.handle_event({:char, ?a}, state) |> elem(0)
      :noreply

      iex> state = Drafter.Widget.TextInput.mount(%{text: "hi", focused: true, cursor_position: 2})
      iex> {:ok, deleted} = Drafter.Widget.TextInput.handle_event({:key, :backspace}, state)
      iex> {deleted.text, deleted.cursor_position}
      {"h", 1}

      iex> state = Drafter.Widget.TextInput.mount(%{text: "hi", disabled: true})
      iex> Drafter.Widget.TextInput.handle_event({:char, ?a}, state) |> elem(0)
      :noreply

      iex> state = Drafter.Widget.TextInput.mount(%{text: "hi", focused: true})
      iex> Drafter.Widget.TextInput.handle_event({:key, :enter}, state) |> elem(0)
      :bubble
  """
  @spec handle_event(term(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(event, state) do
    if state.disabled or state.readonly do
      handle_readonly_event(event, state)
    else
      handle_editable_event(event, state)
    end
  end

  defp handle_readonly_event(event, state) do
    case event do
      {:focus} -> {:ok, %{state | focused: true}}
      {:blur} -> {:ok, %{state | focused: false}}
      :activate -> {:ok, %{state | focused: true}}
      _ -> {:noreply, state}
    end
  end

  defp handle_editable_event(event, state) do
    if state.focused do
      handle_focused_event(event, state)
    else
      handle_unfocused_event(event, state)
    end
  end

  defp handle_unfocused_event(:activate, state), do: {:ok, %{state | focused: true}}
  defp handle_unfocused_event({:focus}, state), do: handle_focus_event(state)
  defp handle_unfocused_event({:blur}, state), do: handle_blur_event(state)

  defp handle_unfocused_event({:mouse, %{type: :mouse_up, x: x}}, state),
    do: handle_mouse_click(state, x)

  defp handle_unfocused_event(:validate, state), do: {:ok, Validation.do_validate(state)}
  defp handle_unfocused_event(:clear_error, state), do: {:ok, %{state | error: nil}}
  defp handle_unfocused_event(_, state), do: {:noreply, state}

  defp handle_focused_event({:key, dir, [:shift]}, state)
       when dir in [:left, :right, :home, :end] do
    new_state = Selection.handle_shift_selection(state, dir)
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_focused_event({:key, dir}, state) when dir in [:left, :right, :home, :end] do
    handle_cursor_move(state, dir)
  end

  defp handle_focused_event({:key, :backspace}, state), do: handle_backspace(state)
  defp handle_focused_event({:key, :delete}, state), do: handle_delete_key(state)
  defp handle_focused_event({:key, key, [:ctrl]}, state), do: handle_ctrl_key(state, key)

  defp handle_focused_event({:key, key, [:ctrl, :shift]}, state) when key in [:left, :right],
    do: handle_word_selection(state, key)

  defp handle_focused_event({:key, _key, [:ctrl | _]}, state), do: {:bubble, state}

  defp handle_focused_event({:key, :enter}, state) when state.on_submit != nil do
    new_state = %{
      state
      | text: "",
        cursor_position: 0,
        scroll_offset: 0,
        selection_start: nil,
        selection_end: nil
    }

    actions =
      case trigger_submit(state) do
        {:app_callback, _, _} = cb -> [cb]
        _ -> []
      end

    {:ok, new_state, actions}
  end

  defp handle_focused_event({:key, :enter}, state), do: {:bubble, state}

  defp handle_focused_event({:key, :" "}, state) do
    try_insert_char(state, " ")
  end

  defp handle_focused_event({:bracketed_paste, content}, state) do
    insert_string(state, String.replace(content, ~r/[\r\n]+/, " "))
  end

  defp handle_focused_event({:char, char}, state) when is_integer(char) do
    try_insert_char(state, <<char::utf8>>)
  end

  defp handle_focused_event({:key, key}, state) when is_atom(key) do
    try_insert_char(state, Atom.to_string(key))
  end

  defp handle_focused_event({:mouse, %{type: :mouse_up, x: x}}, state),
    do: handle_mouse_click(state, x)

  defp handle_focused_event({:mouse, %{type: :drag, x: x}}, state),
    do: handle_mouse_drag(state, x)

  defp handle_focused_event(:activate, state), do: {:ok, %{state | focused: true}}
  defp handle_focused_event({:focus}, state), do: handle_focus_event(state)
  defp handle_focused_event({:blur}, state), do: handle_blur_event(state)
  defp handle_focused_event(:validate, state), do: {:ok, Validation.do_validate(state)}
  defp handle_focused_event(:clear_error, state), do: {:ok, %{state | error: nil}}
  defp handle_focused_event(_, state), do: {:noreply, state}

  defp handle_cursor_move(state, :left) do
    new_position = max(0, state.cursor_position - 1)

    new_state =
      Selection.clear_selection(state)
      |> Map.put(:cursor_position, new_position)
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_cursor_move(state, :right) do
    new_position = min(String.length(state.text), state.cursor_position + 1)

    new_state =
      Selection.clear_selection(state)
      |> Map.put(:cursor_position, new_position)
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_cursor_move(state, :home) do
    new_state =
      Selection.clear_selection(state)
      |> Map.put(:cursor_position, 0)
      |> Map.put(:scroll_offset, 0)

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_cursor_move(state, :end) do
    text_length = String.length(state.text)

    new_state =
      Selection.clear_selection(state)
      |> Map.put(:cursor_position, text_length)
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_backspace(state) do
    if Selection.has_selection?(state) do
      new_state = Selection.delete_selection(state)
      trigger_change(new_state)
      {:ok, new_state}
    else
      delete_char_before_cursor(state)
    end
  end

  defp delete_char_before_cursor(%{cursor_position: 0} = state), do: {:noreply, state}

  defp delete_char_before_cursor(state) do
    {before, after_text} = String.split_at(state.text, state.cursor_position)
    new_text = String.slice(before, 0..-2//1) <> after_text

    new_state =
      %{state | text: new_text, cursor_position: state.cursor_position - 1}
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_delete_key(state) do
    if Selection.has_selection?(state) do
      new_state = Selection.delete_selection(state)
      trigger_change(new_state)
      {:ok, new_state}
    else
      delete_char_at_cursor(state)
    end
  end

  defp delete_char_at_cursor(state) do
    if state.cursor_position < String.length(state.text) do
      {before, after_text} = String.split_at(state.text, state.cursor_position)
      new_text = before <> String.slice(after_text, 1..-1//1)
      new_state = %{state | text: new_text}
      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  defp handle_ctrl_key(state, :c) do
    if Selection.has_selection?(state), do: Clipboard.copy_selection(state)
    {:noreply, state}
  end

  defp handle_ctrl_key(state, :x) do
    if Selection.has_selection?(state) do
      new_state = Clipboard.cut_selection(state)
      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  defp handle_ctrl_key(state, :v) do
    new_state = Clipboard.paste_from_clipboard(state)
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, :a) do
    text_length = String.length(state.text)

    new_state = %{
      state
      | selection_start: 0,
        selection_end: text_length,
        cursor_position: text_length
    }

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, :u) do
    after_text = String.slice(state.text, state.cursor_position..-1//1)

    new_state =
      %{state | text: after_text, cursor_position: 0, scroll_offset: 0}
      |> Selection.clear_selection()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, :k) do
    before_text = String.slice(state.text, 0, state.cursor_position)
    new_state = %{state | text: before_text} |> Selection.clear_selection()
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, :w) do
    new_state = WordNav.delete_word_left(state)
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, key) when key in [:left, :right] do
    new_state = WordNav.handle_word_navigation(state, key)
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_ctrl_key(state, :d), do: {:noreply, state}
  defp handle_ctrl_key(state, _key), do: {:bubble, state}

  defp handle_word_selection(state, key) do
    new_state = WordNav.handle_word_selection(state, key)
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp try_insert_char(state, char_str) do
    printable = Validation.printable_char?(char_str)
    can_insert = Validation.can_insert_char?(state)
    allowed = Validation.char_allowed?(state, char_str)

    if printable and can_insert and allowed do
      if Selection.has_selection?(state) do
        new_state = Selection.insert_char_replace_selection(state, char_str)
        trigger_change(new_state)
        {:ok, new_state}
      else
        insert_char(state, char_str)
      end
    else
      {:noreply, state}
    end
  end

  defp handle_mouse_click(state, x) do
    click_pos = max(0, x - 1)
    actual_pos = min(click_pos + state.scroll_offset, String.length(state.text))

    new_state =
      Selection.clear_selection(state)
      |> Map.put(:focused, true)
      |> Map.put(:cursor_position, actual_pos)
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_mouse_drag(state, x) do
    drag_pos = max(0, x - 1)
    actual_pos = min(drag_pos + state.scroll_offset, String.length(state.text))

    new_state =
      state
      |> Map.put(:focused, true)
      |> Map.put(:cursor_position, actual_pos)
      |> Selection.extend_selection(actual_pos)
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp handle_focus_event(state) do
    new_state =
      if state.select_on_focus do
        text_length = String.length(state.text)

        %{
          state
          | focused: true,
            selection_start: 0,
            selection_end: text_length,
            cursor_position: text_length
        }
      else
        %{state | focused: true}
      end

    {:ok, new_state}
  end

  defp handle_blur_event(state) do
    new_state = %{state | focused: false, touched: true}
    new_state = Validation.validate_if_touched(new_state)
    {:ok, new_state}
  end

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  `:text` is ignored entirely while the field is focused, so a re-render never
  overwrites what is being typed. Unfocused, it accepts either a string or a
  `{text, validation_result}` tuple and falls back to the current text for anything
  else. `:cursor_position` and `:scroll_offset` are never set here, so a shorter
  new text can leave the cursor past its end until the next keystroke.

      iex> state = Drafter.Widget.TextInput.mount(%{text: "old"})
      iex> Drafter.Widget.TextInput.update(%{text: "new"}, state).text
      "new"

      iex> state = Drafter.Widget.TextInput.mount(%{text: "typing", focused: true})
      iex> Drafter.Widget.TextInput.update(%{text: "clobber"}, state).text
      "typing"

      iex> state = Drafter.Widget.TextInput.mount(%{text: "old"})
      iex> Drafter.Widget.TextInput.update(%{text: {"tupled", {:ok, "tupled"}}}, state).text
      "tupled"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    bound_text =
      if state.focused do
        state.text
      else
        normalize_text_prop(Map.get(props, :text, state.text), state.text)
      end

    %{
      state
      | text: bound_text,
        placeholder: Map.get(props, :placeholder, state.placeholder),
        focused: Map.get(props, :focused, state.focused),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        on_change: Map.get(props, :on_change, state.on_change),
        on_submit: Map.get(props, :on_submit, state.on_submit),
        max_length: Map.get(props, :max_length, state.max_length),
        width: Map.get(props, :width, state.width),
        selection_start: Map.get(props, :selection_start, state.selection_start),
        selection_end: Map.get(props, :selection_end, state.selection_end),
        app_module: Map.get(props, :app_module, state.app_module),
        validators: Map.get(props, :validators, state.validators),
        error: Map.get(props, :error, state.error),
        touched: Map.get(props, :touched, state.touched),
        disabled: Map.get(props, :disabled, state.disabled),
        readonly: Map.get(props, :readonly, state.readonly),
        password: Map.get(props, :password, state.password),
        restrict: Validation.compile_restrict(Map.get(props, :restrict, state.restrict)),
        type: Map.get(props, :type, state.type),
        select_on_focus: Map.get(props, :select_on_focus, state.select_on_focus)
    }
  end

  @doc """
  The number of rows the element asks for: always `3`, the two border rows plus the
  content row. There is no `:height` override, and a validation error row is not
  accounted for.

      iex> Drafter.Widget.TextInput.preferred_height(nil, height: 10)
      3
  """
  @spec preferred_height(term(), keyword()) :: 3
  def preferred_height(_args, _opts), do: 3

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.TextInput.component_tag()
      :text_input
  """
  @spec component_tag() :: :text_input
  def component_tag, do: :text_input

  @doc """
  Builds the props map for a `{:text_input, opts}` element.

  The positional argument is ignored. `:text` comes from
  `Drafter.Binding.get_bound_value/3`, so `bind: :key` seeds it from
  `opts[:__app_state__]` and plain `value:` is used otherwise, defaulting to `""`.
  `:width` is the width of `opts[:__rect__]` less two border columns, with the rect
  defaulting to `%{width: 2}`. `:on_change` is the binding's writer and `:on_submit`
  is wrapped so that it dispatches the text and, when `:keep_focus` is set, sends
  `{:focus_widget, id}` back to the session. `:max_length`, `:style` and any
  `:width` in `opts` are not forwarded.

      iex> props = Drafter.Widget.TextInput.from_component_opts(nil, placeholder: "Email")
      iex> {props.text, props.placeholder, props.width, props.type, props.on_change}
      {"", "Email", 0, :text, nil}

      iex> opts = [bind: :query, __app_state__: %{query: "abc"}, __rect__: %{width: 22}]
      iex> props = Drafter.Widget.TextInput.from_component_opts(nil, opts)
      iex> {props.text, props.width, is_function(props.on_change, 1)}
      {"abc", 20, true}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 2})
    value = Drafter.Binding.get_bound_value(opts, app_state, "")
    on_submit = Keyword.get(opts, :on_submit)
    keep_focus = Keyword.get(opts, :keep_focus, false)
    widget_id = Keyword.get(opts, :__widget_id__)
    session_pid = self()
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))
    on_submit_fn = build_submit_fn(on_submit, keep_focus, session_pid, widget_id)

    %{
      text: value,
      placeholder: Keyword.get(opts, :placeholder, ""),
      width: rect.width - 2,
      classes: classes,
      validators: Keyword.get(opts, :validators),
      disabled: Keyword.get(opts, :disabled, false),
      readonly: Keyword.get(opts, :readonly, false),
      password: Keyword.get(opts, :password, false),
      restrict: Keyword.get(opts, :restrict),
      type: Keyword.get(opts, :type, :text),
      select_on_focus: Keyword.get(opts, :select_on_focus, false),
      on_change: Drafter.Binding.create_text_input_callback(opts),
      on_submit: on_submit_fn
    }
  end

  @doc """
  Narrows a re-render to the props that may safely change after mount.

  Always passes `:on_change`, `:on_submit`, `:classes`, `:validators`,
  `:disabled`, `:readonly`, `:password`, `:restrict`, `:type` and
  `:select_on_focus`. Adds `:width` and `:placeholder` only when they differ from
  the mounted state, and `:text` only when `opts` carries `:bind` or `:value` and
  the text differs — so an unbound field keeps whatever the user typed.

      iex> props = Drafter.Widget.TextInput.from_component_opts(nil, placeholder: "Email")
      iex> state = Drafter.Widget.TextInput.mount(props)
      iex> Drafter.Widget.TextInput.update_props_from_mount(props, state, []) |> Map.has_key?(:text)
      false

      iex> opts = [bind: :query, __app_state__: %{query: "abc"}]
      iex> props = Drafter.Widget.TextInput.from_component_opts(nil, opts)
      iex> state = Drafter.Widget.TextInput.mount(%{text: "old", width: 0, placeholder: ""})
      iex> Drafter.Widget.TextInput.update_props_from_mount(props, state, opts).text
      "abc"
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, opts) do
    base = %{
      on_change: mount_props.on_change,
      on_submit: mount_props.on_submit,
      classes: mount_props.classes,
      validators: mount_props.validators,
      disabled: mount_props.disabled,
      readonly: mount_props.readonly,
      password: mount_props.password,
      restrict: mount_props.restrict,
      type: mount_props.type,
      select_on_focus: mount_props.select_on_focus
    }

    base =
      if existing_state.width != mount_props.width do
        Map.put(base, :width, mount_props.width)
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

  defp normalize_text_prop(text, _fallback) when is_binary(text), do: text
  defp normalize_text_prop({text, _}, _fallback) when is_binary(text), do: text
  defp normalize_text_prop(_, fallback), do: fallback

  defp insert_char(state, char) do
    {before, after_text} = String.split_at(state.text, state.cursor_position)
    new_text = before <> char <> after_text

    new_state =
      %{state | text: new_text, cursor_position: state.cursor_position + 1}
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp insert_string(state, "") do
    {:ok, state}
  end

  defp insert_string(state, str) do
    {before, after_text} = String.split_at(state.text, state.cursor_position)
    new_text = before <> str <> after_text

    new_state =
      %{
        state
        | text: new_text,
          cursor_position: state.cursor_position + String.length(str),
          selection_start: nil,
          selection_end: nil
      }
      |> Rendering.adjust_scroll_offset()

    trigger_change(new_state)
    {:ok, new_state}
  end

  defp trigger_change(state) do
    if state.on_change do
      validation_result = Validation.build_validation_result(state)

      try do
        state.on_change.({state.text, validation_result})
      rescue
        _error -> :ok
      end
    end
  end

  defp trigger_submit(state) do
    if state.on_submit do
      validation_result = Validation.build_validation_result(state)

      try do
        state.on_submit.({state.text, validation_result})
      rescue
        _error -> :ok
      end
    end
  end

  defp build_submit_fn(nil, _keep_focus, _session_pid, _widget_id), do: nil

  defp build_submit_fn(on_submit, keep_focus, session_pid, widget_id) do
    wrapped = Callback.wrap_1_with_pid(on_submit, session_pid)

    fn {text, _vr} ->
      wrapped.(text)
      if keep_focus, do: send(session_pid, {:focus_widget, widget_id})
    end
  end
end
