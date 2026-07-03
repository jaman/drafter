defmodule Drafter.Widget.DirectoryTree do
  @moduledoc """
  A live file-system tree widget that reads directories lazily as nodes are expanded.

  The root directory is expanded by default. Directories are rendered in blue with a `▼`
  or `▶` indicator; files are rendered in the default foreground colour. Selecting a file
  (Enter, Space, or click) updates `:selected_file` and calls `:on_file_select` if provided.

  Horizontal scrolling is available when path names are wider than the widget via the
  left/right arrow keys.

  ## Options

    * `:path` - absolute root path to display (default: current working directory)
    * `:show_hidden` - include hidden files and directories starting with `.` (default: `false`)
    * `:on_select` - `(String.t() -> term())` called with the path of any selected item
    * `:on_file_select` - `(String.t() -> term())` called only when a file (not a directory) is selected
    * `:target` - optional atom or string identifier used when wiring into the app's event system
    * `:style` - map of style overrides
    * `:classes` - list of theme class atoms
    * `:handles` - list of event types to respond to; defaults to `[:keyboard, :click, :scroll]`

  ## Key bindings

    * `↑` / `↓` — move cursor one item up/down
    * `Enter` — expand/collapse directory, or select file
    * `Space` — toggle directory expand/collapse; select file
    * `←` / `→` — scroll view horizontally
    * Mouse click — move cursor and activate item
    * Mouse scroll — move cursor 3 items at a time

  ## Usage

      directory_tree(path: "/home/user/projects", on_file_select: :file_opened)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :mouse_up, :scroll]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  @type tree_item :: %{
          path: String.t(),
          type: :dir | :file,
          depth: non_neg_integer()
        }

  @type t :: %__MODULE__{
          path: String.t(),
          expanded_dirs: MapSet.t(String.t()),
          selected_file: String.t() | nil,
          style: map(),
          classes: list(atom()),
          app_module: module() | nil,
          focused: boolean(),
          hovered: boolean(),
          show_hidden: boolean(),
          on_select: (String.t() -> any()) | nil,
          on_file_select: (String.t() -> any()) | nil,
          target: atom() | String.t() | nil,
          cursor_pos: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          viewport_height: non_neg_integer(),
          handles: list(atom())
        }

  defstruct [
    :path,
    :expanded_dirs,
    :selected_file,
    :style,
    :classes,
    :app_module,
    :focused,
    :hovered,
    :show_hidden,
    :on_select,
    :on_file_select,
    :target,
    :cursor_pos,
    :scroll_offset,
    h_scroll_offset: 0,
    viewport_height: 10,
    handles: [:keyboard, :mouse_up, :scroll]
  ]

  @impl Drafter.Widget
  def mount(props) do
    path = Map.get(props, :path, File.cwd!())

    %__MODULE__{
      path: path,
      expanded_dirs: MapSet.new([path]),
      selected_file: nil,
      show_hidden: Map.get(props, :show_hidden, false),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      focused: Map.get(props, :focused, false),
      hovered: false,
      on_select: Map.get(props, :on_select),
      on_file_select: Map.get(props, :on_file_select),
      target: Map.get(props, :target),
      cursor_pos: 0,
      scroll_offset: 0,
      h_scroll_offset: 0,
      handles: Map.get(props, :handles, [:keyboard, :mouse_up, :scroll])
    }
  end

  @impl Drafter.Widget
  def on_rect_change(rect, state) do
    %{state | viewport_height: rect.height}
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = ensure_mounted(state)
    computed = compute_style(state)

    default_fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}
    selected_bg = computed[:background] || {60, 80, 60}

    tree_items = build_tree(state)

    visible_items =
      tree_items
      |> Enum.drop(state.scroll_offset)
      |> Enum.take(rect.height)

    strips = render_items(visible_items, state, rect, default_fg, bg, selected_bg)

    if strips != [] do
      strips
    else
      empty_line = String.duplicate(" ", rect.width)
      [Strip.new([Segment.new(empty_line, %{fg: default_fg, bg: bg})])]
    end
  end

  @impl Drafter.Widget
  def handle_key(:up, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    new_pos = max(0, state.cursor_pos - 1)
    new_scroll = if new_pos < state.scroll_offset, do: state.scroll_offset - 1, else: state.scroll_offset
    new_state = %{state | cursor_pos: new_pos, scroll_offset: max(0, new_scroll)}
    actions = cursor_actions_for_pos(new_state, tree_items, new_pos)
    {:ok, new_state, actions}
  end

  def handle_key(:down, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    new_pos = min(length(tree_items) - 1, state.cursor_pos + 1)
    last_visible_idx = state.scroll_offset + state.viewport_height - 1
    new_scroll = if new_pos > last_visible_idx, do: state.scroll_offset + 1, else: state.scroll_offset
    new_state = %{state | cursor_pos: new_pos, scroll_offset: new_scroll}
    actions = cursor_actions_for_pos(new_state, tree_items, new_pos)
    {:ok, new_state, actions}
  end

  def handle_key(:enter, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    activate_cursor_item(state, tree_items)
  end

  def handle_key(:space, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    activate_cursor_item_space(state, tree_items)
  end

  def handle_key(:left, state) do
    state = ensure_mounted(state)
    {:ok, %{state | h_scroll_offset: max(0, state.h_scroll_offset - 2)}}
  end

  def handle_key(:right, state) do
    state = ensure_mounted(state)
    {:ok, %{state | h_scroll_offset: state.h_scroll_offset + 2}}
  end

  def handle_key(_key, state) do
    {:ok, ensure_mounted(state)}
  end

  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    state = ensure_mounted(state)

    if :scroll in state.handles do
      do_scroll(direction, state)
    else
      {:ok, state}
    end
  end

  @impl Drafter.Widget
  def handle_mouse_up(_x, y, state) do
    state = ensure_mounted(state)

    if :mouse_up in state.handles do
      tree_items = build_tree(state)
      actual_index = state.scroll_offset + y

      if actual_index < length(tree_items) do
        item = Enum.at(tree_items, actual_index)
        new_state = %{state | cursor_pos: actual_index}
        handle_item_selection(new_state, item)
      else
        {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_path = Map.get(props, :path, state.path)

    expanded_dirs =
      if new_path != state.path do
        MapSet.new([new_path])
      else
        state.expanded_dirs
      end

    cursor_pos = if new_path != state.path, do: 0, else: state.cursor_pos
    scroll_offset = if new_path != state.path, do: 0, else: state.scroll_offset

    %{
      state
      | path: new_path,
        expanded_dirs: expanded_dirs,
        cursor_pos: cursor_pos,
        scroll_offset: scroll_offset,
        show_hidden: Map.get(props, :show_hidden, state.show_hidden),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        on_select: Map.get(props, :on_select, state.on_select),
        on_file_select: Map.get(props, :on_file_select, state.on_file_select),
        handles: Map.get(props, :handles, state.handles)
    }
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, :auto)

  def component_tag, do: :directory_tree

  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    base = %{
      path: Keyword.get(opts, :path, File.cwd!()),
      show_hidden: Keyword.get(opts, :show_hidden, false),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select)),
      on_file_select: Callback.wrap_1(Keyword.get(opts, :on_file_select)),
      target: Keyword.get(opts, :target),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }

    case Keyword.get(opts, :handles) do
      nil -> base
      handles -> Map.put(base, :handles, handles)
    end
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    base = %{
      path: mount_props.path,
      show_hidden: mount_props.show_hidden,
      on_select: mount_props.on_select,
      on_file_select: mount_props.on_file_select,
      target: mount_props.target
    }

    case Map.get(mount_props, :handles) do
      nil -> base
      handles -> Map.put(base, :handles, handles)
    end
  end

  defp ensure_mounted(state) do
    if is_struct(state, __MODULE__), do: state, else: mount(state)
  end

  defp compute_style(state) do
    classes = state.classes ++ if state.focused, do: [:focus], else: []
    classes = classes ++ if state.hovered, do: [:hover], else: []
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    Computed.for_widget(:directory_tree, state, computed_opts)
  end

  defp item_bg(is_cursor, is_selected, selected_bg, bg) do
    cond do
      is_cursor and is_selected -> {80, 100, 80}
      is_cursor -> {50, 50, 60}
      is_selected -> selected_bg
      true -> bg
    end
  end

  defp item_fg(:dir, _default_fg), do: {150, 200, 255}
  defp item_fg(_type, default_fg), do: default_fg

  defp dir_prefix(path, expanded_dirs) do
    if MapSet.member?(expanded_dirs, path), do: "▼ ", else: "▶ "
  end

  defp render_item(item, idx, state, rect, default_fg, bg, selected_bg) do
    absolute_idx = state.scroll_offset + idx
    is_selected = item.path == state.selected_file
    is_cursor = absolute_idx == state.cursor_pos

    bg_color = item_bg(is_cursor, is_selected, selected_bg, bg)
    fg_color = item_fg(item.type, default_fg)

    indent = String.duplicate("  ", item.depth)
    prefix = if item.type == :dir, do: dir_prefix(item.path, state.expanded_dirs), else: "  "

    name = Path.basename(item.path)
    full_text = indent <> prefix <> name
    scrolled = String.slice(full_text, state.h_scroll_offset, String.length(full_text))

    truncated =
      if String.length(scrolled) > rect.width do
        String.slice(scrolled, 0, max(0, rect.width - 1)) <> "…"
      else
        scrolled
      end

    padded = String.pad_trailing(truncated, rect.width, " ")
    segment = Segment.new(padded, %{fg: fg_color, bg: bg_color})
    Strip.new([segment])
  end

  defp render_items(visible_items, state, rect, default_fg, bg, selected_bg) do
    Enum.with_index(visible_items, fn item, idx ->
      render_item(item, idx, state, rect, default_fg, bg, selected_bg)
    end)
  end

  defp do_scroll(:up, state) do
    tree_items = build_tree(state)
    scroll_amount = 3
    pos = max(0, state.cursor_pos - scroll_amount)
    scroll = if pos < state.scroll_offset, do: pos, else: state.scroll_offset
    new_state = %{state | cursor_pos: pos, scroll_offset: scroll}
    actions = cursor_actions_for_pos(new_state, tree_items, pos)
    {:ok, new_state, actions}
  end

  defp do_scroll(:down, state) do
    tree_items = build_tree(state)
    scroll_amount = 3
    pos = min(length(tree_items) - 1, state.cursor_pos + scroll_amount)

    scroll =
      if pos >= state.scroll_offset + state.viewport_height do
        pos - state.viewport_height + 1
      else
        state.scroll_offset
      end

    new_state = %{state | cursor_pos: pos, scroll_offset: scroll}
    actions = cursor_actions_for_pos(new_state, tree_items, pos)
    {:ok, new_state, actions}
  end

  defp cursor_actions_for_pos(state, tree_items, pos) do
    if pos < length(tree_items) do
      item = Enum.at(tree_items, pos)
      cursor_actions(state, item)
    else
      []
    end
  end

  defp activate_cursor_item(state, tree_items) do
    if state.cursor_pos < length(tree_items) do
      item = Enum.at(tree_items, state.cursor_pos)
      handle_item_selection(state, item)
    else
      {:ok, state}
    end
  end

  defp activate_cursor_item_space(state, tree_items) do
    if state.cursor_pos < length(tree_items) do
      item = Enum.at(tree_items, state.cursor_pos)
      activate_space_item(state, item)
    else
      {:ok, state}
    end
  end

  defp activate_space_item(state, %{type: :dir, path: path}) do
    toggle_directory(state, path)
  end

  defp activate_space_item(state, item) do
    handle_item_selection(state, item)
  end

  defp build_tree(state) do
    root_item = %{path: state.path, type: :dir, depth: 0}

    children =
      if MapSet.member?(state.expanded_dirs, state.path) do
        build_tree_recursive(state.path, state.expanded_dirs, state.show_hidden, 1, [])
      else
        []
      end

    [root_item | children]
  end

  defp build_tree_recursive(path, expanded_dirs, show_hidden, depth, acc) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> filter_hidden(show_hidden)
        |> build_items(path, expanded_dirs, show_hidden, depth, acc)

      {:error, _} ->
        acc
    end
  end

  defp filter_hidden(entries, true), do: entries
  defp filter_hidden(entries, false), do: Enum.reject(entries, &String.starts_with?(&1, "."))

  defp build_items(entries, path, expanded_dirs, show_hidden, depth, acc) do
    {dirs, files} = Enum.split_with(entries, fn entry -> File.dir?(Path.join([path, entry])) end)

    dirs_with_children = Enum.flat_map(dirs, fn dir -> expand_dir(dir, path, expanded_dirs, show_hidden, depth) end)

    file_items = Enum.map(files, fn file -> %{path: Path.join([path, file]), type: :file, depth: depth} end)

    acc ++ dirs_with_children ++ file_items
  end

  defp expand_dir(dir, parent_path, expanded_dirs, show_hidden, depth) do
    full_path = Path.join([parent_path, dir])
    dir_item = %{path: full_path, type: :dir, depth: depth}

    children =
      if MapSet.member?(expanded_dirs, full_path) do
        build_tree_recursive(full_path, expanded_dirs, show_hidden, depth + 1, [])
      else
        []
      end

    [dir_item | children]
  end

  @spec handle_item_selection(t(), tree_item()) :: {:ok, t()}
  defp handle_item_selection(state, %{type: :dir, path: path}) do
    toggle_directory(state, path)
  end

  defp handle_item_selection(state, %{type: :file, path: path}) do
    new_state = %{state | selected_file: path}
    actions = file_select_actions(state, path)
    {:ok, new_state, actions}
  end

  defp toggle_directory(state, dir_path) do
    if MapSet.member?(state.expanded_dirs, dir_path) do
      {:ok, %{state | expanded_dirs: MapSet.delete(state.expanded_dirs, dir_path)}}
    else
      {:ok, %{state | expanded_dirs: MapSet.put(state.expanded_dirs, dir_path)}}
    end
  end

  defp cursor_actions(state, %{type: :file, path: path}), do: file_select_actions(state, path)
  defp cursor_actions(_state, _item), do: []

  defp file_select_actions(state, path) do
    if state.on_file_select do
      action = state.on_file_select.(path)
      if action, do: [action], else: []
    else
      []
    end
  end
end
