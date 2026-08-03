defmodule Drafter.Widget.FilePicker do
  @moduledoc """
  A modal file picker screen for selecting files or directories.

  Use `show/1` to open the picker as a modal overlay. Callbacks are delivered
  as app events to the calling screen's `handle_event/3`.

  This module has no `component_tag/0` and no `Drafter.App` helper: it is a
  screen shown by `show/1`, not an element placed in a render tree.

  ## Options

  These are the options `show/1` accepts. It converts them into the props
  `mount/1` receives, so `:path` arrives as `:initial_path`, and `:width` and
  `:height` are applied to the modal frame rather than passed to `mount/1`.

    * `:on_select` - atom event name or one-arity function called with the selected
      path. Default `nil`
    * `:on_cancel` - atom event name, or a function of arity 0 or 1, called when the
      picker is dismissed. Default `nil`
    * `:path` - initial path. Default `Path.expand("~/")`. A file path opens its
      containing directory with that file preselected
    * `:allow_dirs` - `t:boolean/0`, allow selecting directories. Default `false`.
      With it on, the Open button stays enabled and falls back to the directory
      currently shown
    * `:filter` - list of file extensions, e.g. `[".ex", ".exs"]`. Default `nil`.
      Carried on the state but not applied: every file is listed either way
    * `:title` - label for the open button. Default `"Open"`
    * `:width` - modal width in columns. Default `90`
    * `:height` - modal height in rows. Default `26`

  ## Key bindings

  `↑`/`↓` navigate the tree, `Enter` expands a directory or selects a file, `h`
  toggles hidden files, and `Esc` cancels. Pasting text sets the location to the
  first pasted line, stripping a `file://` prefix.

  ## Usage

      FilePicker.show(on_select: :file_picked, on_cancel: :pick_cancelled)
  """

  use Drafter.App
  import Drafter.App, except: [breadcrumb: 1, breadcrumb: 2]

  @sidebar_locations [
    {"Desktop", "~/Desktop"},
    {"Documents", "~/Documents"},
    {"Downloads", "~/Downloads"},
    {"Pictures", "~/Pictures"},
    {"Movies", "~/Movies"},
    {"Music", "~/Music"},
    {"Home", "~/"},
    {"/  (root)", "/"}
  ]

  @type state :: %{
          tree_root: Path.t(),
          selected_path: Path.t() | nil,
          show_hidden: boolean(),
          sidebar: [{String.t(), Path.t()}],
          on_select: (Path.t() -> any()) | nil,
          on_cancel: (any() -> any()) | (-> any()) | nil,
          allow_dirs: boolean(),
          filter: [String.t()] | nil,
          title: String.t()
        }

  @doc """
  Builds the `{:show_modal, module, props, opts}` tuple that opens the picker.

  Return it from a screen's `handle_event/3` or `update/2`. An atom `:on_select` or
  `:on_cancel` is wrapped into a closure that sends `{:app_event, name, data}` to
  the calling process, so `show/1` must be called from the app loop's process.

  See the module documentation for every option and its default.
  """
  @spec show(keyword()) :: {:show_modal, module(), map(), keyword()}
  def show(opts \\ []) do
    session_pid = self()

    on_select =
      case Keyword.get(opts, :on_select) do
        nil -> nil
        f when is_function(f, 1) -> f
        name -> fn data -> send(session_pid, {:app_event, name, data}) end
      end

    on_cancel =
      case Keyword.get(opts, :on_cancel) do
        nil -> nil
        f when is_function(f, 0) -> f
        name -> fn _data -> send(session_pid, {:app_event, name, nil}) end
      end

    props = %{
      on_select: on_select,
      on_cancel: on_cancel,
      initial_path: Keyword.get(opts, :path, Path.expand("~/")),
      allow_dirs: Keyword.get(opts, :allow_dirs, false),
      filter: Keyword.get(opts, :filter, nil),
      title: Keyword.get(opts, :title, "Open")
    }

    modal_opts = [
      width: Keyword.get(opts, :width, 90),
      height: Keyword.get(opts, :height, 26),
      border: true
    ]

    {:show_modal, __MODULE__, props, modal_opts}
  end

  @doc """
  Builds the screen state from the props `show/1` produced.

  `:initial_path` decides the starting location: a directory becomes the tree root
  with nothing selected, and a regular file opens its parent directory with that
  file preselected. The sidebar lists only the standard locations that exist on this
  machine.
  """
  @spec mount(map()) :: state()
  def mount(props) do
    raw_path = Map.get(props, :initial_path, Path.expand("~/"))
    tree_root = if File.dir?(raw_path), do: raw_path, else: Path.dirname(raw_path)
    initial_selected = if File.regular?(raw_path), do: raw_path, else: nil

    %{
      tree_root: tree_root,
      selected_path: initial_selected,
      show_hidden: false,
      sidebar: build_sidebar_items(),
      on_select: Map.get(props, :on_select),
      on_cancel: Map.get(props, :on_cancel),
      allow_dirs: Map.get(props, :allow_dirs, false),
      filter: Map.get(props, :filter),
      title: Map.get(props, :title, "Open")
    }
  end

  @doc """
  The key bindings shown by `Drafter.Widget.Footer` while the picker is on top.

      iex> Drafter.Widget.FilePicker.keybindings()
      [{"↑↓", "navigate"}, {"Enter", "expand/select"}, {"h", "hidden"}, {"Esc", "cancel"}]
  """
  @spec keybindings() :: [{String.t(), String.t()}]
  def keybindings do
    [{"↑↓", "navigate"}, {"Enter", "expand/select"}, {"h", "hidden"}, {"Esc", "cancel"}]
  end

  @doc """
  Builds the picker's element tree: a hidden-files toolbar, a split pane with the
  locations sidebar on the left and the directory tree on the right, and a selection
  line with Cancel and Open buttons at the bottom.

  Open is disabled while nothing is selected, unless `:allow_dirs` is set.
  """
  @spec render(state()) :: tuple()
  def render(state) do
    vertical([
      render_toolbar(state),
      split_pane(
        [
          box(
            [
              option_list(
                state.sidebar,
                id: :fp_sidebar,
                on_select: :fp_location_selected,
                trigger: :mouse_up,
                flex: 1
              )
            ],
            title: "Locations",
            width: 22
          ),
          box(
            [
              directory_tree(
                id: :fp_tree,
                path: state.tree_root,
                show_hidden: state.show_hidden,
                on_file_select: :fp_file_selected,
                on_select: :fp_item_selected,
                flex: 1
              )
            ],
            title: breadcrumb(state.tree_root),
            flex: 1
          )
        ],
        orientation: :horizontal,
        ratio: 0.24,
        flex: 1
      ),
      render_bottom(state)
    ])
  end

  defp render_toolbar(state) do
    hidden_label = if state.show_hidden, do: "◉ show hidden  (h)", else: "○ show hidden  (h)"

    horizontal([
      label(hidden_label, style: %{fg: {120, 120, 150}})
    ])
  end

  defp render_bottom(state) do
    {selected_text, selected_style} =
      case state.selected_path do
        nil -> {"No selection", %{fg: {100, 100, 110}, italic: true}}
        path -> {breadcrumb(path), %{fg: {100, 200, 130}}}
      end

    open_enabled = state.selected_path != nil or state.allow_dirs

    vertical([
      horizontal([
        label("Selected: ", style: %{fg: {140, 140, 160}, bold: true}),
        label(selected_text, style: selected_style)
      ]),
      horizontal([
        label("", flex: 1),
        button("Cancel", on_click: :fp_cancel, compact: true),
        label("  "),
        button(state.title, on_click: :fp_open, compact: true, disabled: not open_enabled)
      ])
    ])
  end

  defp breadcrumb(path) do
    home = Path.expand("~/")

    if String.starts_with?(path, home) do
      "~/" <> Path.relative_to(path, home)
    else
      path
    end
  end

  defp build_sidebar_items do
    @sidebar_locations
    |> Enum.map(fn {label, raw_path} -> {label, Path.expand(raw_path)} end)
    |> Enum.filter(fn {_label, path} -> File.dir?(path) end)
  end

  @doc """
  Handles the app events the picker's own widgets raise.

    * `:fp_file_selected` — records the file as the selection
    * `:fp_item_selected` — records the path as the selection when it is a regular
      file, or a directory with `:allow_dirs` set; otherwise `{:noreply, state}`
    * `:fp_location_selected` — moves the tree to that directory and clears the
      selection
    * `:fp_open` — calls `:on_select` with the selection, or with the current
      directory when `:allow_dirs` is set and nothing is selected, then returns
      `{:pop, {:selected, path}}`. With nothing to open it returns
      `{:noreply, state}`
    * `:fp_cancel` — calls `:on_cancel` and returns `{:pop, :cancelled}`
  """
  @spec handle_event(atom(), term(), state()) ::
          {:ok, state()} | {:noreply, state()} | {:pop, term()}
  def handle_event(:fp_file_selected, path, state) do
    {:ok, %{state | selected_path: path}}
  end

  def handle_event(:fp_item_selected, path, state) when is_binary(path) do
    if selectable?(state, path) do
      {:ok, %{state | selected_path: path}}
    else
      {:noreply, state}
    end
  end

  def handle_event(:fp_location_selected, path, state) when is_binary(path) do
    {:ok, %{state | tree_root: path, selected_path: nil}}
  end

  def handle_event(:fp_open, _data, state) do
    selected =
      cond do
        state.selected_path != nil -> state.selected_path
        state.allow_dirs -> state.tree_root
        true -> nil
      end

    if selected do
      call_callback(state.on_select, selected)
      {:pop, {:selected, selected}}
    else
      {:noreply, state}
    end
  end

  def handle_event(:fp_cancel, _data, state) do
    call_callback(state.on_cancel, nil)
    {:pop, :cancelled}
  end

  @doc """
  Handles raw input events.

  `{:key, :escape}` calls `:on_cancel` and returns `{:pop, :cancelled}`.
  `{:key, :h}` toggles hidden files. A bracketed paste takes the first line, strips
  a `file://` prefix, and moves to that directory, or to the file's parent with the
  file selected; a path that does not exist is ignored. Everything else returns
  `{:noreply, state}`.
  """
  @spec handle_event(tuple(), state()) :: {:ok, state()} | {:noreply, state()} | {:pop, term()}
  def handle_event({:key, :escape}, state) do
    call_callback(state.on_cancel, nil)
    {:pop, :cancelled}
  end

  def handle_event({:key, :h}, state) do
    {:ok, %{state | show_hidden: not state.show_hidden}}
  end

  def handle_event({:bracketed_paste, content}, state) do
    path =
      content
      |> String.trim()
      |> String.split(~r/[\n\r]+/)
      |> List.first("")
      |> String.trim()
      |> String.replace_prefix("file://", "")

    cond do
      File.dir?(path) ->
        {:ok, %{state | tree_root: path, selected_path: nil}}

      File.exists?(path) ->
        {:ok, %{state | tree_root: Path.dirname(path), selected_path: path}}

      true ->
        {:noreply, state}
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp selectable?(state, path) do
    cond do
      File.regular?(path) -> true
      File.dir?(path) -> state.allow_dirs
      true -> false
    end
  end

  defp call_callback(nil, _value), do: :ok
  defp call_callback(cb, value) when is_function(cb, 1), do: cb.(value)
  defp call_callback(cb, _value) when is_function(cb, 0), do: cb.()
end
