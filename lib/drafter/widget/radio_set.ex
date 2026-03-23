defmodule Drafter.Widget.RadioSet do
  @moduledoc """
  A mutually exclusive radio button group where exactly one option can be selected at a time.

  Options are rendered as a vertical list of `○` (unselected) and `●` (selected) indicators
  with labels. Arrow keys move the highlighted cursor; Enter or Space confirms the selection.
  Mouse clicks select the clicked option immediately.

  ## Options

    * `:options` - list of options in any of these formats:
        * `"label"` — string used as both ID and label
        * `{"label", id}` — tuple with a display label and an identifier
        * `%{id: id, label: label}` — map with explicit fields
    * `:selected` - ID of the initially selected option
    * `:on_change` - `(id -> term())` called with the selected option's ID on change
    * `:visible_height` - number of rows allocated for the list (default: number of options)

  ## Usage

      radio_set(
        options: [{"Light", :light}, {"Dark", :dark}, {"System", :system}],
        selected: :dark,
        on_change: fn theme -> IO.inspect(theme) end
      )
  """

  use Drafter.Widget,
    handles: [:keyboard],
    focusable: true

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
    cols: 1
  ]

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
      cols: Map.get(props, :cols, 1)
    }
  end

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
    cols = state.cols
    col_width = div(rect.width, cols)
    row_count = ceil(length(state.options) / cols)
    bg_style = Computed.to_segment_style(computed)

    Enum.map(0..(row_count - 1), fn row ->
      segments = Enum.flat_map(0..(cols - 1), &render_column_cell(state, &1, row, row_count, col_width, bg_style))
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

  def handle_event({:key, :up}, state), do: {:ok, %{state | highlighted_index: max(0, state.highlighted_index - 1)}}
  def handle_event({:key, :down}, state), do: {:ok, %{state | highlighted_index: min(length(state.options) - 1, state.highlighted_index + 1)}}
  def handle_event({:key, key}, state) when key in [:enter, :" "], do: select_current(state)

  def handle_event({:mouse, %{type: :mouse_up, y: y}}, state) do
    if y >= 0 and y < length(state.options) do
      new_state = %{state | selected_index: y, highlighted_index: y}
      trigger_change(new_state)
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}
  def handle_event(_, state), do: {:noreply, state}

  def preferred_height(args, opts), do: Keyword.get(opts, :height, length(args || []))

  def component_tag, do: :radio_set

  def from_component_opts(options, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 40, height: 10})
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

    classes =
      Enum.map(raw_classes, fn
        c when is_binary(c) -> String.to_atom(c)
        c when is_atom(c) -> c
      end)

    all_options =
      if is_list(options) and options != [], do: options, else: Keyword.get(opts, :options, [])

    selected = Drafter.Binding.get_bound_value(opts, app_state, Keyword.get(opts, :selected))

    %{
      options: all_options,
      selected: selected,
      on_change: Drafter.Binding.create_bound_callback(opts, :selected),
      visible_height: Keyword.get(opts, :visible_height, rect.height),
      cols: Keyword.get(opts, :cols, 1),
      classes: classes
    }
  end

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
