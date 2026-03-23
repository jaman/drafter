defmodule Drafter.Widget.TabbedContent do
  @moduledoc """
  Renders a bordered tabbed panel where each tab displays independent content.

  Tabs are switched with `←`/`→` or by clicking the tab label. The active tab
  label is wrapped in `[brackets]`; hovered tabs are highlighted. Tab content
  can be a list of strings, a single `{:label, text}` tuple, or an
  `{:option_list, items, opts}` tuple that embeds a fully interactive
  `OptionList` widget inside the tab body.

  An optional `:title` string is rendered in the top border, aligned according
  to `:title_align`.

  ## Options

    * `:tabs` - list of tab descriptors; each may be a string label, `{label, content}` tuple, or a map with `:id`, `:label`, and `:content` keys
    * `:active_tab` - zero-based index of the initially active tab (default `0`)
    * `:title` - string shown in the top border (optional)
    * `:title_align` - title alignment: `:left`, `:center` (default), `:right`
    * `:width` - explicit width in columns; defaults to the available rect width
    * `:on_tab_change` - callback atom dispatched with the tab's `:id` when the active tab changes
    * `:on_item_select` - callback atom dispatched with the selected item when `Enter` is pressed on a string-content tab

  ## Usage

      tabbed_content(tabs: [
        %{id: :overview, label: "Overview", content: ["Line 1", "Line 2"]},
        %{id: :details,  label: "Details",  content: ["More info"]}
      ])

      tabbed_content(
        tabs: [{"Files", {:option_list, file_list, on_select: :file_selected}}],
        title: "Browser"
      )
  """

  use Drafter.Widget,
    handles: [:keyboard],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  defstruct [
    :tabs,
    :active_tab,
    :hovered_tab,
    :highlighted_item,
    :focused,
    :on_tab_change,
    :on_item_select,
    :title,
    :title_align,
    :width,
    :child_widgets
  ]

  def mount(props) do
    tabs = Map.get(props, :tabs, [])

    normalized_tabs = normalize_tabs(tabs)
    child_widgets = mount_child_widgets(normalized_tabs)

    %__MODULE__{
      tabs: normalized_tabs,
      active_tab: Map.get(props, :active_tab, 0),
      hovered_tab: nil,
      highlighted_item: 0,
      focused: Map.get(props, :focused, false),
      on_tab_change: Map.get(props, :on_tab_change),
      on_item_select: Map.get(props, :on_item_select),
      title: Map.get(props, :title),
      title_align: Map.get(props, :title_align, :left),
      width: Map.get(props, :width),
      child_widgets: child_widgets
    }
  end

  def render(state, rect) do
    border_computed = Computed.for_part(:tabbed_content, %{}, :border)
    border_style = Computed.to_segment_style(border_computed)

    content_computed = Computed.for_part(:tabbed_content, %{}, :content)
    bg_style = Computed.to_segment_style(content_computed)

    width = state.width || rect.width

    strips = []

    title_line = render_title_line(state, width)
    strips = strips ++ [title_line]

    tab_bar = render_tab_bar(state, width)
    strips = strips ++ [tab_bar]

    separator = "├" <> String.duplicate("─", width - 2) <> "┤"
    strips = strips ++ [Strip.new([Segment.new(separator, border_style)])]

    active_tab = Enum.at(state.tabs, state.active_tab)
    content_lines = if active_tab, do: active_tab.content, else: []

    content_height = rect.height - length(strips) - 1

    content_strips =
      render_content(
        state,
        active_tab,
        content_lines,
        width,
        content_height,
        border_style,
        bg_style
      )

    strips = strips ++ content_strips

    current_height = length(strips)
    remaining = rect.height - current_height - 1

    strips =
      if remaining > 0 do
        empty_strip =
          Strip.new([
            Segment.new("│ ", border_style),
            Segment.new(String.duplicate(" ", width - 4), bg_style),
            Segment.new(" │", border_style)
          ])

        padding = List.duplicate(empty_strip, remaining)
        strips ++ padding
      else
        strips
      end

    bottom_border = "╰" <> String.duplicate("─", width - 2) <> "╯"
    bottom_strip = Strip.new([Segment.new(bottom_border, border_style)])

    Enum.take(strips, rect.height - 1) ++ [bottom_strip]
  end

  def update(props, state) do
    new_active = Map.get(props, :active_tab, state.active_tab)
    new_tabs = normalize_tabs(Map.get(props, :tabs, state.tabs))

    highlighted =
      if new_active != state.active_tab do
        0
      else
        state.highlighted_item
      end

    new_child_widgets =
      if length(new_tabs) != length(state.tabs) do
        mount_child_widgets(new_tabs)
      else
        state.child_widgets
      end

    %{
      state
      | tabs: new_tabs,
        active_tab: new_active,
        highlighted_item: highlighted,
        on_tab_change: Map.get(props, :on_tab_change, state.on_tab_change),
        on_item_select: Map.get(props, :on_item_select, state.on_item_select),
        title: Map.get(props, :title, state.title),
        title_align: Map.get(props, :title_align, state.title_align),
        width: Map.get(props, :width, state.width),
        child_widgets: new_child_widgets
    }
  end

  def handle_event({:key, :left}, state) when state.active_tab > 0,
    do: change_tab(state, state.active_tab - 1)

  def handle_event({:key, :left}, state), do: {:noreply, state}

  def handle_event({:key, :right}, state) do
    max_tab = length(state.tabs) - 1

    if state.active_tab < max_tab do
      change_tab(state, state.active_tab + 1)
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :up}, state) do
    active_child = Enum.at(state.child_widgets, state.active_tab)
    handle_vertical_key(state, active_child, {:key, :up}, :up)
  end

  def handle_event({:key, :down}, state) do
    active_child = Enum.at(state.child_widgets, state.active_tab)
    handle_vertical_key(state, active_child, {:key, :down}, :down)
  end

  def handle_event({:key, :enter}, state) do
    active_child = Enum.at(state.child_widgets, state.active_tab)
    handle_enter_key(state, active_child)
  end

  def handle_event({:key, :tab}, state), do: {:noreply, state}

  def handle_event({:mouse, %{type: :mouse_up, y: y, x: x}}, state) when y <= 1 do
    case find_tab_at_x(state, x) do
      nil -> {:ok, %{state | focused: true}}
      clicked_tab -> change_tab(%{state | focused: true}, clicked_tab)
    end
  end

  def handle_event({:mouse, %{type: :mouse_up, y: y, x: x}}, state) when y >= 3 do
    active_child = Enum.at(state.child_widgets, state.active_tab)
    handle_content_click(state, active_child, y, x)
  end

  def handle_event({:mouse, %{type: :mouse_up}}, state), do: {:ok, %{state | focused: true}}

  def handle_event({:mouse, %{type: :move, y: y, x: x}}, state) when y <= 1 do
    {:ok, %{state | hovered_tab: find_tab_at_x(state, x)}}
  end

  def handle_event({:mouse, %{type: :move}}, state), do: {:ok, %{state | hovered_tab: nil}}

  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}

  def handle_event({:blur}, state), do: {:ok, %{state | focused: false, hovered_tab: nil}}

  def handle_event(_event, state), do: {:noreply, state}

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 8)

  def component_tag, do: :tabbed_content

  def from_component_opts(tabs, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80})
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

    classes =
      Enum.map(raw_classes, fn
        c when is_binary(c) -> String.to_atom(c)
        c when is_atom(c) -> c
      end)

    all_tabs = if is_list(tabs) and tabs != [], do: tabs, else: Keyword.get(opts, :tabs, [])

    %{
      tabs: all_tabs,
      active_tab: Keyword.get(opts, :active_tab, 0),
      title: Keyword.get(opts, :title),
      title_align: Keyword.get(opts, :title_align, :left),
      on_tab_change: Callback.wrap_1(Keyword.get(opts, :on_tab_change)),
      width: Keyword.get(opts, :width, rect.width),
      classes: classes
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      tabs: mount_props.tabs,
      title_align: mount_props.title_align,
      width: mount_props.width,
      classes: mount_props.classes
    }
  end

  defp handle_vertical_key(state, nil, _event, :up) do
    {:ok, %{state | highlighted_item: max(0, state.highlighted_item - 1)}}
  end

  defp handle_vertical_key(state, nil, _event, :down) do
    active_tab = Enum.at(state.tabs, state.active_tab)
    max_item = if active_tab, do: max(0, length(active_tab.content) - 1), else: 0
    {:ok, %{state | highlighted_item: min(max_item, state.highlighted_item + 1)}}
  end

  defp handle_vertical_key(state, active_child, event, _dir) do
    dispatch_event_to_child(state, active_child, event, state.active_tab)
  end

  defp handle_enter_key(state, nil) do
    maybe_invoke_item_select(state)
    {:ok, state}
  end

  defp handle_enter_key(state, active_child) do
    dispatch_event_to_child(state, active_child, {:key, :enter}, state.active_tab)
  end

  defp maybe_invoke_item_select(%{on_item_select: nil}), do: :ok

  defp maybe_invoke_item_select(state) do
    active_tab = Enum.at(state.tabs, state.active_tab)
    item = if active_tab, do: Enum.at(active_tab.content, state.highlighted_item), else: nil

    if item do
      try do
        state.on_item_select.(item)
      rescue
        _ -> :ok
      end
    end
  end

  defp handle_content_click(state, nil, y, _x) do
    item_index = y - 3
    active_tab = Enum.at(state.tabs, state.active_tab)
    max_item = if active_tab, do: length(active_tab.content) - 1, else: 0

    if item_index >= 0 and item_index <= max_item do
      {:ok, %{state | highlighted_item: item_index, focused: true}}
    else
      {:ok, %{state | focused: true}}
    end
  end

  defp handle_content_click(state, active_child, y, x) do
    dispatch_event_to_child(
      state,
      active_child,
      {:mouse, %{type: :mouse_up, y: y - 3, x: x}},
      state.active_tab
    )
  end

  defp change_tab(state, new_tab) do
    new_state = %{state | active_tab: new_tab, highlighted_item: 0}

    if state.on_tab_change do
      tab = Enum.at(state.tabs, new_tab)

      try do
        case Drafter.ScreenManager.get_active_screen() do
          nil ->
            Drafter.AppRegistry.send_to_loop({:app_event, state.on_tab_change, tab.id})

          _screen ->
            send(self(), {:tui_event, {:app_callback, state.on_tab_change, tab.id}})
        end
      rescue
        _ -> :ok
      end
    end

    {:ok, new_state}
  end

  defp normalize_tabs(tabs) do
    Enum.map(tabs, fn
      %{id: _id, label: _label, content: content} = tab when is_tuple(content) ->
        %{tab | content: [content]}

      %{id: _id, label: _label, content: _content} = tab ->
        tab

      %{id: id, label: label} ->
        %{id: id, label: label, content: []}

      {label, content} when is_tuple(content) ->
        %{id: label, label: label, content: [content]}

      {label, content} when is_list(content) ->
        %{id: label, label: label, content: content}

      {label, content} when is_binary(content) ->
        %{id: label, label: label, content: [content]}

      label when is_binary(label) ->
        %{id: label, label: label, content: []}
    end)
  end

  defp render_title_line(state, width) do
    border_computed = Computed.for_part(:tabbed_content, %{}, :border)
    border_style = Computed.to_segment_style(border_computed)

    title_computed = Computed.for_part(:tabbed_content, %{}, :title)
    title_style = Computed.to_segment_style(title_computed)

    title = state.title || ""
    title_with_space = " " <> title <> " "
    title_len = String.length(title_with_space)

    remaining = width - 2 - title_len

    {left_dashes, right_dashes} =
      case state.title_align do
        :left ->
          {0, max(0, remaining)}

        :right ->
          {max(0, remaining), 0}

        _ ->
          left = max(0, div(remaining, 2))
          {left, max(0, remaining - left)}
      end

    Strip.new([
      Segment.new("╭", border_style),
      Segment.new(String.duplicate("─", left_dashes), border_style),
      Segment.new(title_with_space, title_style),
      Segment.new(String.duplicate("─", right_dashes), border_style),
      Segment.new("╮", border_style)
    ])
  end

  defp render_tab_bar(state, width) do
    border_computed = Computed.for_part(:tabbed_content, %{}, :border)
    border_style = Computed.to_segment_style(border_computed)

    content_computed = Computed.for_part(:tabbed_content, %{}, :content)
    bg_style = Computed.to_segment_style(content_computed)

    active_tab_computed = Computed.for_part(:tabbed_content, %{active: true}, :tab)
    active_style = Computed.to_segment_style(active_tab_computed)

    hover_tab_computed = Computed.for_part(:tabbed_content, %{hovered: true}, :tab)
    hover_style = Computed.to_segment_style(hover_tab_computed)

    inactive_tab_computed = Computed.for_part(:tabbed_content, %{}, :tab)
    inactive_style = Computed.to_segment_style(inactive_tab_computed)

    tab_segments =
      state.tabs
      |> Enum.with_index()
      |> Enum.flat_map(fn {tab, index} ->
        is_active = index == state.active_tab
        is_hovered = index == state.hovered_tab

        cond do
          is_active ->
            [
              Segment.new("[", border_style),
              Segment.new(" " <> tab.label <> " ", active_style),
              Segment.new("]", border_style)
            ]

          is_hovered ->
            [Segment.new(" " <> tab.label <> " ", hover_style)]

          true ->
            [Segment.new(" " <> tab.label <> " ", inactive_style)]
        end
      end)

    content_width =
      tab_segments
      |> Enum.map(fn seg -> String.length(seg.text) end)
      |> Enum.sum()

    padding_width = max(0, width - 2 - content_width)
    padding = Segment.new(String.duplicate(" ", padding_width), bg_style)

    all_segments =
      [Segment.new("│", border_style)] ++
        tab_segments ++ [padding, Segment.new("│", border_style)]

    Strip.new(all_segments)
  end

  defp find_tab_at_x(state, x) do
    {result, _} =
      Enum.reduce_while(state.tabs, {nil, 1}, fn tab, {_found, current_x} ->
        index = Enum.find_index(state.tabs, fn t -> t.id == tab.id end)
        is_active = index == state.active_tab

        label_width =
          if is_active do
            String.length(tab.label) + 4
          else
            String.length(tab.label) + 2
          end

        next_x = current_x + label_width

        if x >= current_x and x < next_x do
          {:halt, {index, next_x}}
        else
          {:cont, {nil, next_x}}
        end
      end)

    result
  end

  defp render_content(
         state,
         active_tab,
         content_lines,
         width,
         content_height,
         border_style,
         bg_style
       ) do
    if has_widgets?(content_lines) do
      render_widget_content(
        content_lines,
        width,
        content_height,
        border_style,
        bg_style,
        state.child_widgets,
        state.active_tab
      )
    else
      render_string_content(
        content_lines,
        width,
        content_height,
        border_style,
        bg_style,
        active_tab
      )
    end
  end

  defp has_widgets?(content_lines) do
    Enum.any?(content_lines, fn
      line when is_tuple(line) -> true
      _ -> false
    end)
  end

  defp render_widget_content(
         content_lines,
         width,
         content_height,
         border_style,
         bg_style,
         child_widgets,
         active_tab
       ) do
    active_child = Enum.at(child_widgets, active_tab)
    render_active_child(active_child, content_lines, width, content_height, border_style, bg_style)
  end

  defp render_active_child(nil, content_lines, width, content_height, border_style, bg_style) do
    case extract_label_content(content_lines) do
      nil -> render_layout_content(content_lines, width, content_height, border_style)
      label -> render_label_content(label, width, content_height, border_style, bg_style)
    end
  end

  defp render_active_child(active_child, _lines, width, content_height, border_style, _bg_style) do
    render_widget_with_state(active_child, width, content_height, border_style)
  end

  defp render_layout_content(content_lines, width, content_height, border_style) do
    content_strips =
      Drafter.ContentRenderer.render_vertical_layout(
        content_lines,
        width - 4,
        content_height
      )

    Enum.map(content_strips, fn strip ->
      Strip.new([Segment.new("│ ", border_style)] ++ strip.segments ++ [Segment.new(" │", border_style)])
    end)
  end

  defp extract_label_content(content_lines) do
    Enum.find_value(content_lines, fn
      {:label, text} when is_binary(text) -> text
      {:label, text, _opts} when is_binary(text) -> text
      _ -> nil
    end)
  end

  defp render_label_content(text, width, content_height, border_style, bg_style) do
    inner_width = width - 4
    lines = wrap_text(text, inner_width)

    content_strips =
      lines
      |> Enum.take(content_height)
      |> Enum.map(fn line ->
        padded = String.pad_trailing(line, inner_width)

        Strip.new([
          Segment.new("│ ", border_style),
          Segment.new(padded, bg_style),
          Segment.new(" │", border_style)
        ])
      end)

    padding_needed = max(0, content_height - length(content_strips))

    padding_strips =
      List.duplicate(
        Strip.new([
          Segment.new("│ ", border_style),
          Segment.new(String.duplicate(" ", inner_width), bg_style),
          Segment.new(" │", border_style)
        ]),
        padding_needed
      )

    content_strips ++ padding_strips
  end

  defp wrap_text(text, max_width) do
    words = String.split(text)
    {lines, current_line} = Enum.reduce(words, {[], ""}, &wrap_word(&1, &2, max_width))
    if current_line != "", do: lines ++ [current_line], else: lines
  end

  defp wrap_word(word, {lines, ""}, _max_width), do: {lines, word}

  defp wrap_word(word, {lines, current}, max_width) do
    test_line = current <> " " <> word

    if String.length(test_line) <= max_width do
      {lines, test_line}
    else
      {lines ++ [current], word}
    end
  end

  defp render_string_content(
         content_lines,
         width,
         content_height,
         border_style,
         bg_style,
         _active_tab
       ) do
    content_lines
    |> Enum.take(content_height)
    |> Enum.map(fn line ->
      text_content = String.pad_trailing(line, width - 4)

      Strip.new([
        Segment.new("│ ", border_style),
        Segment.new(text_content, bg_style),
        Segment.new(" │", border_style)
      ])
    end)
  end

  defp mount_child_widgets(tabs) do
    Enum.map(tabs, fn tab ->
      case tab.content do
        [widget_tuple] when is_tuple(widget_tuple) ->
          mount_widget_from_tuple(widget_tuple)

        _ ->
          nil
      end
    end)
  end

  defp mount_widget_from_tuple({:option_list, items, opts}) do
    alias Drafter.Widget.OptionList

    on_select = Keyword.get(opts, :on_select)
    on_highlight = Keyword.get(opts, :on_highlight)
    selected = Keyword.get(opts, :selected)

    options = Enum.map(items, &normalize_option(&1, selected))

    mount_props = %{
      options: options,
      visible_height: 10,
      expand_height: :fill,
      on_select: build_callback_wrapper(on_select),
      on_highlight: build_callback_wrapper(on_highlight)
    }

    {:option_list, OptionList.mount(mount_props)}
  end

  defp mount_widget_from_tuple(_widget_tuple), do: nil

  defp normalize_option({label, id}, selected),
    do: %{id: id, label: to_string(label), selected: id == selected, disabled: false}

  defp normalize_option(label, selected) when is_binary(label),
    do: %{id: label, label: label, selected: label == selected, disabled: false}

  defp normalize_option(%{id: id} = item, selected),
    do: Map.merge(%{selected: id == selected, disabled: false}, item)

  defp build_callback_wrapper(nil), do: nil

  defp build_callback_wrapper(callback) do
    fn option ->
      dispatch_app_callback(callback, option.id)
    end
  end

  defp dispatch_app_callback(callback, value) do
    case Drafter.ScreenManager.get_active_screen() do
      nil -> Drafter.AppRegistry.send_to_loop({:app_event, callback, value})
      _screen -> send(self(), {:tui_event, {:app_callback, callback, value}})
    end
  end

  defp render_widget_with_state({:option_list, widget_state}, width, height, border_style) do
    alias Drafter.Widget.OptionList

    rect = %{x: 0, y: 0, width: width - 4, height: height}

    strips = OptionList.render(widget_state, rect)

    Enum.map(strips, fn strip ->
      border_left = Segment.new("│ ", border_style)
      border_right = Segment.new(" │", border_style)

      segments = [border_left] ++ strip.segments ++ [border_right]
      Strip.new(segments)
    end)
  end

  defp render_widget_with_state(_widget, _width, _height, _border_style), do: []

  defp dispatch_event_to_child(state, {:option_list, child_state}, event, tab_index) do
    alias Drafter.Widget.OptionList

    case OptionList.handle_event(event, child_state) do
      {:ok, new_child_state} ->
        updated_children =
          List.replace_at(state.child_widgets, tab_index, {:option_list, new_child_state})

        {:ok, %{state | child_widgets: updated_children}}

      {:noreply, new_child_state} ->
        updated_children =
          List.replace_at(state.child_widgets, tab_index, {:option_list, new_child_state})

        {:noreply, %{state | child_widgets: updated_children}}

      _ ->
        {:noreply, state}
    end
  end

  defp dispatch_event_to_child(state, _child, _event, _tab_index) do
    {:noreply, state}
  end
end
