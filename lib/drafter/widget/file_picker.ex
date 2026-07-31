defmodule Drafter.Widget.FilePicker do
  @moduledoc """
  A modal file picker screen for selecting files or directories.

  Use `show/1` to open the picker as a modal overlay. Callbacks are delivered
  as app events to the calling screen's `handle_event/3`.

  ## Options

    * `:on_select` - atom or function called with the selected path
    * `:on_cancel` - atom or function called when the picker is dismissed
    * `:path` - initial directory path (default: `~/`)
    * `:allow_dirs` - allow selecting directories (default: `false`)
    * `:filter` - list of file extensions to show, e.g. `[".ex", ".exs"]`
    * `:title` - label for the open button (default: `"Open"`)
    * `:width` - modal width in columns (default: `90`)
    * `:height` - modal height in rows (default: `26`)

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

  def keybindings do
    [{"↑↓", "navigate"}, {"Enter", "expand/select"}, {"h", "hidden"}, {"Esc", "cancel"}]
  end

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
