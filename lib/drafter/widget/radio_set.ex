defmodule Drafter.Widget.RadioSet do
  @moduledoc """
  A mutually exclusive radio button group where exactly one option can be selected at a time.

  Options are rendered as a vertical list of `○` (unselected) and `●` (selected) indicators
  with labels. Arrow keys move the highlighted cursor; Enter or Space confirms the selection.
  Mouse clicks select the clicked option immediately.

  ## Component tag

  Tag `:radio_set`, built by `Drafter.App` as `{:radio_set, options, opts}`:

      radio_set(options, opts)

  The positional `options` list is used when non-empty, falling back to
  `opts[:options]`. `:selected` and `:on_change` go through the binding layer, so
  passing `bind: :some_key` reads the current selection from that app-state key
  and writes the new one back on change. `:visible_height` and `:width` default
  to the rect the parent allocated, and a `:width` given in `opts` is ignored.

  ## Options

    * `:options` - list of options in any of these formats. Default `[]`. Anything
      else raises `FunctionClauseError` from `mount/1`.
        * `"label"` — string used as both ID and label
        * `{"label", id}` — tuple with a display label and an identifier
        * `%{id: id, label: label}` — map with explicit fields
    * `:selected` - ID of the initially selected option. Default `nil`. An ID that
      is `nil` or matches no option selects index `0`, even when there are no
      options at all.
    * `:bind` - app-state key atom for two-way binding of the selection.
      Default: none.
    * `:on_change` - `(id -> term())` called with the selected option's ID whenever
      the selection changes. Default `nil`. An exception it raises is swallowed.
    * `:visible_height` - `t:non_neg_integer/0` rows allocated for the list.
      Default: the number of options when mounting directly, and the height of
      `opts[:__rect__]` through the element. Held on the state; `render/2` uses the
      rect it is given instead.
    * `:cols` - `t:pos_integer/0` columns the options are laid out across. Default
      `1`. Options fill column-major. Mount-only.
    * `:width` - `t:non_neg_integer/0` total width, used to resolve which column a
      click landed in. Default `0` when mounting directly. Through the element it
      always comes from the allocated rect and a `:width` in `opts` is ignored;
      `on_rect_change/2` keeps it current.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`.

  `update/2` applies `:options`, `:selected`, `:on_change` and `:visible_height`
  and drops every other key, so `:cols`, `:width` and `:focused` are mount-only.
  Through the component tree `update_props_from_mount/3` narrows that to
  `:options` and `:on_change`, plus `:selected` only when `:bind` is set.

  ## Key bindings

    * `up` / `down` - move the highlight; bubbles at either end
    * `enter`, `space` - select the highlighted option

  A mouse up selects the option under the pointer immediately.

  ## Widget value

  `Drafter.get_widget_value/1` returns the ID of the selected option, or `nil` when
  the index lands outside the list.

  ## Usage

      radio_set(
        options: [{"Light", :light}, {"Dark", :dark}, {"System", :system}],
        selected: :dark,
        on_change: fn theme -> IO.inspect(theme) end
      )
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard]

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :options,
    :selected_index,
    :highlighted_index,
    :focused,
    :on_change,
    :visible_height,
    cols: 1,
    width: 0
  ]

  @type option :: %{id: term(), label: String.t()}

  @type t :: %__MODULE__{
          options: [option()],
          selected_index: non_neg_integer(),
          highlighted_index: non_neg_integer(),
          focused: boolean(),
          on_change: (term() -> term()) | nil,
          visible_height: non_neg_integer(),
          cols: pos_integer(),
          width: non_neg_integer()
        }

  @doc """
  Builds the widget state from `props`.

  Options are normalised into `%{id: id, label: label}` maps. `:selected_index` and
  `:highlighted_index` both start at the index of `:selected`, or at `0` when it is
  `nil` or matches nothing.

      iex> state = Drafter.Widget.RadioSet.mount(%{options: ["Light", "Dark"]})
      iex> state.options
      [%{id: "Light", label: "Light"}, %{id: "Dark", label: "Dark"}]

      iex> options = [{"Light", :light}, {"Dark", :dark}]
      iex> state = Drafter.Widget.RadioSet.mount(%{options: options, selected: :dark})
      iex> {state.selected_index, state.highlighted_index, state.visible_height}
      {1, 1, 2}

      iex> options = [{"Light", :light}]
      iex> state = Drafter.Widget.RadioSet.mount(%{options: options, selected: :nope})
      iex> state.selected_index
      0
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    options = Map.get(props, :options, [])
    selected = Map.get(props, :selected)

    selected_index = find_selected_index(options, selected)

    normalized = normalize_options(options)

    %__MODULE__{
      options: normalized,
      selected_index: selected_index,
      highlighted_index: selected_index,
      focused: Map.get(props, :focused, false),
      on_change: Map.get(props, :on_change),
      visible_height: Map.get(props, :visible_height, length(options)),
      cols: Map.get(props, :cols, 1),
      width: Map.get(props, :width, 0)
    }
  end

  @doc false
  @spec on_rect_change(Drafter.Widget.rect(), t()) :: t()
  def on_rect_change(rect, state), do: %{state | width: rect.width}

  @doc """
  Draws the option list into `rect`, always returning exactly `rect.height` strips.

  With `:cols` at `1` the options run down the rect, capped at `rect.height`, and
  the remaining rows are blank. With more columns the options fill column-major
  over `ceil(count / cols)` rows, each column `div(rect.width, cols)` wide. The
  highlight is only drawn while the widget is focused.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    computed = Computed.for_widget(:radio_set, state)
    bg_style = Computed.to_segment_style(computed)
    empty_line = Segment.new(String.duplicate(" ", rect.width), bg_style)
    empty_strip = Strip.new([empty_line])

    strips =
      if state.cols > 1 do
        render_columns(state, rect, computed)
      else
        visible = Enum.take(state.options, rect.height)

        visible
        |> Enum.with_index()
        |> Enum.map(fn {option, index} -> render_option(state, option, index, rect.width) end)
      end

    current_height = length(strips)

    if current_height < rect.height do
      strips ++ List.duplicate(empty_strip, rect.height - current_height)
    else
      strips
    end
  end

  defp render_columns(state, rect, computed) do
    cols = max(state.cols, 1)
    col_width = div(rect.width, cols)
    row_count = rows_per_column(length(state.options), cols)
    bg_style = Computed.to_segment_style(computed)

    Enum.map(0..(row_count - 1)//1, fn row ->
      segments =
        Enum.flat_map(
          0..(cols - 1)//1,
          &render_column_cell(state, &1, row, row_count, col_width, bg_style)
        )

      Strip.new(segments)
    end)
  end

  defp render_column_cell(state, col, row, row_count, col_width, bg_style) do
    index = col * row_count + row

    case Enum.at(state.options, index) do
      nil -> [Segment.new(String.duplicate(" ", col_width), bg_style)]
      option -> render_option(state, option, index, col_width).segments
    end
  end

  @doc """
  Folds `:options`, `:selected`, `:on_change` and `:visible_height` into `state`
  and drops every other key.

  New `:options` are normalised. A `:selected` that matches no option keeps the
  current index; new options without a `:selected` clamp the index to the last
  option. `:highlighted_index` follows `:selected_index` only when that index
  actually moved.

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}]})
      iex> updated = Drafter.Widget.RadioSet.update(%{selected: :b}, state)
      iex> {updated.selected_index, updated.highlighted_index}
      {1, 1}

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}]})
      iex> Drafter.Widget.RadioSet.update(%{selected: :missing}, state).selected_index
      0

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}], selected: :b})
      iex> Drafter.Widget.RadioSet.update(%{options: [{"a", :a}]}, state).selected_index
      0
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    raw_options = Map.get(props, :options)
    new_options = if raw_options, do: normalize_options(raw_options), else: state.options

    new_selected_index =
      cond do
        Map.has_key?(props, :selected) ->
          selected = props.selected

          Enum.find_index(new_options, fn %{id: id} -> id == selected end) ||
            state.selected_index

        raw_options ->
          min(state.selected_index, length(new_options) - 1)

        true ->
          state.selected_index
      end

    new_highlighted_index =
      if new_selected_index != state.selected_index,
        do: new_selected_index,
        else: state.highlighted_index

    %{
      state
      | options: new_options,
        selected_index: new_selected_index,
        highlighted_index: new_highlighted_index,
        on_change: Map.get(props, :on_change, state.on_change),
        visible_height: Map.get(props, :visible_height, state.visible_height)
    }
  end

  @doc """
  Handles the radio set's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  Recognised events:

    * `{:key, :up}` / `{:key, :down}` - move `:highlighted_index`, returning
      `{:bubble, state}` unchanged at the first and last option
    * `{:key, :enter}` / `{:key, :" "}` - set `:selected_index` from the highlight
      and call `:on_change`
    * `{:mouse, %{type: :mouse_up, x: x, y: y}}` - select the option at those
      coordinates and call `:on_change`, or `{:noreply, state}` when the click
      misses every option
    * `{:focus}` / `{:blur}` - set or clear `:focused`

  Every other event returns `{:noreply, state}`.

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}]})
      iex> {:ok, moved} = Drafter.Widget.RadioSet.handle_event({:key, :down}, state)
      iex> {moved.highlighted_index, moved.selected_index}
      {1, 0}

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}]})
      iex> Drafter.Widget.RadioSet.handle_event({:key, :up}, state) == {:bubble, state}
      true

      iex> state = Drafter.Widget.RadioSet.mount(%{options: [{"a", :a}, {"b", :b}]})
      iex> {:ok, moved} = Drafter.Widget.RadioSet.handle_event({:key, :down}, state)
      iex> {:ok, chosen} = Drafter.Widget.RadioSet.handle_event({:key, :enter}, moved)
      iex> chosen.selected_index
      1
  """
  @spec handle_event(term(), t()) :: {:ok, t()} | {:bubble, t()} | {:noreply, t()}
  def handle_event({:key, :up}, %{highlighted_index: 0} = state), do: {:bubble, state}

  def handle_event({:key, :up}, state) do
    {:ok, %{state | highlighted_index: state.highlighted_index - 1}}
  end

  def handle_event({:key, :down}, state) do
    max_index = length(state.options) - 1

    if state.highlighted_index >= max_index do
      {:bubble, state}
    else
      {:ok, %{state | highlighted_index: state.highlighted_index + 1}}
    end
  end

  def handle_event({:key, key}, state) when key in [:enter, :" "], do: select_current(state)

  def handle_event({:mouse, %{type: :mouse_up} = event}, state) do
    case option_index_at(state, Map.get(event, :x, 0), Map.get(event, :y, 0)) do
      nil ->
        {:noreply, state}

      index ->
        new_state = %{state | selected_index: index, highlighted_index: index}
        trigger_change(new_state)
        {:ok, new_state}
    end
  end

  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}
  def handle_event(_, state), do: {:noreply, state}

  @doc """
  The index of the option at the given coordinates, or `nil` where the layout
  has no option.

  Options fill column-major — the first column top to bottom, then the next — so
  both `x` and `y` are used to resolve the index when `:cols` exceeds one. With a
  single column `x` only has to be non-negative.

      iex> state = Drafter.Widget.RadioSet.mount(%{options: ["a", "b", "c"]})
      iex> {Drafter.Widget.RadioSet.option_index_at(state, 0, 1), Drafter.Widget.RadioSet.option_index_at(state, 0, 3)}
      {1, nil}

      iex> state = Drafter.Widget.RadioSet.mount(%{options: ["a", "b", "c", "d"], cols: 2, width: 40})
      iex> {Drafter.Widget.RadioSet.option_index_at(state, 25, 1), Drafter.Widget.RadioSet.option_index_at(state, 0, 1)}
      {3, 1}
  """
  @spec option_index_at(t(), integer(), integer()) :: non_neg_integer() | nil
  def option_index_at(state, x, y) do
    cols = max(state.cols, 1)
    rows = rows_per_column(length(state.options), cols)

    if y < 0 or y >= rows or x < 0 do
      nil
    else
      index = column_at(state, x, cols) * rows + y
      if index < length(state.options), do: index, else: nil
    end
  end

  defp column_at(_state, _x, 1), do: 0

  defp column_at(state, x, cols) do
    col_width = max(div(state.width, cols), 1)
    min(div(x, col_width), cols - 1)
  end

  defp rows_per_column(0, _cols), do: 0
  defp rows_per_column(count, cols), do: ceil(count / cols)

  @doc """
  The number of rows the element asks for.

  Returns `opts[:height]` when given, otherwise the length of the positional
  options list — which is `0` when the options were passed under `opts[:options]`
  instead.

      iex> Drafter.Widget.RadioSet.preferred_height(["a", "b"], [])
      2

      iex> Drafter.Widget.RadioSet.preferred_height(nil, options: ["a", "b"])
      0

      iex> Drafter.Widget.RadioSet.preferred_height(nil, height: 5)
      5
  """
  @spec preferred_height(list() | nil, keyword()) :: non_neg_integer()
  def preferred_height(args, opts), do: Keyword.get(opts, :height, length(args || []))

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.RadioSet.component_tag()
      :radio_set
  """
  @spec component_tag() :: :radio_set
  def component_tag, do: :radio_set

  @doc """
  Builds the props map for a `{:radio_set, options, opts}` element.

  `options` is used when it is a non-empty list, otherwise `opts[:options]`,
  defaulting to `[]`. `:selected` comes from the bound value
  and `:on_change` is the binding's writer. `:visible_height` falls back to the
  height of `opts[:__rect__]` and `:width` always comes from its width, ignoring
  any `:width` in `opts`; the rect itself defaults to `%{width: 40, height: 10}`.
  The emitted `:classes` key is not read by `mount/1`.

      iex> props = Drafter.Widget.RadioSet.from_component_opts([{"a", :a}], selected: :a)
      iex> {props.options, props.selected, props.visible_height, props.width, props.cols}
      {[{"a", :a}], :a, 10, 40, 1}

      iex> opts = [bind: :theme, __app_state__: %{theme: :dark}, options: [{"Dark", :dark}]]
      iex> Drafter.Widget.RadioSet.from_component_opts(nil, opts).selected
      :dark
  """
  @spec from_component_opts(list() | nil, keyword()) :: Drafter.Widget.props()
  def from_component_opts(options, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 10})
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    all_options =
      if is_list(options) and options != [], do: options, else: Keyword.get(opts, :options, [])

    selected = Drafter.Binding.get_bound_value(opts, app_state, Keyword.get(opts, :selected))

    %{
      options: all_options,
      selected: selected,
      on_change: Drafter.Binding.create_bound_callback(opts, :selected),
      visible_height: Keyword.get(opts, :visible_height, rect.height),
      cols: Keyword.get(opts, :cols, 1),
      width: rect.width,
      classes: classes
    }
  end

  @doc """
  Narrows a re-render to `:options`, `:on_change` and `:classes`, adding
  `:selected` only when `opts` carries `:bind`.

  `:visible_height`, `:cols` and `:width` are dropped, so they are mount-only
  through the component tree, and an unbound radio set keeps whatever the user
  selected.

      iex> props = Drafter.Widget.RadioSet.from_component_opts([{"a", :a}], [])
      iex> Drafter.Widget.RadioSet.update_props_from_mount(props, %{}, []) |> Map.keys() |> Enum.sort()
      [:classes, :on_change, :options]

      iex> opts = [bind: :theme, __app_state__: %{theme: :dark}]
      iex> props = Drafter.Widget.RadioSet.from_component_opts([{"Dark", :dark}], opts)
      iex> Drafter.Widget.RadioSet.update_props_from_mount(props, %{}, opts).selected
      :dark
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, opts) do
    base = %{
      options: mount_props.options,
      on_change: mount_props.on_change,
      classes: mount_props.classes
    }

    if Drafter.Binding.has_binding?(opts) do
      Map.put(base, :selected, mount_props.selected)
    else
      base
    end
  end

  defp select_current(state) do
    new_state = %{state | selected_index: state.highlighted_index}
    trigger_change(new_state)
    {:ok, new_state}
  end

  defp find_selected_index(_options, nil), do: 0

  defp find_selected_index(options, selected) do
    Enum.find_index(options, fn
      %{id: id} -> id == selected
      {_label, id} -> id == selected
      label when is_binary(label) -> label == selected
    end) || 0
  end

  defp normalize_options(options) do
    Enum.map(options, fn
      %{id: _id, label: _label} = opt -> opt
      {label, id} -> %{id: id, label: to_string(label)}
      label when is_binary(label) -> %{id: label, label: label}
    end)
  end

  defp render_option(state, option, index, width) do
    is_selected = index == state.selected_index
    is_highlighted = index == state.highlighted_index && state.focused

    radio_char =
      if is_selected,
        do: CharacterSet.indicator(:radio_on),
        else: CharacterSet.indicator(:radio_off)

    option_state = %{
      selected: is_selected,
      focused: is_highlighted
    }

    computed = Computed.for_part(:radio_set, option_state, :option)
    text_style = Computed.to_segment_style(computed)

    radio_computed = Computed.for_part(:radio_set, option_state, :radio)
    radio_style = Computed.to_segment_style(radio_computed)

    bg_computed = Computed.for_part(:radio_set, %{}, :option)
    bg_style = Computed.to_segment_style(bg_computed)

    text = " " <> option.label
    indicator_len = String.length(radio_char)
    text_len = 1 + indicator_len + String.length(text)
    remaining = max(0, width - text_len)

    Strip.new([
      Segment.new(" ", text_style),
      Segment.new(radio_char, radio_style),
      Segment.new(text, text_style),
      Segment.new(String.duplicate(" ", remaining), bg_style)
    ])
  end

  defp trigger_change(state) do
    if state.on_change do
      option = Enum.at(state.options, state.selected_index)

      try do
        state.on_change.(option.id)
      rescue
        _error -> :ok
      end
    end
  end
end
