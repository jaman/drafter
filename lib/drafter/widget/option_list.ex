defmodule Drafter.Widget.OptionList do
  @moduledoc """
  A scrollable, single-selection list widget with keyboard, mouse, and scroll wheel navigation.

  Each option is rendered as a row, and while the widget is focused the highlighted
  row carries a `▶` prefix. An unfocused list draws no prefix, so several lists can
  sit side by side with only the focused one showing a cursor.
  Disabled options are skipped during keyboard navigation. Mouse wheel scrolling is
  throttle-limited via `:scroll_throttle_ms` to prevent excessively fast navigation.

  An option is a map with `:id`, `:label`, `:selected` and `:disabled` keys.
  `option/3` builds one; `mount/1` takes options in that form only.

  ## Component tag

  Tag `:option_list`, built by `Drafter.App` as `{:option_list, items, opts}`:

      option_list(items, opts)

  The positional `items` list supplies the options, falling back to `opts[:options]`
  when it is empty. `from_component_opts/2` normalises each entry, so through the
  element an option may be given as a `{label, id}` tuple, a plain string used as
  both id and label, or a map containing `:id`. `:visible_height` defaults to the
  height of the rect the parent allocated.

  ## Options

    * `:options` - list of option maps, used when no positional `items` are given.
      Default `[]`. `mount/1` needs each entry to carry `:disabled` already, so
      build them with `option/3`; `from_component_opts/2` normalises looser forms.
    * `:selected` - id of the option to mark selected and highlight initially.
      Default `nil`, which highlights index `0`. Read by `from_component_opts/2`
      only — `mount/1` ignores both it and the `:highlighted_index` that function
      computes, and highlights the first enabled option instead.
    * `:visible_height` - `t:pos_integer/0` rows the scroll logic works with.
      Default `10` when mounting directly, and the height of `opts[:__rect__]`
      through the element, itself defaulting to `%{width: 40, height: 10}`.
    * `:expand_height` - `:content | :fill | pos_integer()`. Default `:content`,
      which draws `min(option_count, visible_height)` rows; `:fill` draws
      `rect.height` rows and an integer draws exactly that many.
    * `:on_select` - atom event name or `(option -> term())` called when an option
      is confirmed with `enter`, `space` or the mouse. Default `nil`. An atom is
      wrapped so that the app event carries the option's `:id`, not the whole map.
    * `:on_highlight` - atom event name or `(option -> term())` called when the
      highlighted option changes, wrapped the same way. Default `nil`.
    * `:scroll_throttle_ms` - `t:non_neg_integer/0` minimum milliseconds between
      wheel steps. Default `150`. The first wheel event is never throttled.
    * `:inverted_scroll` - `t:boolean/0`; when `true`, scrolling up moves the
      highlight down and vice versa. Default `false`.
    * `:trigger` - `:press | :mouse_up`, the mouse event that confirms a
      selection. Default `:press`. The other event bubbles.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`. Only a focused
      list draws the `▶` prefix; `{:focus}` and `{:blur}` maintain it, and
      `update_props_from_mount/3` leaves it alone so focus survives a re-render.

  `update/2` merges `props` into the state verbatim, so any key at all can be set
  through it. Through the component tree `update_props_from_mount/3` narrows a
  re-render to `:options`, `:visible_height`, `:on_select`, `:on_highlight`,
  `:trigger` and `:classes`, adding `:highlighted_index` only when the selected
  option's id actually changed — so `:expand_height`, `:scroll_throttle_ms` and
  `:inverted_scroll` are mount-only.

  ## Key bindings

    * `up` / `down` — move the highlight to the next enabled option, bubbling when
      there is none
    * `home` / `end` — jump to the first or last enabled option
    * `page_up` / `page_down` — jump by `:visible_height` rows
    * `enter` / `space` — confirm the highlighted option and call `:on_select`
    * mouse press or release, per `:trigger` — confirm the option on that row
    * mouse wheel — move the highlight one enabled option up or down

  A change that fires `:on_highlight` or `:on_select` returns
  `{:ok, state, actions}`, where each action is the value that callback returned.

  ## Widget value

  This widget's state has both `:selected_index` and `:options`, so
  `Drafter.get_widget_value/1` returns the id of the selected option. `mount/1`
  leaves `:selected_index` as `nil` until something is confirmed, and that raises
  `FunctionClauseError`; read `Drafter.get_widget_state/1` and its
  `:highlighted_index` when a selection is not guaranteed.

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
    traits: [:focusable],
    handles: [:keyboard, :press, :mouse_up, :scroll]

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
    trigger: :press,
    focused: false
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
          trigger: :press | :mouse_up,
          focused: boolean()
        }

  @doc """
  Builds a single option map for the `:options` list.

  `id` is the value handed to `:on_select` and `:on_highlight`; `label` is the
  text drawn in the row. Both must be binaries. A `disabled` option is drawn but
  skipped by keyboard navigation and cannot be selected.

  Returns a map with `:id`, `:label`, `:disabled` and `:selected`, where
  `:selected` starts as `false`.

      iex> Drafter.Widget.OptionList.option("two", "Option Two")
      %{id: "two", label: "Option Two", disabled: false, selected: false}

      iex> Drafter.Widget.OptionList.option("three", "Option Three", true)
      %{id: "three", label: "Option Three", disabled: true, selected: false}
  """
  @spec option(String.t(), String.t(), boolean()) :: option()
  def option(id, label, disabled \\ false)
      when is_binary(id) and is_binary(label) and is_boolean(disabled) do
    %{
      id: id,
      label: label,
      disabled: disabled,
      selected: false
    }
  end

  @doc """
  Builds the widget state from `props`.

  Every option listed in the module doc is read here with the default stated there,
  except `:selected` and `:highlighted_index`, which are ignored: the highlight
  always starts on the first option whose `:disabled` is falsy, and is `nil` for an
  empty or fully disabled list. `:selected_index`, `:scroll_offset` and
  `:last_scroll_time` all start at their zero values.

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> {state.highlighted_index, state.selected_index, state.visible_height}
      {0, nil, 10}

      iex> options = [Drafter.Widget.OptionList.option("a", "A", true), Drafter.Widget.OptionList.option("b", "B")]
      iex> Drafter.Widget.OptionList.mount(%{options: options}).highlighted_index
      1

      iex> state = Drafter.Widget.OptionList.mount(%{})
      iex> {state.highlighted_index, state.expand_height, state.trigger, state.scroll_throttle_ms}
      {nil, :content, :press, 150}

      iex> Drafter.Widget.OptionList.mount(%{focused: true}).focused
      true
  """
  @spec mount(Drafter.Widget.props()) :: t()
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
    focused = Map.get(props, :focused, false)

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
      trigger: trigger,
      focused: focused
    }
  end

  @doc """
  Draws the visible slice of the list into `rect`.

  The number of strips comes from `:expand_height`, not from `rect.height`:
  `:content` gives `min(option_count, visible_height)`, `:fill` gives
  `rect.height`, and an integer gives itself. Rows start at `:scroll_offset`, each
  is truncated and padded to `rect.width`, and the highlighted row is prefixed with
  `▶` when `:focused` is true.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
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

  @doc """
  Moves the highlight or confirms the highlighted option.

  Handles `:up`, `:down`, `:home`, `:end`, `:page_up`, `:page_down`, `:enter` and
  `:" "`; every other key returns `{:bubble, state}`. `:up` and `:down` bubble when
  there is no further enabled option, while `:home` and `:end` return
  `{:noreply, state}` when the list has none at all. A move that fires a callback
  returns `{:ok, state, actions}`.

      iex> options = [Drafter.Widget.OptionList.option("a", "A"), Drafter.Widget.OptionList.option("b", "B")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> {:ok, moved} = Drafter.Widget.OptionList.handle_key(:down, state)
      iex> {moved.highlighted_index, moved.selected_index}
      {1, nil}

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> Drafter.Widget.OptionList.handle_key(:up, state) == {:bubble, state}
      true

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> {:ok, chosen} = Drafter.Widget.OptionList.handle_key(:enter, state)
      iex> chosen.selected_index
      0

      iex> state = Drafter.Widget.OptionList.mount(%{})
      iex> Drafter.Widget.OptionList.handle_key(:x, state) == {:bubble, state}
      true
  """
  @spec handle_key(atom(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
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

  @doc """
  Confirms the option on row `y` when `:trigger` is `:press`, and returns
  `{:bubble, state}` otherwise.

  `y` is relative to the widget's rect and is offset by `:scroll_offset` to find
  the option. A row outside the list, or one holding a disabled option, returns
  `{:noreply, state}`. `x` is ignored.

      iex> options = [Drafter.Widget.OptionList.option("a", "A"), Drafter.Widget.OptionList.option("b", "B")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> {:ok, clicked} = Drafter.Widget.OptionList.handle_press(0, 1, state)
      iex> {clicked.highlighted_index, clicked.selected_index}
      {1, 1}

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options, trigger: :mouse_up})
      iex> Drafter.Widget.OptionList.handle_press(0, 0, state) == {:bubble, state}
      true
  """
  @spec handle_press(integer(), integer(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_press(_x, y, state) do
    if state.trigger == :press do
      clicked_index = y + state.scroll_offset
      action_click_option(state, clicked_index)
    else
      {:bubble, state}
    end
  end

  @doc """
  Confirms the option on row `y` when `:trigger` is `:mouse_up`, and returns
  `{:bubble, state}` otherwise. Otherwise identical to `handle_press/3`.

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options, trigger: :mouse_up})
      iex> {:ok, clicked} = Drafter.Widget.OptionList.handle_mouse_up(0, 0, state)
      iex> clicked.selected_index
      0

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> Drafter.Widget.OptionList.handle_mouse_up(0, 0, state) == {:bubble, state}
      true
  """
  @spec handle_mouse_up(integer(), integer(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_mouse_up(_x, y, state) do
    if state.trigger == :mouse_up do
      clicked_index = state.scroll_offset + y
      action_click_option(state, clicked_index)
    else
      {:bubble, state}
    end
  end

  @doc """
  Moves the highlight one enabled option per wheel step.

  `direction` is `:up` or `:down`, swapped when `:inverted_scroll` is set. Steps
  arriving less than `:scroll_throttle_ms` after the previous one return
  `{:noreply, state}` with only the timestamp updated; the first step after mount
  is never throttled. `:last_scroll_time` is stamped from
  `System.system_time(:millisecond)`.
  """
  @spec handle_scroll(:up | :down, t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    handle_scroll_event(state, direction)
  end

  @doc """
  Confirms the highlighted option on `:activate`, exactly as `enter` does, and
  returns `{:bubble, state}` for every other custom event.

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> {:ok, chosen} = Drafter.Widget.OptionList.handle_custom_event(:activate, state)
      iex> chosen.selected_index
      0

      iex> state = Drafter.Widget.OptionList.mount(%{})
      iex> Drafter.Widget.OptionList.handle_custom_event(:something, state) == {:bubble, state}
      true
  """
  @spec handle_custom_event(term(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:bubble, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_custom_event(:activate, state) do
    action_select_highlighted(state)
  end

  def handle_custom_event(_event, state), do: {:bubble, state}

  @doc """
  Routes an event, taking `{:focus}` itself and delegating everything else to the
  dispatch `use Drafter.Widget` generated.

  `{:focus}` moves the highlight onto the first enabled option when there is none
  yet, and sets `:focused` on the state. `{:blur}` reaches the generated dispatch,
  which clears the same field.
  """
  @spec handle_event(term(), t()) :: term()
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

    {:ok, %{new_state | focused: true}}
  end

  def handle_event(event, state) do
    super(event, state)
  end

  @doc """
  Merges `props` into `state` verbatim.

  Every key in `props` lands on the state as given, including keys the struct does
  not declare and `:options` entries that have not been normalised.

      iex> options = [Drafter.Widget.OptionList.option("a", "A")]
      iex> state = Drafter.Widget.OptionList.mount(%{options: options})
      iex> Drafter.Widget.OptionList.update(%{visible_height: 4}, state).visible_height
      4
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  The number of rows the element asks for.

  Returns `opts[:height]` when given, otherwise the length of the positional items
  list — which is `0` when the options were passed under `opts[:options]` instead.

      iex> Drafter.Widget.OptionList.preferred_height(["a", "b"], [])
      2

      iex> Drafter.Widget.OptionList.preferred_height(nil, options: ["a"])
      0

      iex> Drafter.Widget.OptionList.preferred_height(nil, height: 6)
      6
  """
  @spec preferred_height(list() | nil, keyword()) :: non_neg_integer()
  def preferred_height(args, opts), do: Keyword.get(opts, :height, length(args || []))

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.OptionList.component_tag()
      :option_list
  """
  @spec component_tag() :: :option_list
  def component_tag, do: :option_list

  @doc """
  Builds the props map for an `{:option_list, items, opts}` element.

  `items` is used when it is a non-empty list, otherwise `opts[:options]`,
  defaulting to `[]`. Each entry is normalised: a `{label, id}` tuple, a plain
  string used as both id and label, or a map already carrying `:id`, which keeps
  its own `:selected` and `:disabled` when it has them. The option whose id matches
  `:selected` is marked selected.

  `:on_select` and `:on_highlight` given as atoms are wrapped so the app event
  carries the option's `:id`; given as functions they are passed through and
  receive the whole option map. The emitted `:highlighted_index` and `:classes`
  keys are not read by `mount/1`.

      iex> props = Drafter.Widget.OptionList.from_component_opts([{"A", "a"}, "b"], selected: "b")
      iex> props.options
      [%{id: "a", label: "A", selected: false, disabled: false}, %{id: "b", label: "b", selected: true, disabled: false}]

      iex> props = Drafter.Widget.OptionList.from_component_opts(["a", "b"], selected: "b")
      iex> {props.highlighted_index, props.visible_height, props.trigger}
      {1, 10, :press}
  """
  @spec from_component_opts(list() | nil, keyword()) :: Drafter.Widget.props()
  def from_component_opts(items, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 10})
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

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

  @doc """
  Narrows a re-render to `:options`, `:visible_height`, `:on_select`,
  `:on_highlight`, `:trigger` and `:classes`, adding `:highlighted_index` only when
  the id of the selected option changed.

  `:expand_height`, `:scroll_throttle_ms` and `:inverted_scroll` are dropped, so
  they are mount-only through the component tree, and the highlight the user moved
  survives a re-render that does not change the selection.

      iex> props = Drafter.Widget.OptionList.from_component_opts(["a", "b"], [])
      iex> state = Drafter.Widget.OptionList.mount(props)
      iex> Drafter.Widget.OptionList.update_props_from_mount(props, state, []) |> Map.keys() |> Enum.sort()
      [:classes, :on_highlight, :on_select, :options, :trigger, :visible_height]

      iex> props = Drafter.Widget.OptionList.from_component_opts(["a", "b"], selected: "b")
      iex> state = Drafter.Widget.OptionList.mount(Drafter.Widget.OptionList.from_component_opts(["a", "b"], []))
      iex> Drafter.Widget.OptionList.update_props_from_mount(props, state, []).highlighted_index
      1
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, _opts) do
    current_selected = Enum.find(existing_state.options, fn o -> o.selected end)
    new_selected = Enum.find(mount_props.options, fn o -> o.selected end)
    selected_changed = Map.get(current_selected || %{}, :id) != Map.get(new_selected || %{}, :id)

    base = %{
      options: mount_props.options,
      visible_height: mount_props.visible_height,
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
        {:bubble, state}

      new_index ->
        change_selection(state, new_index, false)
    end
  end

  defp action_cursor_down(state) do
    case find_next_enabled(state.options, state.highlighted_index) do
      nil ->
        {:bubble, state}

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

  defp render_option(state, option, index, rect) do
    is_highlighted = index == state.highlighted_index and state.focused
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
    fitted_text = text |> String.slice(0, rect.width) |> String.pad_trailing(rect.width)

    segment = Segment.new(fitted_text, style)
    Strip.new([segment])
  end

  defp ensure_visible(state, target_index) do
    new_offset =
      Drafter.ScrollMath.ensure_visible(state.scroll_offset, target_index, state.visible_height)

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
