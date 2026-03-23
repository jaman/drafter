defmodule Drafter.Widget.SelectionList do
  @moduledoc """
  A scrollable list widget that supports single or multiple item selection with checkbox-style indicators.

  In `:multiple` mode each item renders a `[X]` checkbox. In `:single` mode items render
  as `(●)` radio indicators. The `:on_change` callback receives a list of currently selected
  IDs after every selection change.

  ## Options

    * `:options` - list of options in any of these formats:
        * `"label"` — string used as both ID and label
        * `{"label", id}` — tuple with a display label and an identifier
        * `%{id: id, label: label}` — map with explicit fields
    * `:selected` - list of IDs that are initially selected (default: `[]`)
    * `:selection_mode` - `:multiple` (default) or `:single`
    * `:on_change` - `([id] -> term())` called with the full list of selected IDs on change
    * `:visible_height` - number of rows allocated for the list (default: number of options)

  ## Key bindings

    * `↑` / `↓` — move the cursor
    * `Space` / `Enter` — toggle selection of the highlighted item
    * Mouse click — moves cursor and toggles the clicked item

  ## Usage

      selection_list(
        options: [{"Elixir", :ex}, {"Erlang", :erl}, {"Gleam", :gleam}],
        selected: [:ex],
        selection_mode: :multiple,
        on_change: fn ids -> IO.inspect(ids) end
      )
  """

  use Drafter.Widget,
    handles: [:keyboard, :char],
    focusable: true

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

  def handle_event({:key, :up}, state) do
    {:ok, %{state | highlighted_index: max(0, state.highlighted_index - 1)} |> ensure_visible()}
  end

  def handle_event({:key, :down}, state) do
    {:ok, %{state | highlighted_index: min(length(state.options) - 1, state.highlighted_index + 1)} |> ensure_visible()}
  end

  def handle_event({:key, :home}, state), do: {:ok, %{state | highlighted_index: 0, scroll_offset: 0}}

  def handle_event({:key, :end}, state) do
    {:ok, %{state | highlighted_index: length(state.options) - 1} |> ensure_visible()}
  end

  def handle_event({:char, 1}, %{selection_mode: :multiple} = state) do
    all_indices = MapSet.new(0..(length(state.options) - 1))
    new_selected = if MapSet.equal?(state.selected_indices, all_indices), do: MapSet.new(), else: all_indices
    new_state = %{state | selected_indices: new_selected}
    trigger_change(new_state)
    {:ok, new_state}
  end

  def handle_event({:key, key}, state) when key in [:enter, :" "], do: select_at(state, state.highlighted_index)

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

  def preferred_height(args, opts), do: Keyword.get(opts, :height, min(length(args || []), 5))

  def component_tag, do: :selection_list

  def from_component_opts(options, opts) do
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
