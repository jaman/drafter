defmodule Drafter.Widget.SelectionList do
  @moduledoc """
  A scrollable list widget that supports single or multiple item selection with checkbox-style indicators.

  In `:multiple` mode each item renders a `[X]` checkbox. In `:single` mode items render
  as `(●)` radio indicators. The `:on_change` callback receives a list of currently selected
  IDs after every selection change.

  ## Component tag

  Tag `:selection_list`, built by `Drafter.App` as `{:selection_list, options, opts}`:

      selection_list(options, opts)

  The positional `options` list is used when non-empty, falling back to
  `opts[:options]`. `from_component_opts/2` wraps `:on_change` and
  `:on_item_toggle` with `Drafter.Widget.Callback`, so both may be given as atom
  event names. `:visible_height` defaults to the rect the parent allocated.

  ## Options

    * `:options` - list of options in any of these formats. Default `[]`. Anything
      else raises `FunctionClauseError` from `mount/1`.
        * `"label"` — string used as both ID and label
        * `{"label", id}` — tuple with a display label and an identifier
        * `%{id: id, label: label}` — map with explicit fields
    * `:selected` - list of IDs that are initially selected. Default `[]`. Read by
      `mount/1` only; an ID that matches no option is ignored.
    * `:selection_mode` - `:multiple | :single`. Default `:multiple`. Any other
      value behaves like `:single` when toggling and like `:multiple` when
      drawing.
    * `:on_change` - atom event name or `([id] -> term())` called with the full
      list of selected IDs after every change. Default `nil`. An exception it
      raises is swallowed.
    * `:on_item_toggle` - atom event name or `((index, selected?) -> term())`
      called with the zero-based row index and its new boolean state each time one
      item is toggled. Default `nil`. Not called by the select-all binding. An
      exception it raises is swallowed.
    * `:visible_height` - `t:non_neg_integer/0` rows the scroll logic assumes.
      Default: the number of options when mounting directly, and the height of
      `opts[:__rect__]` through the element. `render/2` uses the rect it is given
      instead.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`.

  Through the component tree `update_props_from_mount/3` narrows a re-render to
  `:on_change`, `:on_item_toggle`, `:selection_mode` and `:classes`, so
  `:options`, `:selected` and `:visible_height` are mount-only.

  ## Key bindings

    * `up` / `down` — move the cursor, clamped at the ends, scrolling to keep it
      inside `:visible_height`
    * `home` / `end` — jump to the first or last item
    * `space` / `enter` — toggle selection of the highlighted item
    * `ctrl+a` — in `:multiple` mode, select every item, or clear the selection
      when everything is already selected
    * mouse up — move the cursor to the clicked row and toggle it

  ## Widget value

  `Drafter.get_widget_value/1` returns the list of selected option IDs, in option
  order.

  ## Usage

      selection_list(
        options: [{"Elixir", :ex}, {"Erlang", :erl}, {"Gleam", :gleam}],
        selected: [:ex],
        selection_mode: :multiple,
        on_change: fn ids -> IO.inspect(ids) end
      )
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :char]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  defstruct [
    :options,
    :selected_indices,
    :highlighted_index,
    :focused,
    :on_change,
    :on_item_toggle,
    :visible_height,
    :scroll_offset,
    :selection_mode
  ]

  @type option :: %{id: term(), label: String.t()}

  @type t :: %__MODULE__{
          options: [option()],
          selected_indices: MapSet.t(non_neg_integer()),
          highlighted_index: non_neg_integer(),
          focused: boolean(),
          on_change: ([term()] -> term()) | nil,
          on_item_toggle: (non_neg_integer(), boolean() -> term()) | nil,
          visible_height: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          selection_mode: :multiple | :single
        }

  @doc """
  Builds the widget state from `props`.

  Options are normalised into `%{id: id, label: label}` maps and `:selected` is
  turned into the matching set of indices. `:highlighted_index` and
  `:scroll_offset` always start at `0`.

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"]})
      iex> {state.options, MapSet.to_list(state.selected_indices), state.selection_mode}
      {[%{id: "a", label: "a"}, %{id: "b", label: "b"}], [], :multiple}

      iex> options = [{"Elixir", :ex}, {"Erlang", :erl}]
      iex> state = Drafter.Widget.SelectionList.mount(%{options: options, selected: [:erl]})
      iex> MapSet.to_list(state.selected_indices)
      [1]

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"], selected: [:missing]})
      iex> {MapSet.to_list(state.selected_indices), state.visible_height}
      {[], 2}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    options = Map.get(props, :options, [])
    selected = Map.get(props, :selected, [])
    selection_mode = Map.get(props, :selection_mode, :multiple)

    normalized_options = normalize_options(options)

    selected_indices =
      normalized_options
      |> Enum.with_index()
      |> Enum.filter(fn {opt, _idx} -> opt.id in selected end)
      |> Enum.map(fn {_opt, idx} -> idx end)
      |> MapSet.new()

    %__MODULE__{
      options: normalized_options,
      selected_indices: selected_indices,
      highlighted_index: 0,
      focused: Map.get(props, :focused, false),
      on_change: Map.get(props, :on_change),
      on_item_toggle: Map.get(props, :on_item_toggle),
      visible_height: Map.get(props, :visible_height, length(options)),
      scroll_offset: 0,
      selection_mode: selection_mode
    }
  end

  @doc """
  Draws the visible slice of the list into `rect`, always returning exactly
  `rect.height` strips.

  Rows start at `:scroll_offset` and run for `min(rect.height, option_count)`
  rows; the rest of the rect is blank. `:single` mode draws `(●)` and `( )`, every
  other mode draws `[X]` and `[ ]`. The highlight is only drawn while the widget is
  focused.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    computed = Computed.for_widget(:selection_list, state)
    bg_style = Computed.to_segment_style(computed)

    actual_height = min(rect.height, length(state.options))

    visible_options =
      state.options
      |> Enum.drop(state.scroll_offset)
      |> Enum.take(actual_height)

    strips =
      visible_options
      |> Enum.with_index()
      |> Enum.map(fn {option, visible_index} ->
        actual_index = state.scroll_offset + visible_index
        render_option(state, option, actual_index, rect.width)
      end)

    current_height = length(strips)

    if current_height < rect.height do
      empty_line = Segment.new(String.duplicate(" ", rect.width), bg_style)
      empty_strip = Strip.new([empty_line])
      padding = List.duplicate(empty_strip, rect.height - current_height)
      strips ++ padding
    else
      strips
    end
  end

  @doc """
  Merges `props` into `state` verbatim.

  Every key in `props` lands on the state as given, including keys the struct does
  not declare, and `:options` is stored without being normalised — so a re-render
  that goes through this must already supply `%{id: _, label: _}` maps.
  `:selection_mode` and `:on_item_toggle` keep their current value when absent.

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"]})
      iex> Drafter.Widget.SelectionList.update(%{selection_mode: :single}, state).selection_mode
      :single

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"]})
      iex> Drafter.Widget.SelectionList.update(%{highlighted_index: 1}, state).highlighted_index
      1
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    new_state = Map.merge(state, props)

    selection_mode = Map.get(props, :selection_mode, state.selection_mode)

    %{new_state | selection_mode: selection_mode}
    |> then(fn s ->
      case Map.fetch(props, :on_item_toggle) do
        {:ok, cb} -> %{s | on_item_toggle: cb}
        :error -> s
      end
    end)
  end

  @doc """
  Handles the list's own events, replacing the dispatch `use Drafter.Widget` would
  otherwise generate.

  Recognised events, each returning `{:ok, new_state}`:

    * `{:key, :up}` / `{:key, :down}` - move `:highlighted_index`, clamped at both
      ends, adjusting `:scroll_offset` to keep it within `:visible_height`
    * `{:key, :home}` - first item, scrolled to the top
    * `{:key, :end}` - last item
    * `{:key, :enter}` / `{:key, :" "}` - toggle the highlighted item
    * `{:char, 1}` - in `:multiple` mode only, select every item or clear the
      selection when everything is already selected
    * `{:mouse, %{type: :mouse_up, y: y}}` - toggle the row at `y`, or
      `{:noreply, state}` when it falls outside the list
    * `{:focus}` / `{:blur}` - set or clear `:focused`

  Every other event returns `{:noreply, state}`. Toggling calls `:on_change` with
  the full list of selected IDs and `:on_item_toggle` with the index and its new
  state; the select-all binding calls `:on_change` only.

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"]})
      iex> {:ok, toggled} = Drafter.Widget.SelectionList.handle_event({:key, :enter}, state)
      iex> MapSet.to_list(toggled.selected_indices)
      [0]

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b"]})
      iex> {:ok, moved} = Drafter.Widget.SelectionList.handle_event({:key, :down}, state)
      iex> {:ok, back} = Drafter.Widget.SelectionList.handle_event({:key, :up}, moved)
      iex> {moved.highlighted_index, back.highlighted_index}
      {1, 0}

      iex> state = Drafter.Widget.SelectionList.mount(%{options: ["a", "b", "c"]})
      iex> {:ok, all} = Drafter.Widget.SelectionList.handle_event({:char, 1}, state)
      iex> {:ok, none} = Drafter.Widget.SelectionList.handle_event({:char, 1}, all)
      iex> {MapSet.to_list(all.selected_indices), MapSet.to_list(none.selected_indices)}
      {[0, 1, 2], []}
  """
  @spec handle_event(term(), t()) :: {:ok, t()} | {:noreply, t()}
  def handle_event({:key, :up}, state) do
    {:ok, %{state | highlighted_index: max(0, state.highlighted_index - 1)} |> ensure_visible()}
  end

  def handle_event({:key, :down}, state) do
    {:ok,
     %{state | highlighted_index: min(length(state.options) - 1, state.highlighted_index + 1)}
     |> ensure_visible()}
  end

  def handle_event({:key, :home}, state),
    do: {:ok, %{state | highlighted_index: 0, scroll_offset: 0}}

  def handle_event({:key, :end}, state) do
    {:ok, %{state | highlighted_index: length(state.options) - 1} |> ensure_visible()}
  end

  def handle_event({:char, 1}, %{selection_mode: :multiple} = state) do
    all_indices = MapSet.new(0..(length(state.options) - 1)//1)

    new_selected =
      if MapSet.equal?(state.selected_indices, all_indices), do: MapSet.new(), else: all_indices

    new_state = %{state | selected_indices: new_selected}
    trigger_change(new_state)
    {:ok, new_state}
  end

  def handle_event({:key, key}, state) when key in [:enter, :" "],
    do: select_at(state, state.highlighted_index)

  def handle_event({:mouse, %{type: :mouse_up, y: y}}, state) do
    actual_index = state.scroll_offset + y

    if actual_index >= 0 and actual_index < length(state.options) do
      select_at(%{state | highlighted_index: actual_index}, actual_index)
    else
      {:noreply, state}
    end
  end

  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}
  def handle_event(_, state), do: {:noreply, state}

  @doc """
  The number of rows the element asks for.

  Returns `opts[:height]` when given, otherwise the length of the positional
  options list capped at `5` — which is `0` when the options were passed under
  `opts[:options]` instead.

      iex> Drafter.Widget.SelectionList.preferred_height(["a", "b"], [])
      2

      iex> Drafter.Widget.SelectionList.preferred_height(Enum.to_list(1..20), [])
      5

      iex> Drafter.Widget.SelectionList.preferred_height(nil, options: ["a"])
      0
  """
  @spec preferred_height(list() | nil, keyword()) :: non_neg_integer()
  def preferred_height(args, opts), do: Keyword.get(opts, :height, min(length(args || []), 5))

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.SelectionList.component_tag()
      :selection_list
  """
  @spec component_tag() :: :selection_list
  def component_tag, do: :selection_list

  @doc """
  Builds the props map for a `{:selection_list, options, opts}` element.

  `options` is used when it is a non-empty list, otherwise `opts[:options]`,
  defaulting to `[]`. `:on_change` and `:on_item_toggle` go through
  `Drafter.Widget.Callback.wrap_1/1` and `wrap_2/1`, so an atom becomes a closure
  that dispatches an app event. `:visible_height` falls back to the height of
  `opts[:__rect__]`, itself defaulting to `%{width: 40, height: 10}`. The emitted
  `:classes` key is not read by `mount/1`.

      iex> props = Drafter.Widget.SelectionList.from_component_opts([{"a", :a}], selected: [:a])
      iex> {props.options, props.selected, props.selection_mode, props.visible_height}
      {[{"a", :a}], [:a], :multiple, 10}

      iex> props = Drafter.Widget.SelectionList.from_component_opts(["a"], on_change: :picked)
      iex> is_function(props.on_change, 1)
      true
  """
  @spec from_component_opts(list() | nil, keyword()) :: Drafter.Widget.props()
  def from_component_opts(options, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 10})
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    all_options =
      if is_list(options) and options != [], do: options, else: Keyword.get(opts, :options, [])

    %{
      options: all_options,
      selected: Keyword.get(opts, :selected, []),
      selection_mode: Keyword.get(opts, :selection_mode, :multiple),
      on_change: Callback.wrap_1(Keyword.get(opts, :on_change)),
      on_item_toggle: Callback.wrap_2(Keyword.get(opts, :on_item_toggle)),
      visible_height: Keyword.get(opts, :visible_height, rect.height),
      classes: classes
    }
  end

  @doc """
  Narrows a re-render to `:on_change`, `:on_item_toggle`, `:selection_mode` and
  `:classes`.

  `:options`, `:selected` and `:visible_height` are dropped, so they are
  mount-only through the component tree and the user's selection survives a
  re-render.

      iex> props = Drafter.Widget.SelectionList.from_component_opts(["a"], [])
      iex> Drafter.Widget.SelectionList.update_props_from_mount(props, %{}, []) |> Map.keys() |> Enum.sort()
      [:classes, :on_change, :on_item_toggle, :selection_mode]
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      on_change: mount_props.on_change,
      on_item_toggle: mount_props.on_item_toggle,
      selection_mode: mount_props.selection_mode,
      classes: mount_props.classes
    }
  end

  defp select_at(state, index) do
    case state.selection_mode do
      :single ->
        new_selected = MapSet.new([index])
        new_state = %{state | selected_indices: new_selected}
        trigger_change(new_state)
        trigger_item_toggle(new_state, index, true)
        {:ok, new_state}

      :multiple ->
        was_selected = MapSet.member?(state.selected_indices, index)

        new_selected =
          if was_selected do
            MapSet.delete(state.selected_indices, index)
          else
            MapSet.put(state.selected_indices, index)
          end

        new_state = %{state | selected_indices: new_selected}
        trigger_change(new_state)
        trigger_item_toggle(new_state, index, not was_selected)
        {:ok, new_state}

      _ ->
        new_selected = MapSet.new([index])
        new_state = %{state | selected_indices: new_selected}
        trigger_change(new_state)
        trigger_item_toggle(new_state, index, true)
        {:ok, new_state}
    end
  end

  defp ensure_visible(state) do
    cond do
      state.highlighted_index < state.scroll_offset ->
        %{state | scroll_offset: state.highlighted_index}

      state.highlighted_index >= state.scroll_offset + state.visible_height ->
        %{state | scroll_offset: state.highlighted_index - state.visible_height + 1}

      true ->
        state
    end
  end

  defp normalize_options(options) do
    Enum.map(options, fn
      %{id: _id, label: _label} = opt -> opt
      {label, id} -> %{id: id, label: to_string(label)}
      label when is_binary(label) -> %{id: label, label: label}
    end)
  end

  defp render_option(state, option, index, width) do
    is_selected = MapSet.member?(state.selected_indices, index)
    is_highlighted = index == state.highlighted_index && state.focused

    item_state = %{
      selected: is_selected,
      focused: is_highlighted
    }

    computed = Computed.for_part(:selection_list, item_state, :item)
    text_style = Computed.to_segment_style(computed)

    checkbox_state = %{selected: is_selected}
    checkbox_computed = Computed.for_part(:selection_list, checkbox_state, :checkbox)
    box_style = Computed.to_segment_style(checkbox_computed)

    bg_computed = Computed.for_part(:selection_list, %{}, :item)
    bg_style = Computed.to_segment_style(bg_computed)

    {open_char, check_char, close_char} =
      case state.selection_mode do
        :single ->
          if is_selected, do: {"(", "●", ")"}, else: {"(", " ", ")"}

        _ ->
          if is_selected, do: {"[", "X", "]"}, else: {"[", " ", "]"}
      end

    text = " " <> option.label
    text_len = String.length(text) + 4
    remaining = max(0, width - text_len)

    Strip.new([
      Segment.new(" ", text_style),
      Segment.new(open_char, box_style),
      Segment.new(check_char, box_style),
      Segment.new(close_char, box_style),
      Segment.new(text, text_style),
      Segment.new(String.duplicate(" ", remaining), bg_style)
    ])
  end

  defp trigger_item_toggle(%{on_item_toggle: callback}, index, new_selected_state)
       when is_function(callback, 2) do
    callback.(index, new_selected_state)
  rescue
    _error -> :ok
  end

  defp trigger_item_toggle(_state, _index, _new_selected_state), do: :ok

  defp trigger_change(state) do
    if state.on_change do
      selected_ids =
        state.options
        |> Enum.with_index()
        |> Enum.filter(fn {_opt, idx} -> MapSet.member?(state.selected_indices, idx) end)
        |> Enum.map(fn {opt, _idx} -> opt.id end)

      try do
        state.on_change.(selected_ids)
      rescue
        _error -> :ok
      end
    end
  end
end
