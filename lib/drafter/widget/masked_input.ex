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

  ## Options

    * `:mask` - format mask string, e.g. `"(999) 999-9999"` for a US phone number
    * `:value` - initial raw value (unmasked characters, default: `""`)
    * `:placeholder` - hint text shown when the field has no input
    * `:on_change` - `(String.t() -> term())` called with the raw value on every change
    * `:style` - map of style overrides
    * `:classes` - list of theme class atoms

  ## Key bindings

    * `←` / `→` — move cursor between editable positions
    * Any valid character — fills the current mask position and advances the cursor
    * `Backspace` — removes the previous character and moves the cursor back
    * `Delete` — removes the character at the current cursor position

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

  def get_unmasked_value(%__MODULE__{raw_value: raw_value}), do: raw_value || ""
  def get_unmasked_value(%__MODULE__{value: value, mask: mask}), do: strip_mask(value, mask)

  def preferred_height(_args, _opts), do: 3

  def component_tag, do: :masked_input

  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

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
