defmodule Drafter.Widget.DirectoryTree do
  @moduledoc """
  A live file-system tree widget that reads directories lazily as nodes are expanded.

  The root directory is expanded by default. Directories are rendered in blue with a `▼`
  or `▶` indicator; files are rendered in the default foreground colour. Selecting a file
  (Enter, Space, or click) updates `:selected_file` and calls `:on_file_select` if provided.

  Horizontal scrolling is available when path names are wider than the widget via the
  left/right arrow keys.

  ## Component tag

  Tag `:directory_tree`, built by `Drafter.App` as `{:directory_tree, opts}`:

      directory_tree(opts)

  There is no positional argument; every prop comes from `opts` via
  `from_component_opts/2`, which wraps `:on_select` and `:on_file_select` with
  `Drafter.Widget.Callback` so they may be given as atom event names.

  ## Options

    * `:path` - absolute root path to display. Default `File.cwd!()`. Only this
      directory starts expanded
    * `:show_hidden` - `t:boolean/0`, include entries starting with `.`. Default
      `false`
    * `:on_select` - atom event name or `(String.t() -> term())` called with the
      path of any selected item, file or directory. Default `nil`. A non-`nil`
      return value is emitted as an action
    * `:on_file_select` - atom event name or `(String.t() -> term())` called only
      when a file is selected. Default `nil`. A non-`nil` return value is emitted as
      an action
    * `:target` - atom or string identifier. Default `nil`. Carried on the state but
      never read, and not re-read by `update/2`
    * `:style` - `t:map/0` of style overrides. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:handles` - list of event types to respond to. Default
      `[:keyboard, :mouse_up, :scroll]`. Removing `:mouse_up` or `:scroll` makes the
      corresponding handler consume the event without acting on it
    * `:height` - read only by `preferred_height/2`, never by `mount/1`. Default
      `:auto`

  `update/2` re-reads `:path`, `:show_hidden`, `:style`, `:classes`, `:app_module`,
  `:on_select`, `:on_file_select` and `:handles`. A new `:path` collapses everything
  but the new root and resets the cursor and scroll offset. `:target` is mount-only.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`;
  the selection is reported through `:on_select` and `:on_file_select`.

  ## Key bindings

    * `↑` / `↓` — move cursor one item up/down, scrolling the viewport to follow.
      Landing on a file fires `:on_file_select`
    * `Enter` — expand/collapse directory, or select file
    * `Space` — toggle directory expand/collapse; select file
    * `←` / `→` — scroll view horizontally by two columns, clamped at `0` on the
      left and unbounded on the right
    * Mouse click — move cursor and activate item
    * Mouse scroll — move cursor 3 items at a time

  Every other key is consumed and leaves the state unchanged, so nothing bubbles out
  of a focused tree.

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

  @doc """
  Builds the tree state from `props`, with only the root directory expanded.

  `:selected_file`, `:cursor_pos` and both scroll offsets always start at `nil`/`0`.

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp", show_hidden: true})
      iex> {t.path, MapSet.to_list(t.expanded_dirs), t.show_hidden, t.cursor_pos}
      {"/tmp", ["/tmp"], true, 0}

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp"})
      iex> {t.selected_file, t.scroll_offset, t.h_scroll_offset, t.viewport_height, t.handles}
      {nil, 0, 0, 10, [:keyboard, :mouse_up, :scroll]}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Records the rect's height as the viewport height used by cursor scrolling.

  Called by the runtime whenever the widget's rect changes.

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp"})
      iex> Drafter.Widget.DirectoryTree.on_rect_change(%{x: 0, y: 0, width: 40, height: 25}, t).viewport_height
      25
  """
  @spec on_rect_change(Drafter.Widget.rect(), t()) :: t()
  def on_rect_change(rect, state) do
    %{state | viewport_height: rect.height}
  end

  @doc """
  Draws the visible slice of the tree into `rect`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. Directories
  are read from disk on every call, so an unreadable directory simply contributes no
  children. Emits at most `rect.height` strips starting at `:scroll_offset`, and one
  blank strip when nothing is visible.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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

  @doc """
  Moves the cursor, activates the item under it, or scrolls horizontally.

  `:up` and `:down` return `{:ok, state, actions}`, where `actions` carries the
  `:on_file_select` result when the cursor lands on a file. `:enter` and `:" "`
  toggle a directory or select a file, also returning `{:ok, state, actions}`.
  `:left` and `:right` move `:h_scroll_offset` by two columns and return
  `{:ok, state}`. Every other key returns `{:ok, state}` unchanged, so nothing
  bubbles.

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp"})
      iex> {:ok, moved} = Drafter.Widget.DirectoryTree.handle_key(:right, t)
      iex> {:ok, back} = Drafter.Widget.DirectoryTree.handle_key(:left, moved)
      iex> {moved.h_scroll_offset, back.h_scroll_offset}
      {2, 0}

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp"})
      iex> {:ok, ^t} = Drafter.Widget.DirectoryTree.handle_key(:escape, t)
      iex> t.cursor_pos
      0
  """
  @spec handle_key(Drafter.Widget.key(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [term()]}
  @impl Drafter.Widget
  def handle_key(:up, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    new_pos = max(0, state.cursor_pos - 1)

    new_scroll =
      if new_pos < state.scroll_offset, do: state.scroll_offset - 1, else: state.scroll_offset

    new_state = %{state | cursor_pos: new_pos, scroll_offset: max(0, new_scroll)}
    actions = cursor_actions_for_pos(new_state, tree_items, new_pos)
    {:ok, new_state, actions}
  end

  def handle_key(:down, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    new_pos = min(length(tree_items) - 1, state.cursor_pos + 1)
    last_visible_idx = state.scroll_offset + state.viewport_height - 1

    new_scroll =
      if new_pos > last_visible_idx, do: state.scroll_offset + 1, else: state.scroll_offset

    new_state = %{state | cursor_pos: new_pos, scroll_offset: new_scroll}
    actions = cursor_actions_for_pos(new_state, tree_items, new_pos)
    {:ok, new_state, actions}
  end

  def handle_key(:enter, state) do
    state = ensure_mounted(state)
    tree_items = build_tree(state)
    activate_cursor_item(state, tree_items)
  end

  def handle_key(:" ", state) do
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

  @doc """
  Moves the cursor three items per wheel notch.

  Returns `{:ok, state}` unchanged when `:scroll` is not in the widget's `:handles`,
  so the event is consumed either way.
  """
  @spec handle_scroll(:up | :down, t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [term()]}
  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    state = ensure_mounted(state)

    if :scroll in state.handles do
      do_scroll(direction, state)
    else
      {:ok, state}
    end
  end

  @doc """
  Moves the cursor to the item on row `y` and activates it.

  `y` is counted from the top of the widget, so the item is
  `scroll_offset + y`. A release past the last item, or one arriving when
  `:mouse_up` is not in the widget's `:handles`, returns `{:ok, state}` unchanged.
  """
  @spec handle_mouse_up(integer(), integer(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [term()]}
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

  @doc """
  Folds fresh props into `state`.

  Re-reads `:path`, `:show_hidden`, `:style`, `:classes`, `:app_module`,
  `:on_select`, `:on_file_select` and `:handles`. A new `:path` collapses every
  expanded directory except the new root and resets `:cursor_pos` and
  `:scroll_offset` to `0`. `:target`, `:selected_file`, `:h_scroll_offset` and
  `:viewport_height` are left alone.

      iex> t = Drafter.Widget.DirectoryTree.mount(%{path: "/tmp"})
      iex> moved = Drafter.Widget.DirectoryTree.update(%{path: "/"}, t)
      iex> {moved.path, MapSet.to_list(moved.expanded_dirs), moved.cursor_pos}
      {"/", ["/"], 0}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  `opts[:height]`, or `:auto` when it is absent, letting the layout give the tree
  whatever space is left.

      iex> Drafter.Widget.DirectoryTree.preferred_height(nil, [])
      :auto

      iex> Drafter.Widget.DirectoryTree.preferred_height(nil, height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer() | :auto
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, :auto)

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.DirectoryTree.component_tag()
      :directory_tree
  """
  @spec component_tag() :: :directory_tree
  def component_tag, do: :directory_tree

  @doc """
  Turns the `{:directory_tree, opts}` element into a props map for `mount/1`.

  The positional argument is ignored. `:class` is normalised into `:classes`,
  `:on_select` and `:on_file_select` are wrapped by
  `Drafter.Widget.Callback.wrap_1/1`, and `:__app_module__` becomes `:app_module`.
  `:handles` is included only when given, so its default lives in `mount/1`.

      iex> props = Drafter.Widget.DirectoryTree.from_component_opts(nil, path: "/tmp")
      iex> {props.path, props.show_hidden, props.on_select, props.classes, Map.has_key?(props, :handles)}
      {"/tmp", false, nil, [], false}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

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

  @doc """
  Narrows the props a re-render feeds to `update/2` to `:path`, `:show_hidden`,
  `:on_select`, `:on_file_select`, `:target` and, when present, `:handles`. `:style`
  and `:classes` stay as mounted.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
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

    dirs_with_children =
      Enum.flat_map(dirs, fn dir -> expand_dir(dir, path, expanded_dirs, show_hidden, depth) end)

    file_items =
      Enum.map(files, fn file -> %{path: Path.join([path, file]), type: :file, depth: depth} end)

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

  @spec handle_item_selection(t(), tree_item()) :: {:ok, t(), [term()]}
  defp handle_item_selection(state, %{type: :dir, path: path}) do
    {:ok, new_state} = toggle_directory(state, path)
    {:ok, new_state, select_actions(state, path)}
  end

  defp handle_item_selection(state, %{type: :file, path: path}) do
    new_state = %{state | selected_file: path}
    actions = file_select_actions(state, path) ++ select_actions(state, path)
    {:ok, new_state, actions}
  end

  defp select_actions(state, path) do
    if state.on_select do
      case state.on_select.(path) do
        nil -> []
        action -> [action]
      end
    else
      []
    end
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
