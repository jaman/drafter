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
    handles: [:keyboard, :mouse_up, :scroll],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

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

  def on_rect_change(rect, state) do
    %{state | viewport_height: rect.height}
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    classes = state.classes ++ if state.focused, do: [:focus], else: []
    classes = classes ++ if state.hovered, do: [:hover], else: []
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:directory_tree, state, computed_opts)

    default_fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}
    selected_bg = computed[:background] || {60, 80, 60}

    tree_items = build_tree(state)

    visible_items =
      tree_items
      |> Enum.drop(state.scroll_offset)
      |> Enum.take(rect.height)

    strips =
      Enum.with_index(visible_items, fn item, idx ->
        absolute_idx = state.scroll_offset + idx
        is_selected = item.path == state.selected_file
        is_cursor = absolute_idx == state.cursor_pos

        item_bg =
          cond do
            is_cursor and is_selected -> {80, 100, 80}
            is_cursor -> {50, 50, 60}
            is_selected -> selected_bg
            true -> bg
          end

        item_fg =
          cond do
            item.type == :dir -> {150, 200, 255}
            true -> default_fg
          end

        indent = String.duplicate("  ", item.depth)

        prefix =
          if item.type == :dir do
            if MapSet.member?(state.expanded_dirs, item.path) do
              "▼ "
            else
              "▶ "
            end
          else
            "  "
          end

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

        segment = Segment.new(padded, %{fg: item_fg, bg: item_bg})
        Strip.new([segment])
      end)

    if length(strips) > 0 do
      strips
    else
      empty_line = String.duplicate(" ", rect.width)
      [Strip.new([Segment.new(empty_line, %{fg: default_fg, bg: bg})])]
    end
  end

  @impl Drafter.Widget
  def handle_key(key, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    tree_items = build_tree(state)

    case key do
      :up ->
        new_pos = max(0, state.cursor_pos - 1)

        new_scroll =
          if new_pos < state.scroll_offset do
            state.scroll_offset - 1
          else
            state.scroll_offset
          end

        new_state = %{state | cursor_pos: new_pos, scroll_offset: max(0, new_scroll)}

        actions =
          if new_pos < length(tree_items) do
            item = Enum.at(tree_items, new_pos)
            cursor_actions(new_state, item)
          else
            []
          end

        {:ok, new_state, actions}

      :down ->
        new_pos = min(length(tree_items) - 1, state.cursor_pos + 1)
        last_visible_idx = state.scroll_offset + state.viewport_height - 1

        new_scroll =
          if new_pos > last_visible_idx do
            state.scroll_offset + 1
          else
            state.scroll_offset
          end

        new_state = %{state | cursor_pos: new_pos, scroll_offset: new_scroll}

        actions =
          if new_pos < length(tree_items) do
            item = Enum.at(tree_items, new_pos)
            cursor_actions(new_state, item)
          else
            []
          end

        {:ok, new_state, actions}

      :enter ->
        if state.cursor_pos < length(tree_items) do
          item = Enum.at(tree_items, state.cursor_pos)
          handle_item_selection(state, item)
        else
          {:ok, state}
        end

      :space ->
        if state.cursor_pos < length(tree_items) do
          item = Enum.at(tree_items, state.cursor_pos)

          if item.type == :dir do
            toggle_directory(state, item.path)
          else
            handle_item_selection(state, item)
          end
        else
          {:ok, state}
        end

      :left ->
        {:ok, %{state | h_scroll_offset: max(0, state.h_scroll_offset - 2)}}

      :right ->
        {:ok, %{state | h_scroll_offset: state.h_scroll_offset + 2}}

      _ ->
        {:ok, state}
    end
  end

  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if :scroll not in state.handles do
      {:ok, state}
    else
      tree_items = build_tree(state)
      scroll_amount = 3

      {new_pos, new_scroll} =
        case direction do
          :up ->
            pos = max(0, state.cursor_pos - scroll_amount)

            scroll =
              if pos < state.scroll_offset do
                pos
              else
                state.scroll_offset
              end

            {pos, scroll}

          :down ->
            pos = min(length(tree_items) - 1, state.cursor_pos + scroll_amount)

            scroll =
              if pos >= state.scroll_offset + state.viewport_height do
                pos - state.viewport_height + 1
              else
                state.scroll_offset
              end

            {pos, scroll}
        end

      new_state = %{state | cursor_pos: new_pos, scroll_offset: new_scroll}

      actions =
        if new_pos < length(tree_items) do
          item = Enum.at(tree_items, new_pos)
          cursor_actions(new_state, item)
        else
          []
        end

      {:ok, new_state, actions}
    end
  end

  @impl Drafter.Widget
  def handle_mouse_up(_x, y, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if :mouse_up not in state.handles do
      {:ok, state}
    else
      tree_items = build_tree(state)

      if y < length(tree_items) do
        item = Enum.at(tree_items, y)
        new_state = %{state | cursor_pos: y}
        handle_item_selection(new_state, item)
      else
        {:ok, state}
      end
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | path: Map.get(props, :path, state.path),
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
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
      c when is_binary(c) -> String.to_atom(c)
      c when is_atom(c) -> c
    end)
    base = %{
      path: Keyword.get(opts, :path, File.cwd!()),
      show_hidden: Keyword.get(opts, :show_hidden, false),
      on_select: Drafter.Widget.Callback.wrap_1(Keyword.get(opts, :on_select)),
      on_file_select: Drafter.Widget.Callback.wrap_1(Keyword.get(opts, :on_file_select)),
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

  defp build_tree(state) do
    root_item = %{
      path: state.path,
      type: :dir,
      depth: 0
    }

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
        entries = Enum.sort(entries)

        entries =
          if not show_hidden do
            Enum.reject(entries, fn entry ->
              String.starts_with?(entry, ".")
            end)
          else
            entries
          end

        {dirs, files} =
          Enum.split_with(entries, fn entry ->
            File.dir?(Path.join([path, entry]))
          end)

        dirs_with_children =
          Enum.flat_map(dirs, fn dir ->
            full_path = Path.join([path, dir])

            dir_item = %{
              path: full_path,
              type: :dir,
              depth: depth
            }

            children =
              if MapSet.member?(expanded_dirs, full_path) do
                build_tree_recursive(full_path, expanded_dirs, show_hidden, depth + 1, [])
              else
                []
              end

            [dir_item | children]
          end)

        file_items =
          Enum.map(files, fn file ->
            full_path = Path.join([path, file])

            %{
              path: full_path,
              type: :file,
              depth: depth
            }
          end)

        acc ++ dirs_with_children ++ file_items

      {:error, _} ->
        acc
    end
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
