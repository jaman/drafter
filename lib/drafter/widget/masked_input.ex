defmodule Drafter.Widget.MaskedInput do
  @moduledoc """
  A single-line text input that enforces a character-by-character format mask.

  Unfilled positions are displayed as `_` placeholders. The cursor advances automatically
  after a valid character is entered. The `:on_change` callback receives the unmasked raw
  value (user-entered characters only, without literal separators).

  ## Mask format characters

    * `#` — accepts any printable character
    * `9` — accepts digits `0`–`9` only
    * `a` — accepts lowercase letters `a`–`z` only
    * `A` — accepts any letter (`a`–`z` or `A`–`Z`)
    * Any other character — treated as a literal separator and displayed as-is

  ## Component tag

  Tag `:masked_input`, built by `Drafter.App` as `{:masked_input, opts}`:

      masked_input(opts)

  `masked_input/1` requires a keyword list — there is no zero-argument form and
  no positional argument. `from_component_opts/2` wraps `:on_change` and
  `:on_submit` with `Drafter.Widget.Callback`, so both may be given as atom
  event names.

  ## Options

    * `:mask` - format mask string, e.g. `"(999) 999-9999"` for a US phone number.
      Default `nil`, which accepts no input at all and displays the raw value
      unchanged.
    * `:value` - initial raw value, unmasked characters only. Default `""`.
      Characters the mask rejects are dropped when it is applied.
    * `:placeholder` - hint text shown while the raw value is empty. Default `""`.
    * `:on_change` - atom event name or `(String.t() -> term())` called with the
      raw value after every insertion or deletion. Default `nil`.
    * `:on_submit` - atom event name or `(String.t() -> term())` called with the
      raw value when `enter` is pressed. Default `nil`.
    * `:style` - `t:map/0` of style overrides passed to the theme computation.
      Default `%{}`.
    * `:class` - theme class atom or list of them, normalised by
      `Drafter.Style.normalize_classes/1` and reaching `mount/1` as `:classes`.
      Default `[]`.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`. Every editing
      key binding requires it.

  `update/2` accepts `:mask`, `:value`, `:placeholder`, `:style`, `:classes`,
  `:app_module`, `:on_change` and `:on_submit`, and never moves the cursor.
  Through the component tree `update_props_from_mount/3` narrows that to
  `:on_change` and `:on_submit`, adding `:mask` and `:placeholder` only when they
  actually differ from the mounted state — so `:value` is mount-only and the text
  the user typed survives a re-render.

  ## Key bindings

  All of these require the widget to be focused; otherwise the event bubbles as
  `{:noreply, state}`.

    * `left` / `right` — move the cursor between editable positions
    * any character the mask position accepts — fills that position and advances
      the cursor
    * `backspace` — removes the character before the cursor and moves it back
    * `delete` — removes the character at the cursor
    * `enter` — calls `:on_submit`

  ## Widget value

  `Drafter.get_widget_value/1` returns `nil` for this widget: the text lives under
  `:raw_value` and `:value`, neither of which it reads. Use
  `get_unmasked_value/1` on the state from `Drafter.get_widget_state/1`.

  ## Usage

      masked_input(mask: "99/99/9999", placeholder: "DD/MM/YYYY", on_change: :date_changed)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :char]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  @placeholder_char "_"

  defstruct [
    :mask,
    :value,
    :raw_value,
    :placeholder,
    :style,
    :classes,
    :app_module,
    :focused,
    :cursor_pos,
    :on_change,
    :on_submit
  ]

  @type t :: %__MODULE__{
          mask: String.t() | nil,
          value: String.t(),
          raw_value: String.t(),
          placeholder: String.t(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          focused: boolean(),
          cursor_pos: non_neg_integer(),
          on_change: (String.t() -> term()) | nil,
          on_submit: (String.t() -> term()) | nil
        }

  @doc """
  Builds the widget state from `props`.

  `:value` is kept as `:raw_value` and also run through the mask to produce
  `:value`, with unfilled positions shown as `_`. `:cursor_pos` always starts at
  `0` and counts editable mask positions, not display columns.

      iex> Drafter.Widget.MaskedInput.mount(%{mask: "99/99"}).value
      "__/__"

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99", value: "1234"})
      iex> {state.value, state.raw_value, state.cursor_pos}
      {"12/34", "1234", 0}

      iex> Drafter.Widget.MaskedInput.mount(%{mask: "999", value: "1a2"}).value
      "12_"

      iex> state = Drafter.Widget.MaskedInput.mount(%{value: "anything"})
      iex> {state.mask, state.value}
      {nil, "anything"}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    mask = Map.get(props, :mask)
    raw_value = Map.get(props, :value, "")
    placeholder = Map.get(props, :placeholder, "")

    %__MODULE__{
      mask: mask,
      value: apply_mask(raw_value, mask),
      raw_value: raw_value,
      placeholder: placeholder,
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      focused: Map.get(props, :focused, false),
      cursor_pos: 0,
      on_change: Map.get(props, :on_change),
      on_submit: Map.get(props, :on_submit)
    }
  end

  @doc """
  Draws the field into `rect` as a single strip.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. The masked value is drawn once there is any raw input and the placeholder
  before that, either padded or truncated to `rect.width`. The cursor cell is drawn
  reversed only while the widget is focused and has input.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    computed = compute_style(state)
    {base_style, cursor_offset} = build_render_context(state, rect, computed)
    has_input = String.length(state.raw_value || "") > 0

    display_value =
      state
      |> pick_display_value(has_input)
      |> fit_to_width(rect.width)

    chars = String.graphemes(display_value)

    segments =
      Enum.with_index(chars, fn char, idx ->
        char_style =
          if idx == cursor_offset and state.focused and has_input do
            Map.put(base_style, :reverse, true)
          else
            base_style
          end

        Segment.new(char, char_style)
      end)

    [Strip.new(segments)]
  end

  @doc """
  Handles the field's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  A plain props map is passed through `mount/1` first, so the returned state is
  always a `t:t/0`. Recognised events:

    * `{:focus}` / `{:blur}` - set or clear `:focused`
    * `{:key, :left}` / `{:key, :right}` - move `:cursor_pos`, clamped to
      `0..(editable_positions - 1)`
    * `{:key, :backspace}` - delete before the cursor, or `{:noreply, state}` at
      position `0`
    * `{:key, :delete}` - delete at the cursor
    * `{:key, :enter}` - call `:on_submit` and return the state unchanged
    * `{:key, key}` where `key` is a single printable character, and
      `{:char, code}` - insert when the mask position accepts it, otherwise
      `{:noreply, state}`

  Every binding but focus and blur also requires `:focused`; without it, and for
  any unrecognised event, the result is `{:noreply, state}`.

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99", focused: true})
      iex> {:ok, typed} = Drafter.Widget.MaskedInput.handle_event({:char, ?5}, state)
      iex> {typed.value, typed.raw_value, typed.cursor_pos}
      {"5_/__", "5", 1}

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99", focused: true})
      iex> Drafter.Widget.MaskedInput.handle_event({:char, ?x}, state) |> elem(0)
      :noreply

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99", value: "12", focused: true})
      iex> {:ok, moved} = Drafter.Widget.MaskedInput.handle_event({:key, :right}, state)
      iex> {:ok, deleted} = Drafter.Widget.MaskedInput.handle_event({:key, :backspace}, moved)
      iex> {deleted.raw_value, deleted.value, deleted.cursor_pos}
      {"2", "2_/__", 0}

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99"})
      iex> Drafter.Widget.MaskedInput.handle_event({:char, ?5}, state) |> elem(0)
      :noreply
  """
  @spec handle_event(term(), t() | Drafter.Widget.props()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_event({:focus}, state) do
    state = ensure_mounted(state)
    {:ok, %{state | focused: true}}
  end

  def handle_event({:blur}, state) do
    state = ensure_mounted(state)
    {:ok, %{state | focused: false}}
  end

  def handle_event({:key, :left}, %{focused: true} = state) do
    state = ensure_mounted(state)
    {:ok, %{state | cursor_pos: max(0, state.cursor_pos - 1)}}
  end

  def handle_event({:key, :right}, %{focused: true} = state) do
    state = ensure_mounted(state)
    max_pos = count_mask_chars(state.mask) - 1
    {:ok, %{state | cursor_pos: min(max_pos, state.cursor_pos + 1)}}
  end

  def handle_event({:key, :backspace}, %{focused: true} = state) do
    state = ensure_mounted(state)

    if state.cursor_pos > 0 do
      {new_masked, new_raw} = delete_char(state, state.cursor_pos - 1)

      new_state = %{
        state
        | value: new_masked,
          raw_value: new_raw,
          cursor_pos: max(0, state.cursor_pos - 1)
      }

      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :delete}, %{focused: true} = state) do
    state = ensure_mounted(state)
    max_pos = count_mask_chars(state.mask) - 1

    if state.cursor_pos <= max_pos do
      {new_masked, new_raw} = delete_char(state, state.cursor_pos)
      new_state = %{state | value: new_masked, raw_value: new_raw}
      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :enter}, %{focused: true} = state) do
    state = ensure_mounted(state)
    trigger_submit(state)
    {:ok, state}
  end

  def handle_event({:key, key}, %{focused: true} = state) when is_atom(key) do
    state = ensure_mounted(state)
    char_str = Atom.to_string(key)

    if String.length(char_str) == 1 and String.printable?(char_str) do
      <<char_code::utf8>> = char_str
      try_insert_char(state, char_str, char_code)
    else
      {:noreply, state}
    end
  end

  def handle_event({:char, char}, %{focused: true} = state) when is_integer(char) do
    state = ensure_mounted(state)
    char_str = <<char::utf8>>
    try_insert_char(state, char_str, char)
  end

  def handle_event(_event, state) do
    {:noreply, ensure_mounted(state)}
  end

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  `:value` sets the raw value, and `:value` is re-masked on every call. The mask
  used for that is the one already on the state, so a `props` that changes both
  `:mask` and `:value` formats the new value with the old mask until the next
  update. `:cursor_pos` and `:focused` are never touched here.

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99"})
      iex> updated = Drafter.Widget.MaskedInput.update(%{value: "1234"}, state)
      iex> {updated.value, updated.raw_value}
      {"12/34", "1234"}

      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99"})
      iex> updated = Drafter.Widget.MaskedInput.update(%{mask: "999", value: "1234"}, state)
      iex> {updated.mask, updated.value}
      {"999", "12/34"}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    new_raw_value = Map.get(props, :value, state.raw_value)

    %{
      state
      | mask: Map.get(props, :mask, state.mask),
        value: apply_mask(new_raw_value, state.mask),
        raw_value: new_raw_value,
        placeholder: Map.get(props, :placeholder, state.placeholder),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        on_change: Map.get(props, :on_change, state.on_change),
        on_submit: Map.get(props, :on_submit, state.on_submit)
    }
  end

  @doc """
  The characters the user entered, without the mask's literal separators.

  Returns `:raw_value`, or `""` when it is `nil`.

      iex> Drafter.Widget.MaskedInput.mount(%{mask: "99/99", value: "1234"})
      ...> |> Drafter.Widget.MaskedInput.get_unmasked_value()
      "1234"

      iex> Drafter.Widget.MaskedInput.mount(%{mask: "99/99"})
      ...> |> Drafter.Widget.MaskedInput.get_unmasked_value()
      ""
  """
  @spec get_unmasked_value(t()) :: String.t()
  def get_unmasked_value(%__MODULE__{raw_value: raw_value}), do: raw_value || ""
  def get_unmasked_value(%__MODULE__{value: value, mask: mask}), do: strip_mask(value, mask)

  @doc """
  The number of rows the element asks for: always `3`. There is no `:height`
  override.

      iex> Drafter.Widget.MaskedInput.preferred_height(nil, height: 1)
      3
  """
  @spec preferred_height(term(), keyword()) :: 3
  def preferred_height(_args, _opts), do: 3

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.MaskedInput.component_tag()
      :masked_input
  """
  @spec component_tag() :: :masked_input
  def component_tag, do: :masked_input

  @doc """
  Builds the props map for a `{:masked_input, opts}` element.

  The positional argument is ignored. `:on_change` and `:on_submit` go through
  `Drafter.Widget.Callback.wrap_1/1`, so an atom becomes a closure that dispatches
  an app event. `:class` is normalised into `:classes` and `:__app_module__`
  becomes `:app_module`.

      iex> props = Drafter.Widget.MaskedInput.from_component_opts(nil, mask: "99/99")
      iex> {props.mask, props.value, props.placeholder, props.on_change}
      {"99/99", "", "", nil}

      iex> props = Drafter.Widget.MaskedInput.from_component_opts(nil, on_submit: :saved)
      iex> is_function(props.on_submit, 1)
      true
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    %{
      mask: Keyword.get(opts, :mask),
      value: Keyword.get(opts, :value, ""),
      placeholder: Keyword.get(opts, :placeholder, ""),
      on_change: Callback.wrap_1(Keyword.get(opts, :on_change)),
      on_submit: Callback.wrap_1(Keyword.get(opts, :on_submit)),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Narrows a re-render to `:on_change` and `:on_submit`, adding `:mask` and
  `:placeholder` only when they differ from the mounted state.

  `:value`, `:style` and `:classes` are always dropped, so the text the user typed
  survives a re-render.

      iex> props = Drafter.Widget.MaskedInput.from_component_opts(nil, mask: "99/99")
      iex> state = Drafter.Widget.MaskedInput.mount(props)
      iex> Drafter.Widget.MaskedInput.update_props_from_mount(props, state, []) |> Map.keys() |> Enum.sort()
      [:on_change, :on_submit]

      iex> props = Drafter.Widget.MaskedInput.from_component_opts(nil, mask: "999")
      iex> state = Drafter.Widget.MaskedInput.mount(%{mask: "99/99"})
      iex> Drafter.Widget.MaskedInput.update_props_from_mount(props, state, []).mask
      "999"
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, _opts) do
    base = %{
      on_change: mount_props.on_change,
      on_submit: mount_props.on_submit
    }

    base =
      if existing_state.mask != mount_props.mask do
        Map.put(base, :mask, mount_props.mask)
      else
        base
      end

    if existing_state.placeholder != mount_props.placeholder do
      Map.put(base, :placeholder, mount_props.placeholder)
    else
      base
    end
  end

  defp ensure_mounted(state) do
    if is_struct(state, __MODULE__), do: state, else: mount(state)
  end

  defp compute_style(state) do
    classes = state.classes ++ if state.focused, do: [:focus], else: []
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    Computed.for_widget(:masked_input, state, computed_opts)
  end

  defp build_render_context(state, rect, computed) do
    app_module = state.style[:app_module]
    theme = if app_module, do: app_module.__theme__(:get), else: Drafter.Theme.dark_theme()

    fg = Map.get(theme, :text_primary, {200, 200, 200})
    bg = computed[:background] || Map.get(theme, :background, {40, 40, 40})
    focus_bg = Map.get(theme, :panel, {60, 60, 80})
    actual_bg = if state.focused, do: focus_bg, else: bg
    base_style = %{fg: fg, bg: actual_bg}

    has_input = String.length(state.raw_value || "") > 0

    cursor_pos =
      if has_input do
        mask_positions = get_mask_positions(state.mask)

        if state.cursor_pos < length(mask_positions) do
          Enum.at(mask_positions, state.cursor_pos, 0)
        else
          0
        end
      else
        0
      end

    cursor_offset = min(cursor_pos, rect.width - 1)
    {base_style, cursor_offset}
  end

  defp pick_display_value(state, true), do: state.value
  defp pick_display_value(state, false), do: state.placeholder

  defp fit_to_width(value, width) do
    if String.length(value) < width do
      String.pad_trailing(value, width, " ")
    else
      String.slice(value, 0, width)
    end
  end

  defp try_insert_char(state, char_str, char_code) do
    max_pos = count_mask_chars(state.mask) - 1

    if state.cursor_pos <= max_pos do
      mask_char = get_mask_char_at(state.mask, state.cursor_pos)
      insert_if_accepted(state, char_str, char_code, mask_char)
    else
      {:noreply, state}
    end
  end

  defp insert_if_accepted(state, char_str, char_code, mask_char) when not is_nil(mask_char) do
    if accepts_char?(mask_char, char_code) do
      {new_masked, new_raw} = insert_char(state, char_str, state.cursor_pos)
      new_state = %{state | value: new_masked, raw_value: new_raw}
      new_state = move_cursor_next(new_state)
      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  defp insert_if_accepted(state, _char_str, _char_code, _mask_char), do: {:noreply, state}

  defp get_mask_positions(mask) when is_binary(mask) do
    mask
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {char, _idx} -> char in ["#", "9", "a", "A"] end)
    |> Enum.map(fn {_char, idx} -> idx end)
  end

  defp get_mask_char_at(mask, position) when is_binary(mask) do
    mask_positions = get_mask_positions(mask)

    if position < length(mask_positions) do
      mask_idx = Enum.at(mask_positions, position)
      mask |> String.graphemes() |> Enum.at(mask_idx)
    else
      nil
    end
  end

  defp get_mask_char_at(_mask, _position), do: nil

  defp count_mask_chars(mask) when is_binary(mask) do
    mask
    |> String.graphemes()
    |> Enum.count(fn char -> char in ["#", "9", "a", "A"] end)
  end

  defp count_mask_chars(_mask), do: 0

  defp accepts_char?("#", _char), do: true
  defp accepts_char?("9", char), do: char >= ?0 and char <= ?9
  defp accepts_char?("a", char), do: char >= ?a and char <= ?z
  defp accepts_char?("A", char), do: (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z)
  defp accepts_char?(_mask_char, _char), do: false

  defp apply_mask(input, nil), do: input || ""

  defp apply_mask(input, mask) when is_binary(mask) do
    mask_chars = String.graphemes(mask)
    input_chars = String.graphemes(input || "")
    mask_positions = get_mask_positions(mask)

    {_remaining, accepted_chars} =
      Enum.reduce(mask_positions, {input_chars, []}, fn mask_idx, {remaining_input, accepted} ->
        char_at_mask = Enum.at(mask_chars, mask_idx)
        consume_input_char(char_at_mask, remaining_input, accepted)
      end)

    build_mask_string(mask, accepted_chars)
  end

  defp consume_input_char(mask_char, [input_hd | input_tl], accepted)
       when mask_char in ["#", "9", "a", "A"] do
    char_code = String.to_charlist(input_hd) |> List.first()

    if accepts_char?(mask_char, char_code) do
      {input_tl, accepted ++ [input_hd]}
    else
      {input_tl, accepted}
    end
  end

  defp consume_input_char(mask_char, [], accepted) when mask_char in ["#", "9", "a", "A"] do
    {[], accepted}
  end

  defp consume_input_char(_mask_char, remaining, accepted), do: {remaining, accepted}

  defp build_mask_string(mask, input_chars) do
    {result, _remaining} =
      Enum.reduce(String.graphemes(mask), {"", input_chars}, fn mask_char, {acc, remaining} ->
        place_mask_char(mask_char, acc, remaining)
      end)

    result
  end

  defp place_mask_char(mask_char, acc, [input_hd | input_tl])
       when mask_char in ["#", "9", "a", "A"] do
    {acc <> input_hd, input_tl}
  end

  defp place_mask_char(mask_char, acc, []) when mask_char in ["#", "9", "a", "A"] do
    {acc <> @placeholder_char, []}
  end

  defp place_mask_char(literal, acc, remaining), do: {acc <> literal, remaining}

  defp strip_mask(value, mask) when is_binary(mask) do
    mask_chars = String.graphemes(mask)
    value_chars = String.graphemes(value || "")

    mask_chars
    |> Enum.zip(value_chars)
    |> Enum.filter(fn {m, _v} -> m in ["#", "9", "a", "A"] end)
    |> Enum.map_join(fn {_m, v} -> v end)
  end

  defp strip_mask(value, _mask), do: value || ""

  defp insert_char(state, char, position) do
    unmasked = get_unmasked_value(state)
    unmasked_chars = String.graphemes(unmasked)
    new_unmasked = List.insert_at(unmasked_chars, position, char) |> Enum.join()
    masked = apply_mask(new_unmasked, state.mask)
    {masked, new_unmasked}
  end

  defp delete_char(state, position) do
    unmasked = get_unmasked_value(state)
    unmasked_chars = String.graphemes(unmasked)

    if position < length(unmasked_chars) do
      new_unmasked = List.delete_at(unmasked_chars, position) |> Enum.join()
      masked = apply_mask(new_unmasked, state.mask)
      {masked, new_unmasked}
    else
      {state.value, state.raw_value}
    end
  end

  defp move_cursor_next(state) do
    max_pos = count_mask_chars(state.mask) - 1
    %{state | cursor_pos: min(max_pos, state.cursor_pos + 1)}
  end

  defp trigger_change(%{on_change: callback} = state) when is_function(callback, 1) do
    callback.(get_unmasked_value(state))
  end

  defp trigger_change(_state), do: :ok

  defp trigger_submit(%{on_submit: callback} = state) when is_function(callback, 1) do
    callback.(get_unmasked_value(state))
  end

  defp trigger_submit(_state), do: :ok
end
