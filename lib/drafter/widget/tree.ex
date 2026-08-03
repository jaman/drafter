defmodule Drafter.Widget.Tree do
  @moduledoc """
  A hierarchical tree widget that renders nested nodes with expand/collapse controls.

  Expanded nodes show a `▼` prefix; collapsed nodes with children show `▶`; leaf nodes
  show an indent. Optional icons are displayed after the expansion character when
  `:show_icons` is enabled and a node provides an `:icon` field.

  The cursor moves through the currently visible (flattened) display list, which only
  includes children of expanded parent nodes.

  ## Node format

  Each node in the `:data` list is a map with the following fields:

    * `:id` — identifier used to track expansion and selection. Default: eight
      random bytes, regenerated every time the data is normalised, so a node
      without an explicit `:id` loses its expansion and selection state on the
      next `update/2`.
    * `:label` — display string. Default `"Unnamed"`.
    * `:children` — list of child nodes in the same format. Default `[]`; a
      non-list is replaced by `[]`.
    * `:icon` — string drawn before the label. Default `nil`.
    * `:metadata` — arbitrary map stored on the node and passed to callbacks.
      Default `%{}`.

  Every other key, `:expanded` among them, is dropped by normalisation. Nodes
  therefore always start collapsed and are expanded from the key bindings alone.

  Shorthand formats are also accepted:
    * a bare string becomes a node with that label and no children
    * `{"label", children}` becomes a node with that label and those children,
      where `children` may be a list or a map
    * a map of nodes is turned into a list with `Map.to_list/1`, so each entry
      arrives as a `{key, value}` tuple

  ## Component tag

  Tag `:tree`, built by `Drafter.App` as `{:tree, opts}`:

      tree(opts)

  There is no positional argument; the nodes are passed as `data:` in `opts`.
  `from_component_opts/2` wraps `:on_select`, `:on_expand` and
  `:on_node_highlight` with `Drafter.Widget.Callback`, so each may be given as an
  atom event name. `:width` and `:height` default to the rect the parent allocated.

  ## Options

    * `:data` - list of root nodes, or a map that is turned into one. Default
      `[]`. Anything else normalises to `[]`.
    * `:selection_mode` - `:none | :single | :multiple`. Default `:single`.
    * `:on_select` - atom event name or `([node] -> term())` called with the list
      of selected nodes on selection change. Default `nil`.
    * `:on_expand` - atom event name or `((node, boolean()) -> term())` called when
      a node is expanded or collapsed. Default `nil`.
    * `:on_node_highlight` - atom event name or `(node -> term())` called when the
      cursor moves to a different node. Default `nil`.
    * `:show_icons` - `t:boolean/0`, draw node `:icon` fields. Default `true`.
    * `:indent_size` - `t:pos_integer/0` spaces per depth level. Default `2`.
    * `:width` - `t:pos_integer/0` widget width in columns. Default `80` when
      mounting directly, and the allocated rect width through the element. Held on
      the state; `render/2` uses the rect it is given.
    * `:height` - `t:pos_integer/0` widget height in rows. Default `20` when
      mounting directly, and the allocated rect height through the element. Read
      by `handle_scroll/2` and the cursor's scroll adjustment, not by `render/2`.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`. Every key
      binding requires it.
    * `:height` as an element option is also what `preferred_height/2` returns,
      defaulting to `:auto` rather than to a row count.

  These style maps are read by `mount/1` and `update/2` only; the `tree/1` element
  does not forward them, and `render/2` overlays the current theme on top of them:

    * `:style` - base row style. Default `%{fg: {200, 200, 200}, bg: {30, 30, 30}}`.
    * `:selected_style` - style for selected rows. Default
      `%{fg: {255, 255, 255}, bg: {0, 120, 215}}`.
    * `:cursor_style` - style for the row under the cursor. Default
      `%{fg: {255, 255, 255}, bg: {50, 100, 200}, bold: true}`.
    * `:expanded_style` - style for the `▼` marker. Default
      `%{fg: {100, 200, 100}, bg: {30, 30, 30}}`.
    * `:collapsed_style` - style for the `▶` marker. Default
      `%{fg: {200, 200, 100}, bg: {30, 30, 30}}`.

  `mount/1` always starts the cursor at `0` with nothing expanded, nothing
  selected and no scroll; none of those can be seeded from props. `update/2`
  re-normalises `:data` and clamps the cursor into it, but leaves `:expanded_nodes`
  and `:selected_nodes` alone. Through the component tree
  `update_props_from_mount/3` always passes `:on_select`, `:on_expand`,
  `:on_node_highlight`, `:selection_mode`, `:show_icons`, `:indent_size` and
  `:data`, and `:width` and `:height` only when they changed.

  ## Widget value

  `Drafter.get_widget_value/1` returns the selected node ids as a list.

  ## Key bindings

    * `↑` / `↓` — move cursor through visible nodes
    * `←` — collapse the current node
    * `→` — expand the current node
    * `Enter` — toggle expand/collapse of the current node
    * `Space` — toggle selection of the current node
    * `+` — expand current node
    * `-` — collapse current node
    * `*` — expand all nodes
    * `/` — collapse all nodes
    * `Shift+←` / `Shift+→` — collapse or expand the current node
    * Mouse click — move cursor and toggle expand/collapse; this one does not
      require focus

  Every key binding requires the widget to be focused; unfocused, all of them fall
  through to `{:noreply, state}`.

  ## Usage

      tree(
        data: [
          %{id: :lib, label: "lib", children: [
            %{id: :app, label: "app.ex"},
            %{id: :router, label: "router.ex"}
          ]},
          %{id: :test, label: "test", children: []}
        ],
        on_select: fn nodes -> IO.inspect(nodes) end
      )
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:scroll]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager
  alias Drafter.Widget.Callback
  alias Drafter.Widget.Scrollbar

  defstruct [
    :data,
    :cursor_index,
    :expanded_nodes,
    :selected_nodes,
    :scroll_offset,
    :focused,
    :style,
    :selected_style,
    :cursor_style,
    :expanded_style,
    :collapsed_style,
    :selection_mode,
    :on_select,
    :on_expand,
    :on_node_highlight,
    :show_icons,
    :indent_size,
    :width,
    :height
  ]

  @type tree_node :: %{
          id: term(),
          label: String.t(),
          children: [tree_node()],
          icon: String.t() | nil,
          metadata: map()
        }

  @type selection_mode :: :none | :single | :multiple

  @type t :: %__MODULE__{
          data: [tree_node()],
          cursor_index: non_neg_integer(),
          expanded_nodes: MapSet.t(),
          selected_nodes: MapSet.t(),
          scroll_offset: non_neg_integer(),
          focused: boolean(),
          style: Segment.style(),
          selected_style: Segment.style(),
          cursor_style: Segment.style(),
          expanded_style: Segment.style(),
          collapsed_style: Segment.style(),
          selection_mode: selection_mode(),
          on_select: ([tree_node()] -> term()) | nil,
          on_expand: (tree_node(), boolean() -> term()) | nil,
          on_node_highlight: (tree_node() -> term()) | nil,
          show_icons: boolean(),
          indent_size: pos_integer(),
          width: pos_integer(),
          height: pos_integer()
        }

  @doc """
  Builds the widget state from `props`.

  `:data` is normalised into `t:tree_node/0` maps. Because normalisation drops
  every key it does not know, an `:expanded` field on an input node is gone by the
  time the expansion set is built, so `:expanded_nodes` always starts empty.
  `:cursor_index`, `:selected_nodes` and `:scroll_offset` likewise always start
  empty and cannot be seeded from props.

      iex> state = Drafter.Widget.Tree.mount(%{data: [%{id: :lib, label: "lib"}]})
      iex> state.data
      [%{id: :lib, label: "lib", children: [], icon: nil, metadata: %{}}]

      iex> state = Drafter.Widget.Tree.mount(%{data: [%{id: :lib, label: "lib", expanded: true}]})
      iex> MapSet.to_list(state.expanded_nodes)
      []

      iex> state = Drafter.Widget.Tree.mount(%{})
      iex> {state.data, state.cursor_index, state.selection_mode, state.show_icons, state.indent_size}
      {[], 0, :single, true, 2}

      iex> state = Drafter.Widget.Tree.mount(%{data: [{"lib", [%{id: :app, label: "app.ex"}]}]})
      iex> [root] = state.data
      iex> {root.label, Enum.map(root.children, & &1.label)}
      {"lib", ["app.ex"]}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    raw_data = Map.get(props, :data, [])
    normalized_data = normalize_tree_data(raw_data)

    expanded_nodes =
      normalized_data
      |> flatten_tree()
      |> Enum.filter(fn node -> Map.get(node, :expanded, false) end)
      |> Enum.map(fn node -> node.id end)
      |> MapSet.new()

    %__MODULE__{
      data: normalized_data,
      cursor_index: 0,
      expanded_nodes: expanded_nodes,
      selected_nodes: MapSet.new(),
      scroll_offset: 0,
      focused: Map.get(props, :focused, false),
      style: Map.get(props, :style, %{fg: {200, 200, 200}, bg: {30, 30, 30}}),
      selected_style: Map.get(props, :selected_style, %{fg: {255, 255, 255}, bg: {0, 120, 215}}),
      cursor_style:
        Map.get(props, :cursor_style, %{fg: {255, 255, 255}, bg: {50, 100, 200}, bold: true}),
      expanded_style: Map.get(props, :expanded_style, %{fg: {100, 200, 100}, bg: {30, 30, 30}}),
      collapsed_style: Map.get(props, :collapsed_style, %{fg: {200, 200, 100}, bg: {30, 30, 30}}),
      selection_mode: Map.get(props, :selection_mode, :single),
      on_select: Map.get(props, :on_select),
      on_expand: Map.get(props, :on_expand),
      on_node_highlight: Map.get(props, :on_node_highlight),
      show_icons: Map.get(props, :show_icons, true),
      indent_size: Map.get(props, :indent_size, 2),
      width: Map.get(props, :width, 80),
      height: Map.get(props, :height, 20)
    }
  end

  @doc """
  Draws the visible slice of the tree into `rect`, always returning exactly
  `rect.height` strips.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. Only children of expanded nodes appear. Rows start at `:scroll_offset`;
  when the flattened list is taller than `rect.height` the last column becomes a
  scrollbar and the rows are cropped one narrower. Theme colours are merged over
  the state's style maps first.
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

    theme = ThemeManager.get_current_theme()
    normalized_state = apply_theme_styles(normalized_state, theme)

    content_width = rect.width
    content_height = rect.height

    all_items = flatten_for_display(normalized_state)

    thumb =
      Scrollbar.thumb_rows(normalized_state.scroll_offset, length(all_items), content_height)

    item_width = if thumb, do: max(1, content_width - 1), else: content_width
    sb_styles = Scrollbar.styles(theme)

    strips =
      all_items
      |> Enum.slice(normalized_state.scroll_offset, content_height)
      |> Enum.with_index()
      |> Enum.map(fn {item, row} ->
        normalized_state
        |> render_tree_item(item, normalized_state.scroll_offset + row, item_width)
        |> Strip.crop(item_width)
        |> Scrollbar.append(row, thumb, sb_styles)
      end)

    current_height = length(strips)

    if current_height < content_height do
      empty_style = normalized_state.style
      empty_line = String.duplicate(" ", content_width)
      empty_strip = Strip.new([Segment.new(empty_line, empty_style)])
      padding = List.duplicate(empty_strip, content_height - current_height)
      strips ++ padding
    else
      strips
    end
  end

  @doc """
  Scrolls the viewport by three rows per wheel step, without moving the cursor.

  Always returns `{:ok, new_state}`. Scrolling up stops at `0`; scrolling down
  stops at `visible_row_count - height`, using the state's `:height`, not the rect.
  Works whether or not the widget is focused.

      iex> data = Enum.map(1..20, fn n -> %{id: n, label: "node"} end)
      iex> state = Drafter.Widget.Tree.mount(%{data: data, height: 5})
      iex> {:ok, down} = Drafter.Widget.Tree.handle_scroll(:down, state)
      iex> down.scroll_offset
      3

      iex> state = Drafter.Widget.Tree.mount(%{data: [%{id: :a, label: "a"}]})
      iex> {:ok, down} = Drafter.Widget.Tree.handle_scroll(:down, state)
      iex> down.scroll_offset
      0
  """
  @spec handle_scroll(:up | :down, t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_scroll(:up, state) do
    {:ok, %{state | scroll_offset: max(0, state.scroll_offset - 3)}}
  end

  def handle_scroll(:down, state) do
    total = length(flatten_for_display(state))
    max_offset = max(0, total - state.height)
    {:ok, %{state | scroll_offset: min(max_offset, state.scroll_offset + 3)}}
  end

  @doc """
  Handles the tree's own events, replacing the dispatch `use Drafter.Widget` would
  otherwise generate.

  Recognised events are the key bindings listed in the module doc — all of which
  require `:focused` — plus a mouse up, a mouse wheel, `{:focus}` and `{:blur}`,
  which do not. Anything else returns `{:noreply, state}`, and so does a cursor
  move that is already at either end and a collapse or expand that would not change
  anything.

  A cursor move calls `:on_node_highlight`, expanding or collapsing calls
  `:on_expand` with the node and its new state, and toggling a selection calls
  `:on_select` with every selected node.

      iex> data = [%{id: :a, label: "a"}, %{id: :b, label: "b"}]
      iex> state = Drafter.Widget.Tree.mount(%{data: data, focused: true})
      iex> {:ok, moved} = Drafter.Widget.Tree.handle_event({:key, :down}, state)
      iex> moved.cursor_index
      1

      iex> data = [%{id: :a, label: "a"}]
      iex> state = Drafter.Widget.Tree.mount(%{data: data, focused: true})
      iex> Drafter.Widget.Tree.handle_event({:key, :up}, state) == {:noreply, state}
      true

      iex> data = [%{id: :a, label: "a", children: [%{id: :b, label: "b"}]}]
      iex> state = Drafter.Widget.Tree.mount(%{data: data, focused: true})
      iex> {:ok, expanded} = Drafter.Widget.Tree.handle_event({:key, :right}, state)
      iex> MapSet.to_list(expanded.expanded_nodes)
      [:a]

      iex> data = [%{id: :a, label: "a"}]
      iex> state = Drafter.Widget.Tree.mount(%{data: data, focused: true})
      iex> {:ok, selected} = Drafter.Widget.Tree.handle_event({:key, :" "}, state)
      iex> MapSet.to_list(selected.selected_nodes)
      [:a]

      iex> data = [%{id: :a, label: "a"}, %{id: :b, label: "b"}]
      iex> state = Drafter.Widget.Tree.mount(%{data: data})
      iex> Drafter.Widget.Tree.handle_event({:key, :down}, state) == {:noreply, state}
      true
  """
  @spec handle_event(term(), t()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_event({:key, :up}, %{focused: true} = state), do: move_cursor_up(state)
  def handle_event({:key, :down}, %{focused: true} = state), do: move_cursor_down(state)

  def handle_event({:key, :left, [:shift]}, %{focused: true} = state),
    do: move_to_prev_sibling(state)

  def handle_event({:key, :right, [:shift]}, %{focused: true} = state),
    do: move_to_next_sibling(state)

  def handle_event({:key, :left}, %{focused: true} = state), do: collapse_current_node(state)
  def handle_event({:key, :right}, %{focused: true} = state), do: expand_current_node(state)
  def handle_event({:key, :enter}, %{focused: true} = state), do: toggle_current_node(state)
  def handle_event({:key, :" "}, %{focused: true} = state), do: toggle_selection(state)
  def handle_event({:key, :+}, %{focused: true} = state), do: expand_current_node(state)
  def handle_event({:key, :-}, %{focused: true} = state), do: collapse_current_node(state)
  def handle_event({:key, :*}, %{focused: true} = state), do: expand_all_nodes(state)
  def handle_event({:key, :/}, %{focused: true} = state), do: collapse_all_nodes(state)

  def handle_event({:mouse, %{type: :mouse_up, x: _x, y: y}}, state),
    do: handle_mouse_click(state, y)

  def handle_event({:mouse, %{type: :scroll, direction: dir}}, state),
    do: handle_scroll(dir, state)

  def handle_event({:focus}, state), do: {:ok, %{state | focused: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false}}
  def handle_event(_event, state), do: {:noreply, state}

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  `:data` is re-normalised on every call, whether or not `props` carries it, and
  the cursor is clamped to the resulting visible row count. `:expanded_nodes`,
  `:selected_nodes` and `:scroll_offset` are left alone, so expansion survives new
  data only for nodes that keep the same explicit `:id`.

      iex> data = [%{id: :a, label: "a"}, %{id: :b, label: "b"}]
      iex> state = %{Drafter.Widget.Tree.mount(%{data: data}) | cursor_index: 1}
      iex> updated = Drafter.Widget.Tree.update(%{data: [%{id: :a, label: "a"}]}, state)
      iex> {length(updated.data), updated.cursor_index}
      {1, 0}

      iex> state = Drafter.Widget.Tree.mount(%{data: [%{id: :a, label: "a"}]})
      iex> Drafter.Widget.Tree.update(%{show_icons: false}, state).show_icons
      false
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)

    normalized_data = normalize_tree_data(new_data)

    display_items = flatten_for_display(%{state | data: normalized_data})
    max_index = max(0, length(display_items) - 1)
    cursor_index = min(state.cursor_index, max_index)

    %{
      state
      | data: normalized_data,
        cursor_index: cursor_index,
        selection_mode: Map.get(props, :selection_mode, state.selection_mode),
        style: Map.get(props, :style, state.style),
        selected_style: Map.get(props, :selected_style, state.selected_style),
        cursor_style: Map.get(props, :cursor_style, state.cursor_style),
        expanded_style: Map.get(props, :expanded_style, state.expanded_style),
        collapsed_style: Map.get(props, :collapsed_style, state.collapsed_style),
        on_select: Map.get(props, :on_select, state.on_select),
        on_expand: Map.get(props, :on_expand, state.on_expand),
        on_node_highlight: Map.get(props, :on_node_highlight, state.on_node_highlight),
        show_icons: Map.get(props, :show_icons, state.show_icons),
        indent_size: Map.get(props, :indent_size, state.indent_size),
        width: Map.get(props, :width, state.width),
        height: Map.get(props, :height, state.height)
    }
  end

  defp move_cursor_up(state) do
    if state.cursor_index > 0 do
      new_index = state.cursor_index - 1

      new_state =
        %{state | cursor_index: new_index}
        |> adjust_scroll_vertical()

      display_items = flatten_for_display(new_state)
      trigger_node_highlight(new_state, Enum.at(display_items, new_index))
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  defp move_cursor_down(state) do
    display_items = flatten_for_display(state)
    max_index = length(display_items) - 1

    if state.cursor_index < max_index do
      new_index = state.cursor_index + 1

      new_state =
        %{state | cursor_index: new_index}
        |> adjust_scroll_vertical()

      trigger_node_highlight(new_state, Enum.at(display_items, new_index))
      {:ok, new_state}
    else
      {:noreply, state}
    end
  end

  defp expand_current_node(state) do
    display_items = flatten_for_display(state)

    if state.cursor_index < length(display_items) do
      current_item = Enum.at(display_items, state.cursor_index)

      if current_item.children && current_item.children != [] do
        expanded_nodes = MapSet.put(state.expanded_nodes, current_item.id)
        new_state = %{state | expanded_nodes: expanded_nodes}
        trigger_expand(new_state, current_item, true)
        {:ok, new_state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp collapse_current_node(state) do
    display_items = flatten_for_display(state)

    if state.cursor_index < length(display_items) do
      current_item = Enum.at(display_items, state.cursor_index)

      if MapSet.member?(state.expanded_nodes, current_item.id) do
        expanded_nodes = MapSet.delete(state.expanded_nodes, current_item.id)
        new_state = %{state | expanded_nodes: expanded_nodes}
        trigger_expand(new_state, current_item, false)
        {:ok, new_state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp toggle_current_node(state) do
    display_items = flatten_for_display(state)

    if state.cursor_index < length(display_items) do
      current_item = Enum.at(display_items, state.cursor_index)
      toggle_node_if_parent(state, current_item)
    else
      {:noreply, state}
    end
  end

  defp toggle_node_if_parent(state, %{children: children}) when children in [nil, []] do
    {:noreply, state}
  end

  defp toggle_node_if_parent(state, current_item) do
    if MapSet.member?(state.expanded_nodes, current_item.id) do
      collapse_current_node(state)
    else
      expand_current_node(state)
    end
  end

  defp expand_all_nodes(state) do
    all_nodes =
      flatten_tree(state.data)
      |> Enum.filter(fn node -> node.children && node.children != [] end)
      |> Enum.map(fn node -> node.id end)
      |> MapSet.new()

    {:ok, %{state | expanded_nodes: all_nodes}}
  end

  defp collapse_all_nodes(state) do
    {:ok, %{state | expanded_nodes: MapSet.new()}}
  end

  defp toggle_selection(state) do
    case state.selection_mode do
      :none ->
        {:noreply, state}

      :single ->
        display_items = flatten_for_display(state)

        if state.cursor_index < length(display_items) do
          current_item = Enum.at(display_items, state.cursor_index)

          selected =
            if MapSet.member?(state.selected_nodes, current_item.id) do
              MapSet.new()
            else
              MapSet.new([current_item.id])
            end

          new_state = %{state | selected_nodes: selected}
          trigger_selection(new_state)
          {:ok, new_state}
        else
          {:noreply, state}
        end

      :multiple ->
        display_items = flatten_for_display(state)

        if state.cursor_index < length(display_items) do
          current_item = Enum.at(display_items, state.cursor_index)

          selected =
            if MapSet.member?(state.selected_nodes, current_item.id) do
              MapSet.delete(state.selected_nodes, current_item.id)
            else
              MapSet.put(state.selected_nodes, current_item.id)
            end

          new_state = %{state | selected_nodes: selected}
          trigger_selection(new_state)
          {:ok, new_state}
        else
          {:noreply, state}
        end
    end
  end

  defp handle_mouse_click(state, y) do
    clicked_index = y + state.scroll_offset
    display_items = flatten_for_display(state)

    if clicked_index >= 0 && clicked_index < length(display_items) do
      new_state = %{state | cursor_index: clicked_index, focused: true}
      current_item = Enum.at(display_items, clicked_index)
      trigger_node_highlight(new_state, current_item)
      click_toggle_node(new_state, current_item)
    else
      {:noreply, state}
    end
  end

  defp click_toggle_node(state, %{children: children} = item)
       when is_list(children) and children != [] do
    new_state =
      if MapSet.member?(state.expanded_nodes, item.id) do
        trigger_expand(state, item, false)
        %{state | expanded_nodes: MapSet.delete(state.expanded_nodes, item.id)}
      else
        trigger_expand(state, item, true)
        %{state | expanded_nodes: MapSet.put(state.expanded_nodes, item.id)}
      end

    select_on_click(new_state, item)
  end

  defp click_toggle_node(state, item), do: select_on_click(state, item)

  defp select_on_click(state, item) do
    case state.selection_mode do
      :none ->
        {:ok, state}

      _ ->
        new_state = %{state | selected_nodes: MapSet.new([item.id])}
        trigger_selection(new_state)
        {:ok, new_state}
    end
  end

  defp expansion_char(item, expanded_nodes) do
    if item.children && item.children != [] do
      if MapSet.member?(expanded_nodes, item.id), do: "▼ ", else: "▶ "
    else
      "  "
    end
  end

  defp item_icon(item, show_icons) do
    if show_icons && item.icon, do: item.icon <> "  ", else: ""
  end

  defp item_style(state, item, is_cursor, is_selected, is_expanded) do
    has_children = item.children && item.children != []

    cond do
      is_cursor -> state.cursor_style
      is_selected -> state.selected_style
      is_expanded && has_children -> state.expanded_style
      has_children -> state.collapsed_style
      true -> state.style
    end
  end

  defp format_content(content, width) do
    if display_width(content) >= width do
      truncate_to_width(content, max(0, width - 2)) <> "…"
    else
      pad_to_width(content, width)
    end
  end

  defp render_tree_item(state, item, index, width) do
    is_cursor = state.focused && index == state.cursor_index
    is_selected = MapSet.member?(state.selected_nodes, item.id)
    is_expanded = MapSet.member?(state.expanded_nodes, item.id)

    indent = String.duplicate(" ", item.depth * state.indent_size)
    exp_char = expansion_char(item, state.expanded_nodes)
    icon = item_icon(item, state.show_icons)

    content = indent <> exp_char <> icon <> item.label
    formatted_content = format_content(content, width)
    style = item_style(state, item, is_cursor, is_selected, is_expanded)

    Strip.new([Segment.new(formatted_content, style)])
  end

  defp normalize_tree_data(data) when is_map(data) do
    data
    |> Map.to_list()
    |> Enum.map(&normalize_node/1)
  end

  defp normalize_tree_data(data) when is_list(data) do
    Enum.map(data, &normalize_node/1)
  end

  defp normalize_tree_data(_data), do: []

  defp normalize_node(node) when is_map(node) do
    children = Map.get(node, :children, [])

    normalized_children =
      if children && is_list(children) do
        Enum.map(children, &normalize_node/1)
      else
        []
      end

    %{
      id: Map.get(node, :id, :crypto.strong_rand_bytes(8)),
      label: Map.get(node, :label, "Unnamed"),
      children: normalized_children,
      icon: Map.get(node, :icon),
      metadata: Map.get(node, :metadata, %{})
    }
  end

  defp normalize_node(node) when is_binary(node) do
    %{
      id: :crypto.strong_rand_bytes(8),
      label: node,
      children: [],
      icon: nil,
      metadata: %{}
    }
  end

  defp normalize_node({label, children}) when is_binary(label) and is_list(children) do
    %{
      id: :crypto.strong_rand_bytes(8),
      label: label,
      children: Enum.map(children, &normalize_node/1),
      icon: nil,
      metadata: %{}
    }
  end

  defp normalize_node({label, children}) when is_binary(label) and is_map(children) do
    %{
      id: :crypto.strong_rand_bytes(8),
      label: label,
      children: children |> Map.to_list() |> Enum.map(&normalize_node/1),
      icon: nil,
      metadata: %{}
    }
  end

  defp flatten_tree(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node] ++ flatten_tree(node.children || [])
    end)
  end

  defp flatten_for_display(state, nodes \\ nil, depth \\ 0) do
    nodes = nodes || state.data

    Enum.flat_map(nodes, fn node ->
      item_with_depth = Map.put(node, :depth, depth)

      if MapSet.member?(state.expanded_nodes, node.id) && node.children do
        [item_with_depth] ++ flatten_for_display(state, node.children, depth + 1)
      else
        [item_with_depth]
      end
    end)
  end

  defp adjust_scroll_vertical(state) do
    cond do
      state.cursor_index < state.scroll_offset ->
        %{state | scroll_offset: state.cursor_index}

      state.cursor_index >= state.scroll_offset + state.height ->
        %{state | scroll_offset: state.cursor_index - state.height + 1}

      true ->
        state
    end
  end

  defp trigger_selection(%{on_select: nil}), do: :ok

  defp trigger_selection(state) do
    all_nodes = flatten_tree(state.data)

    selected_data =
      state.selected_nodes
      |> MapSet.to_list()
      |> Enum.map(fn id -> Enum.find(all_nodes, fn node -> node.id == id end) end)
      |> Enum.filter(& &1)

    try do
      state.on_select.(selected_data)
    rescue
      _error -> :ok
    end
  end

  defp trigger_expand(state, node, expanded) do
    if state.on_expand do
      try do
        state.on_expand.(node, expanded)
      rescue
        _error -> :ok
      end
    end
  end

  defp trigger_node_highlight(state, node) do
    if state.on_node_highlight && node do
      try do
        state.on_node_highlight.(node)
      rescue
        _error -> :ok
      end
    end
  end

  defp move_to_prev_sibling(state) do
    display_items = flatten_for_display(state)
    current_item = Enum.at(display_items, state.cursor_index)

    case current_item do
      nil ->
        {:noreply, state}

      item ->
        current_depth = item.depth

        prev_sibling_index =
          display_items
          |> Enum.take(state.cursor_index)
          |> Enum.with_index()
          |> Enum.filter(fn {candidate, _idx} -> candidate.depth == current_depth end)
          |> List.last()
          |> case do
            {_node, idx} -> idx
            nil -> nil
          end

        case prev_sibling_index do
          nil ->
            {:noreply, state}

          new_index ->
            new_state =
              %{state | cursor_index: new_index}
              |> adjust_scroll_vertical()

            trigger_node_highlight(new_state, Enum.at(display_items, new_index))
            {:ok, new_state}
        end
    end
  end

  defp move_to_next_sibling(state) do
    display_items = flatten_for_display(state)
    current_item = Enum.at(display_items, state.cursor_index)

    case current_item do
      nil ->
        {:noreply, state}

      item ->
        current_depth = item.depth

        next_sibling_index =
          display_items
          |> Enum.with_index()
          |> Enum.drop(state.cursor_index + 1)
          |> Enum.find(fn {candidate, _idx} -> candidate.depth == current_depth end)
          |> case do
            {_node, idx} -> idx
            nil -> nil
          end

        case next_sibling_index do
          nil ->
            {:noreply, state}

          new_index ->
            new_state =
              %{state | cursor_index: new_index}
              |> adjust_scroll_vertical()

            trigger_node_highlight(new_state, Enum.at(display_items, new_index))
            {:ok, new_state}
        end
    end
  end

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `:auto`.

  Unlike the other widgets this returns an atom when no height is given, leaving
  the row count to the layout.

      iex> Drafter.Widget.Tree.preferred_height(nil, [])
      :auto

      iex> Drafter.Widget.Tree.preferred_height(nil, height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer() | :auto
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, :auto)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Tree.component_tag()
      :tree
  """
  @spec component_tag() :: :tree
  def component_tag, do: :tree

  @doc """
  Builds the props map for a `{:tree, opts}` element.

  The positional argument is ignored; the nodes come from `opts[:data]`.
  `:on_select` and `:on_node_highlight` go through
  `Drafter.Widget.Callback.wrap_1/1` and `:on_expand` through `wrap_2/1`, so an
  atom becomes a closure that dispatches an app event. `:width` and `:height` fall
  back to `opts[:__rect__]`, itself defaulting to `%{width: 80, height: 20}`. The
  five style maps are not forwarded.

      iex> props = Drafter.Widget.Tree.from_component_opts(nil, data: [%{id: :a, label: "a"}])
      iex> {props.selection_mode, props.show_icons, props.indent_size, props.width, props.height}
      {:single, true, 2, 80, 20}

      iex> props = Drafter.Widget.Tree.from_component_opts(nil, on_select: :picked)
      iex> {props.data, is_function(props.on_select, 1)}
      {[], true}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80, height: 20})

    %{
      data: Keyword.get(opts, :data, []),
      selection_mode: Keyword.get(opts, :selection_mode, :single),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select)),
      on_expand: Callback.wrap_2(Keyword.get(opts, :on_expand)),
      on_node_highlight: Callback.wrap_1(Keyword.get(opts, :on_node_highlight)),
      show_icons: Keyword.get(opts, :show_icons, true),
      indent_size: Keyword.get(opts, :indent_size, 2),
      width: Keyword.get(opts, :width, rect.width),
      height: Keyword.get(opts, :height, rect.height)
    }
  end

  @doc """
  Narrows a re-render to the props that may safely change after mount.

  Always passes `:on_select`, `:on_expand`, `:on_node_highlight`,
  `:selection_mode`, `:show_icons`, `:indent_size` and `:data`. Adds `:width` and
  `:height` only when they differ from the mounted state.

      iex> props = Drafter.Widget.Tree.from_component_opts(nil, data: [%{id: :a, label: "a"}])
      iex> state = Drafter.Widget.Tree.mount(props)
      iex> Drafter.Widget.Tree.update_props_from_mount(props, state, []) |> Map.keys() |> Enum.sort()
      [:data, :indent_size, :on_expand, :on_node_highlight, :on_select, :selection_mode, :show_icons]

      iex> props = Drafter.Widget.Tree.from_component_opts(nil, __rect__: %{width: 40, height: 8})
      iex> state = Drafter.Widget.Tree.mount(%{})
      iex> result = Drafter.Widget.Tree.update_props_from_mount(props, state, [])
      iex> {result.width, result.height}
      {40, 8}
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, _opts) do
    base = %{
      on_select: mount_props.on_select,
      on_expand: mount_props.on_expand,
      on_node_highlight: mount_props.on_node_highlight,
      selection_mode: mount_props.selection_mode,
      show_icons: mount_props.show_icons,
      indent_size: mount_props.indent_size,
      data: mount_props.data
    }

    base =
      if existing_state.width != mount_props.width do
        Map.put(base, :width, mount_props.width)
      else
        base
      end

    if existing_state.height != mount_props.height do
      Map.put(base, :height, mount_props.height)
    else
      base
    end
  end

  defp apply_theme_styles(state, theme) do
    %{
      state
      | style: %{fg: theme.text_primary, bg: theme.background},
        selected_style: %{fg: theme.text_primary, bg: theme.primary},
        cursor_style: %{fg: theme.text_primary, bg: theme.primary, bold: true},
        expanded_style: %{fg: theme.success, bg: theme.background},
        collapsed_style: %{fg: theme.warning, bg: theme.background}
    }
  end

  defp char_width(grapheme), do: Drafter.CharacterWidth.grapheme(grapheme)
  defp display_width(str), do: Drafter.CharacterWidth.string(str)

  defp truncate_to_width(str, target_width) do
    str
    |> String.graphemes()
    |> Enum.reduce_while({"", 0}, fn grapheme, {acc, width} ->
      grapheme_w = char_width(grapheme)
      new_width = width + grapheme_w

      if new_width <= target_width do
        {:cont, {acc <> grapheme, new_width}}
      else
        {:halt, {acc, width}}
      end
    end)
    |> elem(0)
  end

  defp pad_to_width(str, target_width) do
    current_width = display_width(str)
    padding_needed = max(0, target_width - current_width)
    str <> String.duplicate(" ", padding_needed)
  end
end
