defmodule Drafter.Widget.OptionList do
  @moduledoc """
  A scrollable, single-selection list widget with keyboard, mouse, and scroll wheel navigation.

  Each option is rendered as a row with a `▶` highlight prefix on the currently focused item.
  Disabled options are skipped during keyboard navigation. Mouse wheel scrolling is
  throttle-limited via `:scroll_throttle_ms` to prevent excessively fast navigation.

  Options are created with `option/3` and passed as a list to `:options`.

  ## Options

    * `:options` - list of option maps created via `Drafter.Widget.OptionList.option/3`
    * `:visible_height` - number of rows to display (default: `10`)
    * `:expand_height` - height expansion behaviour: `:content` (fit to options, default),
      `:fill` (expand to available height), or an integer row count
    * `:on_select` - `(option -> term())` called when an option is confirmed via Enter or click
    * `:on_highlight` - `(option -> term())` called when the highlighted option changes
    * `:scroll_throttle_ms` - minimum milliseconds between scroll events (default: `150`)
    * `:inverted_scroll` - when `true`, scrolling up moves down and vice versa (default: `false`)

  ## Key bindings

    * `↑` / `↓` — move highlight one step
    * `Home` / `End` — jump to first/last enabled option
    * `Page Up` / `Page Down` — jump by `:visible_height` rows
    * `Enter` / `Space` — confirm selection and call `:on_select`
    * Mouse click — confirm selection on the clicked row
    * Mouse scroll — move highlight one step up or down

  ## Usage

      alias Drafter.Widget.OptionList

      option_list(
        options: [
          OptionList.option("one", "Option One"),
          OptionList.option("two", "Option Two"),
          OptionList.option("three", "Option Three", true)
        ],
        on_select: fn opt -> IO.inspect(opt.id) end
      )
  """

  use Drafter.Widget,
    handles: [:keyboard, :press, :mouse_up, :scroll],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  defstruct [
    :options,
    :highlighted_index,
    :selected_index,
    :scroll_offset,
    :visible_height,
    :on_select,
    :on_highlight,
    :last_scroll_time,
    :scroll_throttle_ms,
    :inverted_scroll,
    :expand_height,
    trigger: :press
  ]

  @type option :: %{
          id: String.t(),
          label: String.t(),
          disabled: boolean(),
          selected: boolean()
        }

  @type t :: %__MODULE__{
          options: [option()],
          highlighted_index: integer() | nil,
          selected_index: integer() | nil,
          scroll_offset: integer(),
          visible_height: integer(),
          on_select: (option() -> term()) | nil,
          on_highlight: (option() -> term()) | nil,
          last_scroll_time: integer(),
          scroll_throttle_ms: integer(),
          inverted_scroll: boolean(),
          expand_height: Drafter.Widget.expand_option(),
          trigger: :press | :mouse_up
        }

  def option(id, label, disabled \\ false)
      when is_binary(id) and is_binary(label) and is_boolean(disabled) do
    %{
      id: id,
      label: label,
      disabled: disabled,
      selected: false
    }
  end

  @impl Drafter.Widget
  def mount(props) do
    options = Map.get(props, :options, [])
    visible_height = Map.get(props, :visible_height, 10)
    on_select = Map.get(props, :on_select, nil)
    on_highlight = Map.get(props, :on_highlight, nil)
    scroll_throttle_ms = Map.get(props, :scroll_throttle_ms, 150)
    inverted_scroll = Map.get(props, :inverted_scroll, false)
    expand_height = Map.get(props, :expand_height, :content)
    trigger = Map.get(props, :trigger, :press)

    highlighted_index = find_first_enabled(options)

    %__MODULE__{
      options: options,
      highlighted_index: highlighted_index,
      selected_index: nil,
      scroll_offset: 0,
      visible_height: visible_height,
      on_select: on_select,
      on_highlight: on_highlight,
      last_scroll_time: 0,
      scroll_throttle_ms: scroll_throttle_ms,
      inverted_scroll: inverted_scroll,
      expand_height: expand_height,
      trigger: trigger
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    actual_height =
      case state.expand_height do
        :fill -> rect.height
        :content -> min(length(state.options), state.visible_height)
        height when is_integer(height) -> height
        _ -> state.visible_height
      end

    start_idx = state.scroll_offset

    visible_options = Enum.slice(state.options, start_idx, actual_height)

    strips =
      visible_options
      |> Enum.with_index(start_idx)
      |> Enum.map(fn {option, index} ->
        render_option(state, option, index, rect)
      end)

    computed = Computed.for_widget(:option_list, state)
    bg_style = Computed.to_segment_style(computed)

    current_height = length(strips)

    if current_height < actual_height do
      empty_segment = Segment.new(String.duplicate(" ", rect.width), bg_style)
      empty_line = Strip.new([empty_segment])
      padding_lines = List.duplicate(empty_line, actual_height - current_height)
      strips ++ padding_lines
    else
      strips
    end
  end

  @impl Drafter.Widget
  def handle_key(:up, state), do: action_cursor_up(state)
  def handle_key(:down, state), do: action_cursor_down(state)
  def handle_key(:home, state), do: action_cursor_first(state)
  def handle_key(:end, state), do: action_cursor_last(state)
  def handle_key(:page_up, state), do: action_page_up(state)
  def handle_key(:page_down, state), do: action_page_down(state)
  def handle_key(:enter, state), do: action_select_highlighted(state)
  def handle_key(:" ", state), do: action_select_highlighted(state)
  def handle_key(_key, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_press(_x, y, state) do
    if state.trigger == :press do
      clicked_index = y + state.scroll_offset
      action_click_option(state, clicked_index)
    else
      {:bubble, state}
    end
  end

  @impl Drafter.Widget
  def handle_mouse_up(_x, y, state) do
    if state.trigger == :mouse_up do
      clicked_index = state.scroll_offset + y
      action_click_option(state, clicked_index)
    else
      {:bubble, state}
    end
  end

  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    handle_scroll_event(state, direction)
  end

  @impl Drafter.Widget
  def handle_custom_event(:activate, state) do
    action_select_highlighted(state)
  end

  def handle_custom_event(_event, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_event({:focus}, state) do
    new_state =
      if state.highlighted_index == nil do
        case find_first_enabled(state.options) do
          nil -> state
          index -> %{state | highlighted_index: index}
        end
      else
        state
      end

    {:ok, Map.put(new_state, :focused, true)}
  end

  def handle_event(event, state) do
    super(event, state)
  end

  @impl Drafter.Widget
  def update(props, state) do
    Map.merge(state, props)
  end

  # Action implementations

  def preferred_height(args, opts), do: Keyword.get(opts, :height, length(args || []))

  def component_tag, do: :option_list

  def from_component_opts(items, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 10})
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

    classes =
      Enum.map(raw_classes, fn
        c when is_binary(c) -> String.to_atom(c)
        c when is_atom(c) -> c
      end)

    selected = Keyword.get(opts, :selected)

    raw_items =
      if is_list(items) and items != [], do: items, else: Keyword.get(opts, :options, [])

    options =
      Enum.map(raw_items, fn
        {label, id} ->
          %{id: id, label: to_string(label), selected: id == selected, disabled: false}

        label when is_binary(label) ->
          %{id: label, label: label, selected: label == selected, disabled: false}

        %{id: id} = item ->
          Map.merge(%{selected: id == selected, disabled: false}, item)
      end)

    highlighted_index =
      if selected do
        Enum.find_index(options, fn opt -> opt.id == selected end) || 0
      else
        0
      end

    %{
      options: options,
      highlighted_index: highlighted_index,
      visible_height: Keyword.get(opts, :visible_height, rect.height),
      on_select: wrap_id_callback(Keyword.get(opts, :on_select)),
      on_highlight: wrap_id_callback(Keyword.get(opts, :on_highlight)),
      scroll_throttle_ms: Keyword.get(opts, :scroll_throttle_ms, 150),
      inverted_scroll: Keyword.get(opts, :inverted_scroll, false),
      expand_height: Keyword.get(opts, :expand_height, :content),
      trigger: Keyword.get(opts, :trigger, :press),
      classes: classes
    }
  end

  def update_props_from_mount(mount_props, existing_state, _opts) do
    current_selected = Enum.find(existing_state.options, fn o -> o.selected end)
    new_selected = Enum.find(mount_props.options, fn o -> o.selected end)
    selected_changed = Map.get(current_selected || %{}, :id) != Map.get(new_selected || %{}, :id)

    base = %{
      options: mount_props.options,
      on_select: mount_props.on_select,
      on_highlight: mount_props.on_highlight,
      trigger: mount_props.trigger,
      classes: mount_props.classes
    }

    if selected_changed do
      Map.put(base, :highlighted_index, mount_props.highlighted_index)
    else
      base
    end
  end

  defp wrap_id_callback(nil), do: nil
  defp wrap_id_callback(cb) when is_function(cb), do: cb

  defp wrap_id_callback(name) when is_atom(name) do
    wrapped = Callback.wrap_1(name)
    fn option -> wrapped.(option.id) end
  end

  defp action_cursor_up(state) do
    case find_previous_enabled(state.options, state.highlighted_index) do
      nil ->
        {:noreply, state}

      new_index ->
        change_selection(state, new_index, false)
    end
  end

  defp action_cursor_down(state) do
    case find_next_enabled(state.options, state.highlighted_index) do
      nil ->
        {:noreply, state}

      new_index ->
        change_selection(state, new_index, false)
    end
  end

  defp action_cursor_first(state) do
    case find_first_enabled(state.options) do
      nil ->
        {:noreply, state}

      new_index ->
        change_selection(state, new_index, false)
    end
  end

  defp action_cursor_last(state) do
    case find_last_enabled(state.options) do
      nil ->
        {:noreply, state}

      new_index ->
        change_selection(state, new_index, false)
    end
  end

  defp action_page_up(state) do
    current = state.highlighted_index || 0
    target_index = max(0, current - state.visible_height)

    # Find closest enabled option
    new_index =
      case find_previous_enabled(state.options, target_index) do
        nil -> find_next_enabled(state.options, target_index) || find_first_enabled(state.options)
        index -> index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:noreply, state}
    end
  end

  defp action_page_down(state) do
    current = state.highlighted_index || 0
    target_index = min(length(state.options) - 1, current + state.visible_height)

    # Find closest enabled option
    new_index =
      case find_next_enabled(state.options, target_index) do
        nil ->
          find_previous_enabled(state.options, target_index) || find_last_enabled(state.options)

        index ->
          index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:noreply, state}
    end
  end

  defp action_select_highlighted(state) do
    if state.highlighted_index do
      change_selection(state, state.highlighted_index, true)
    else
      {:noreply, state}
    end
  end

  defp action_click_option(state, clicked_index) do
    if clicked_index >= 0 and clicked_index < length(state.options) do
      option = Enum.at(state.options, clicked_index)

      if option && !option.disabled do
        change_selection(state, clicked_index, true)
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Rendering helpers

  defp render_option(state, option, index, rect) do
    is_highlighted = index == state.highlighted_index
    is_selected = index == state.selected_index

    item_state = %{
      disabled: option.disabled,
      selected: is_selected,
      hovered: is_highlighted
    }

    computed = Computed.for_part(:option_list, item_state, :item)
    style = Computed.to_segment_style(computed)

    prefix = if is_highlighted, do: "▶ ", else: "  "

    text = prefix <> option.label
    padded_text = String.pad_trailing(text, rect.width)

    segment = Segment.new(padded_text, style)
    Strip.new([segment])
  end

  # Scroll management

  defp ensure_visible(state, target_index) do
    new_offset = Drafter.ScrollMath.ensure_visible(state.scroll_offset, target_index, state.visible_height)
    %{state | scroll_offset: new_offset}
  end

  defp find_first_enabled(options) do
    Enum.find_index(options, fn option -> !option.disabled end)
  end

  defp find_last_enabled(options) do
    options
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {option, index} ->
      if !option.disabled, do: index
    end)
  end

  defp find_next_enabled(options, current_index) do
    start_index = if current_index, do: current_index + 1, else: 0

    options
    |> Enum.slice(start_index..-1//1)
    |> Enum.find_index(fn option -> !option.disabled end)
    |> case do
      nil -> nil
      relative_index -> start_index + relative_index
    end
  end

  defp find_previous_enabled(options, current_index) do
    end_index = if current_index && current_index > 0, do: current_index - 1, else: -1

    if end_index >= 0 do
      options
      |> Enum.slice(0..end_index)
      |> Enum.reverse()
      |> Enum.find_index(fn option -> !option.disabled end)
      |> case do
        nil -> nil
        relative_index -> end_index - relative_index
      end
    else
      nil
    end
  end

  defp handle_scroll_event(state, direction) do
    current_time = System.system_time(:millisecond)

    if scroll_throttled?(state, current_time) do
      {:noreply, state}
    else
      actual_direction = resolve_direction(state.inverted_scroll, direction)
      scroll_result = execute_scroll_action(state, actual_direction)
      stamp_scroll_time(scroll_result, current_time)
    end
  end

  defp scroll_throttled?(%{last_scroll_time: 0}, _current_time), do: false

  defp scroll_throttled?(state, current_time) do
    current_time - state.last_scroll_time < state.scroll_throttle_ms
  end

  defp resolve_direction(true, :up), do: :down
  defp resolve_direction(true, :down), do: :up
  defp resolve_direction(false, direction), do: direction

  defp execute_scroll_action(state, :up), do: action_cursor_up(state)
  defp execute_scroll_action(state, :down), do: action_cursor_down(state)

  defp stamp_scroll_time({:ok, new_state, actions}, current_time),
    do: {:ok, %{new_state | last_scroll_time: current_time}, actions}

  defp stamp_scroll_time({:noreply, new_state}, current_time),
    do: {:noreply, %{new_state | last_scroll_time: current_time}}

  defp stamp_scroll_time(other, _current_time), do: other

  defp change_selection(state, target_index, trigger_select) do
    option = Enum.at(state.options, target_index)

    cond do
      target_index < 0 or target_index >= length(state.options) -> {:noreply, state}
      is_nil(option) or option.disabled -> {:noreply, state}
      true -> apply_option_selection(state, option, target_index, trigger_select)
    end
  end

  defp apply_option_selection(state, option, target_index, trigger_select) do
    new_state =
      state
      |> Map.put(:highlighted_index, target_index)
      |> ensure_visible(target_index)
      |> maybe_set_selected(target_index, trigger_select)

    actions =
      []
      |> maybe_add_highlight(state, option, target_index)
      |> maybe_add_on_select(state, option, trigger_select)

    if actions != [], do: {:ok, new_state, actions}, else: {:ok, new_state}
  end

  defp maybe_set_selected(state, target_index, true), do: %{state | selected_index: target_index}
  defp maybe_set_selected(state, _index, false), do: state

  defp maybe_add_highlight(actions, state, option, target_index) do
    if state.on_highlight && target_index != state.highlighted_index do
      [state.on_highlight.(option) | actions]
    else
      actions
    end
  end

  defp maybe_add_on_select(actions, state, option, true) when not is_nil(state.on_select) do
    [state.on_select.(option) | actions]
  end

  defp maybe_add_on_select(actions, _state, _option, _trigger), do: actions
end
