defmodule Drafter.Widget.DataTable do
  @moduledoc """
  A full-featured tabular data widget with column headers, sorting, row selection, and scrolling.

  Rows are provided as a list of maps. Each map key corresponds to a column `:key`. Data can be
  pre-sorted at mount time via `:sort_by`. Users can sort any sortable column by clicking its
  header, cycling through ascending → descending → unsorted. Sort direction is indicated by `↑`
  or `↓` in the header; `↕` appears on all sortable columns that are not currently sorted.

  An optional vertical scrollbar is rendered in the rightmost column when the number of rows
  exceeds the visible area. The scrollbar supports click-to-jump and drag-to-scroll. Zebra
  stripes alternate the background colour of odd rows when `:zebra_stripes` is enabled.

  ## Column definition format

  Each column is a map (or shorthand) with the following fields:

    * `:key` — atom matching the map key in each data row (required)
    * `:label` — header display string (required)
    * `:width` — column width in characters, or `:auto` (default: `:auto`)
    * `:align` — cell alignment: `:left` (default), `:center`, or `:right`
    * `:sortable` — whether clicking the header sorts by this column (default: `true`)
    * `:color_fn` — `(raw_value -> {r,g,b} | %{bg: {r,g,b}, fg: {r,g,b}} | nil)` applied to cell colours when not selected

  Shorthand forms are also accepted: `{:key, "Label"}` or just `:key`.

  ## Options

    * `:columns` - list of column definitions (required)
    * `:data` - list of row maps (default: `[]`)
    * `:sort_by` - initial sort: an atom column key (ascending), or `{key, :asc | :desc}`
    * `:selection_mode` - `:none`, `:single` (default), or `:multiple`
    * `:on_select` - `([row] -> term())` called with selected rows when a row is activated
    * `:on_sort` - `(atom(), :asc | :desc -> term())` called after a column sort
    * `:show_header` - render column headers (default: `true`)
    * `:show_cursor` - highlight the current cell column in the header (default: `true`)
    * `:zebra_stripes` - alternate row background colours (default: `true`)
    * `:show_scrollbars` - render a vertical scrollbar when content overflows (default: `true`)
    * `:column_fit_mode` - `:fit` (divide available width equally, default) or `:expand`
      (compute optimal widths from content, allows horizontal overflow)
    * `:mouse_scroll_moves_selection` - when `true`, scrolling moves the cursor row rather
      than scrolling the viewport (default: `true`)
    * `:width` - widget width in columns (default: `80`)
    * `:height` - widget height in rows (default: `20`)
    * `:fixed_columns` - number of left-most columns that do not scroll horizontally (default: `0`)
    * `:sortable` - enable/disable column sorting and sort indicators for the entire table (default: `true`)
    * `:locked` - when `true` (default), dragging a column header resizes it; when `false`, dragging reorders columns
    * `:on_layout_change` - `(%{col_widths: [...], col_order: [...]}) -> term()` called after resize or reorder
    * `:col_widths` - initial list of column widths in display order; used to restore a saved layout
    * `:col_order` - initial list of original column indices in display order; used to restore a saved layout
    * `:cursor_type` - `:row` (default, highlights entire row), `:cell` (highlights only the cell at cursor column),
      `:column` (highlights entire column across all rows), or `:none` (no cursor highlight)
    * `:cell_padding` - number of spaces to pad on each side of cell content (default: `0`)
    * `:on_row_highlight` - `(row :: map() -> term())` called when the cursor moves to a new row
    * `:on_header_select` - `(column_key :: atom() -> term())` called when a column header is clicked

  ## Key bindings

    * `↑` / `↓` — move cursor row up/down
    * `←` / `→` — move cursor column left/right
    * `Home` / `End` — jump to first/last row
    * `Page Up` / `Page Down` — jump by viewport height
    * `Enter` — select the highlighted row and call `:on_select`
    * `Space` — toggle selection in `:multiple` mode; otherwise same as Enter
    * `+` / `-` — widen or narrow the cursor column
    * `Shift+←` / `Shift+→` — reorder the cursor column left or right
    * Mouse click on header — sort by that column (cycles through ascending → descending → unsorted)
    * Mouse drag on header — resize column (when `locked: true`) or reorder column (when `locked: false`)
    * Mouse click on row — select the row
    * Mouse scroll — move cursor row (or scroll viewport when `:mouse_scroll_moves_selection` is `false`)
    * Scrollbar click/drag — jump or drag the viewport position

  ## Usage

      data_table(
        columns: [
          %{key: :name, label: "Name", width: 20},
          %{key: :age, label: "Age", width: 8, align: :right},
          %{key: :city, label: "City"}
        ],
        data: [
          %{name: "Alice", age: 30, city: "Dublin"},
          %{name: "Bob", age: 25, city: "London"}
        ],
        sort_by: {:name, :asc},
        on_select: fn rows -> IO.inspect(rows) end
      )
  """

  use Drafter.Widget,
    handles: [:scroll, :keyboard, :mouse_up, :drag, :hover],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager
  alias Drafter.Widget.Callback

  defstruct [
    :columns,
    :data,
    :cursor_col,
    :sort_column,
    :sort_direction,
    :show_header,
    :show_cursor,
    :zebra_stripes,
    :show_scrollbars,
    :column_fit_mode,
    :width,
    :height,
    :viewport_height,
    :fixed_columns,
    :fixed_col_widths,
    :highlighted_index,
    :selected_indices,
    :selection_mode,
    :sortable,
    :resizable,
    :locked,
    :cursor_type,
    :cell_padding,
    :_unsorted_data,
    :_col_widths,
    :_col_order,
    callbacks: %{
      on_select: nil,
      on_sort: nil,
      on_layout_change: nil,
      on_row_highlight: nil,
      on_header_select: nil
    },
    styles: %{base: %{}, header: %{}, selected: %{}, cursor: %{}},
    drag: %{
      resize_col: nil,
      resize_start_x: nil,
      resize_start_width: nil,
      reorder_col: nil,
      dragging_scrollbar: false,
      hovering_scrollbar: false
    },
    scroll: %{
      offset: 0,
      offset_col: 0,
      mouse_scroll_moves_selection: true,
      mouse_scroll_selects_item: false
    }
  ]

  @type column :: %{
          key: atom(),
          label: String.t(),
          width: pos_integer() | :auto,
          align: :left | :center | :right,
          sortable: boolean(),
          color_fn: (term() -> {byte(), byte(), byte()} | %{bg: tuple(), fg: tuple()} | nil) | nil
        }

  @type row :: map()

  @type selection_mode :: :none | :single | :multiple

  @type sort_direction :: :asc | :desc

  @type t :: %__MODULE__{
          columns: [column()],
          data: [row()],
          cursor_col: non_neg_integer(),
          highlighted_index: integer() | nil,
          selected_indices: MapSet.t(),
          selection_mode: selection_mode(),
          sort_column: atom() | nil,
          sort_direction: sort_direction(),
          callbacks: %{
            on_select: ([row()] -> term()) | nil,
            on_sort: (atom(), sort_direction() -> term()) | nil,
            on_layout_change: (%{col_widths: [pos_integer()], col_order: [non_neg_integer()]} -> term()) | nil,
            on_row_highlight: (row() -> term()) | nil,
            on_header_select: (atom() -> term()) | nil
          },
          styles: %{
            base: Segment.style(),
            header: Segment.style(),
            selected: Segment.style(),
            cursor: Segment.style()
          },
          drag: %{
            resize_col: non_neg_integer() | nil,
            resize_start_x: integer() | nil,
            resize_start_width: integer() | nil,
            reorder_col: non_neg_integer() | nil,
            dragging_scrollbar: boolean(),
            hovering_scrollbar: boolean()
          },
          scroll: %{
            offset: integer(),
            offset_col: non_neg_integer(),
            mouse_scroll_moves_selection: boolean(),
            mouse_scroll_selects_item: boolean()
          },
          show_header: boolean(),
          show_cursor: boolean(),
          zebra_stripes: boolean(),
          show_scrollbars: boolean(),
          column_fit_mode: :fit | :expand,
          width: pos_integer(),
          height: pos_integer(),
          fixed_columns: non_neg_integer(),
          fixed_col_widths: [pos_integer()],
          sortable: boolean(),
          resizable: boolean(),
          locked: boolean(),
          cursor_type: :row | :cell | :column | :none,
          cell_padding: non_neg_integer()
        }

  @impl Drafter.Widget
  def mount(props) do
    columns = Map.get(props, :columns, [])
    data = Map.get(props, :data, [])
    height = Map.get(props, :height, 20)
    selection_mode = Map.get(props, :selection_mode, :single)

    {sorted_data, sort_col, sort_dir} =
      case Map.get(props, :sort_by) do
        {column, direction} when direction in [:asc, :desc] ->
          {sort_data(data, column, direction), column, direction}

        column when is_atom(column) ->
          {sort_data(data, column, :asc), column, :asc}

        _ ->
          {data, nil, :asc}
      end

    _data_height = if Map.get(props, :show_header, true), do: height - 1, else: height

    highlighted_index = if sorted_data != [], do: 0, else: nil
    selected_indices = MapSet.new()

    fixed_columns = Map.get(props, :fixed_columns, 0)

    %__MODULE__{
      columns: normalize_columns(columns),
      data: sorted_data,
      cursor_col: 0,
      highlighted_index: highlighted_index,
      selected_indices: selected_indices,
      selection_mode: selection_mode,
      sort_column: sort_col,
      sort_direction: sort_dir,
      callbacks: %{
        on_select: Map.get(props, :on_select),
        on_sort: Map.get(props, :on_sort),
        on_layout_change: Map.get(props, :on_layout_change),
        on_row_highlight: Map.get(props, :on_row_highlight),
        on_header_select: Map.get(props, :on_header_select)
      },
      styles: %{
        base: Map.get(props, :style, %{fg: {200, 200, 200}, bg: {30, 30, 30}}),
        header: Map.get(props, :header_style, %{fg: {255, 255, 255}, bg: {60, 60, 60}, bold: true}),
        selected: Map.get(props, :selected_style, %{fg: {255, 255, 255}, bg: {0, 120, 215}}),
        cursor: Map.get(props, :cursor_style, %{fg: {255, 255, 255}, bg: {50, 100, 200}, bold: true})
      },
      drag: %{
        resize_col: nil,
        resize_start_x: nil,
        resize_start_width: nil,
        reorder_col: nil,
        dragging_scrollbar: false,
        hovering_scrollbar: false
      },
      scroll: %{
        offset: 0,
        offset_col: 0,
        mouse_scroll_moves_selection: Map.get(props, :mouse_scroll_moves_selection, true),
        mouse_scroll_selects_item: Map.get(props, :mouse_scroll_selects_item, false)
      },
      show_header: Map.get(props, :show_header, true),
      show_cursor: Map.get(props, :show_cursor, true),
      zebra_stripes: Map.get(props, :zebra_stripes, true),
      show_scrollbars: Map.get(props, :show_scrollbars, true),
      column_fit_mode: Map.get(props, :column_fit_mode, :fit),
      width: Map.get(props, :width, 80),
      height: height,
      viewport_height: height,
      fixed_columns: min(fixed_columns, length(columns)),
      fixed_col_widths: [],
      sortable: Map.get(props, :sortable, true),
      resizable: Map.get(props, :resizable, true),
      locked: Map.get(props, :locked, true),
      cursor_type: Map.get(props, :cursor_type, :row),
      cell_padding: Map.get(props, :cell_padding, 0),
      _unsorted_data: data,
      _col_widths: Map.get(props, :col_widths),
      _col_order: Map.get(props, :col_order)
    }
  end

  def on_rect_change(rect, state) do
    %{state | viewport_height: rect.height, width: rect.width}
  end

  defp normalize_state(state) when is_struct(state, __MODULE__), do: state
  defp normalize_state(state), do: mount(state)

  defp table_width(state, content_width, data_height) do
    if state.show_scrollbars && length(state.data) > data_height do
      content_width - 1
    else
      content_width
    end
  end

  defp render_data_strips(state, column_widths, table_width, data_height) do
    start_idx = state.scroll.offset
    visible_count = min(data_height, length(state.data) - start_idx)

    if visible_count > 0 do
      start_idx..(start_idx + visible_count - 1)
      |> Enum.map(fn row_index ->
        render_row(state, Enum.at(state.data, row_index), row_index, column_widths, table_width)
      end)
    else
      []
    end
  end

  defp pad_strips_to_height(strips, content_height, table_width, style) do
    current_height = length(strips)

    if current_height < content_height do
      empty_strip = Strip.new([Segment.new(String.duplicate(" ", table_width), style)])
      strips ++ List.duplicate(empty_strip, content_height - current_height)
    else
      Enum.take(strips, content_height)
    end
  end

  @impl Drafter.Widget
  def render(state, rect) do
    st = state |> normalize_state() |> apply_theme_styles(ThemeManager.get_current_theme())

    content_width = min(st.width, rect.width)
    content_height = st.viewport_height || rect.height
    data_height = get_data_height(st)
    tbl_width = table_width(st, content_width, data_height)
    column_widths = get_column_widths(st, tbl_width)

    header_strips = if st.show_header, do: [render_header(st, column_widths, tbl_width)], else: []
    data_strips = render_data_strips(st, column_widths, tbl_width, data_height)

    final_strips =
      (header_strips ++ data_strips)
      |> pad_strips_to_height(content_height, tbl_width, st.styles.base)

    if st.show_scrollbars && length(st.data) > data_height do
      add_vertical_scrollbar(final_strips, st, content_width, data_height)
    else
      final_strips
    end
  end

  def keybindings do
    [
      {"↑↓", "Scroll"},
      {"Enter", "Select"},
      {"+/-", "Resize col"},
      {"⇧←→", "Reorder col"}
    ]
  end

  @impl Drafter.Widget
  def handle_key(?+, state), do: resize_cursor_col(state, 2)
  def handle_key(?-, state), do: resize_cursor_col(state, -2)
  def handle_key(:+, state), do: resize_cursor_col(state, 2)
  def handle_key(:-, state), do: resize_cursor_col(state, -2)

  def handle_key(:left, state) do
    if focused(state) do
      move_cursor_horizontal(state, :left)
    else
      {:bubble, state}
    end
  end

  def handle_key(:right, state) do
    if focused(state) do
      move_cursor_horizontal(state, :right)
    else
      {:bubble, state}
    end
  end

  def handle_key(:up, state), do: action_cursor_up(state)
  def handle_key(:down, state), do: action_cursor_down(state)
  def handle_key(:home, state), do: action_cursor_first(state)
  def handle_key(:end, state), do: action_cursor_last(state)
  def handle_key(:page_up, state), do: action_page_up(state)
  def handle_key(:page_down, state), do: action_page_down(state)
  def handle_key(:enter, state), do: action_select_highlighted(state)
  def handle_key(:space, state), do: action_toggle_selection(state)
  def handle_key(_key, state), do: {:bubble, state}

  def handle_key(:left, [:shift], state), do: reorder_column(state, state.cursor_col, :left)
  def handle_key(:right, [:shift], state), do: reorder_column(state, state.cursor_col, :right)
  def handle_key(_key, _mods, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    if state.scroll.mouse_scroll_moves_selection do
      case direction do
        :up -> action_cursor_up(state)
        :down -> action_cursor_down(state)
      end
    else
      case direction do
        :up -> action_scroll_up(state)
        :down -> action_scroll_down(state)
      end
    end
  end

  @impl Drafter.Widget
  def handle_mouse_up(x, y, state) do
    was_resizing = state.drag.resize_col != nil
    was_reordering = state.drag.reorder_col != nil

    state = put_in(state.drag, %{state.drag | resize_col: nil, resize_start_x: nil, resize_start_width: nil, reorder_col: nil})

    if was_resizing or was_reordering do
      trigger_layout_change(state)
      {:ok, state}
    else
      handle_mouse_click(state, x, y)
    end
  end

  @impl Drafter.Widget
  def handle_drag(x, _y, state) when state.drag.resize_col != nil do
    do_column_resize(state, x)
  end

  def handle_drag(x, _y, state) when state.drag.reorder_col != nil do
    do_column_reorder(state, x)
  end

  def handle_drag(x, y, state) when y == 0 and state.show_header and state.locked and state.resizable do
    col = calculate_column_from_x(state, x)
    widths = get_column_widths(state, state.width)
    start_width = Enum.at(widths, col, 10)
    {:ok, %{state | drag: %{state.drag | resize_col: col, resize_start_x: x, resize_start_width: start_width}, _col_widths: widths}}
  end

  def handle_drag(x, y, state) when y == 0 and state.show_header and not state.locked do
    col = calculate_column_from_x(state, x)
    widths = get_column_widths(state, state.width)
    col_order = get_col_order_list(state)
    {:ok, %{state | drag: %{state.drag | reorder_col: col}, _col_widths: widths, _col_order: col_order}}
  end

  def handle_drag(x, y, state), do: handle_mouse_drag(state, x, y)

  @impl Drafter.Widget
  def handle_hover(x, y, state) do
    handle_mouse_move(state, x, y)
  end

  @impl Drafter.Widget
  def handle_custom_event({:mouse, %{type: :mouse_up, x: x, y: y}}, state) do
    cond do
      state.drag.resize_col ->
        {:ok, %{state | drag: %{state.drag | resize_col: nil, resize_start_x: nil, resize_start_width: nil}}}

      state.drag.dragging_scrollbar ->
        handle_mouse_release(state, x, y)

      true ->
        handle_mouse_click(state, x, y)
    end
  end

  def handle_custom_event(_event, state), do: {:bubble, state}

  defp updated_col_widths(state, props, col_count_changed) do
    cond do
      col_count_changed -> nil
      state._col_widths == nil and Map.has_key?(props, :col_widths) -> Map.get(props, :col_widths)
      true -> state._col_widths
    end
  end

  defp updated_col_order(state, props) do
    case {Map.fetch(props, :col_order), state._col_order} do
      {{:ok, order}, nil} -> order
      _ -> state._col_order
    end
  end

  defp clamp_highlighted_index(_state, nil), do: nil

  defp clamp_highlighted_index(state, highlighted_index) do
    max_row = max(0, length(state.data) - 1)

    if highlighted_index > max_row do
      min(max_row, highlighted_index)
    else
      highlighted_index
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    new_data = Map.get(props, :data, state.data)
    new_columns = normalize_columns(Map.get(props, :columns, state.columns))

    sorted_data =
      if new_data != state.data && state.sort_column do
        sort_data(new_data, state.sort_column, state.sort_direction)
      else
        new_data
      end

    col_count_changed = length(new_columns) != length(state.columns)

    %{
      state
      | columns: new_columns,
        data: sorted_data,
        highlighted_index: clamp_highlighted_index(%{state | data: sorted_data}, state.highlighted_index),
        selection_mode: Map.get(props, :selection_mode, state.selection_mode),
        callbacks: %{
          on_select: Map.get(props, :on_select, state.callbacks.on_select),
          on_sort: Map.get(props, :on_sort, state.callbacks.on_sort),
          on_layout_change: Map.get(props, :on_layout_change, state.callbacks.on_layout_change),
          on_row_highlight: Map.get(props, :on_row_highlight, state.callbacks.on_row_highlight),
          on_header_select: Map.get(props, :on_header_select, state.callbacks.on_header_select)
        },
        styles: %{
          base: Map.get(props, :style, state.styles.base),
          header: Map.get(props, :header_style, state.styles.header),
          selected: Map.get(props, :selected_style, state.styles.selected),
          cursor: Map.get(props, :cursor_style, state.styles.cursor)
        },
        cursor_type: Map.get(props, :cursor_type, state.cursor_type),
        cell_padding: Map.get(props, :cell_padding, state.cell_padding),
        show_header: Map.get(props, :show_header, state.show_header),
        show_cursor: Map.get(props, :show_cursor, state.show_cursor),
        zebra_stripes: Map.get(props, :zebra_stripes, state.zebra_stripes),
        show_scrollbars: Map.get(props, :show_scrollbars, state.show_scrollbars),
        column_fit_mode: Map.get(props, :column_fit_mode, state.column_fit_mode),
        width: Map.get(props, :width, state.width),
        height: Map.get(props, :height, state.height),
        sortable: Map.get(props, :sortable, state.sortable),
        resizable: Map.get(props, :resizable, state.resizable),
        locked: Map.get(props, :locked, state.locked),
        _unsorted_data: if(Map.has_key?(props, :data), do: new_data, else: state._unsorted_data),
        _col_widths: updated_col_widths(state, props, col_count_changed),
        _col_order: updated_col_order(state, props)
    }
  end

  defp action_scroll_up(state) do
    if state.scroll.offset > 0 do
      new_state = put_in(state.scroll.offset, state.scroll.offset - 1)
      {:ok, new_state, [:render_update]}
    else
      {:ok, state, []}
    end
  end

  defp action_scroll_down(state) do
    data_height = get_data_height(state)
    max_scroll = max(0, length(state.data) - data_height)

    if state.scroll.offset < max_scroll do
      new_state = put_in(state.scroll.offset, state.scroll.offset + 1)
      {:ok, new_state, [:render_update]}
    else
      {:ok, state, []}
    end
  end

  defp action_cursor_up(state) do
    case find_previous_enabled(state.data, get_highlighted_index(state)) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  defp action_cursor_down(state) do
    case find_next_enabled(state.data, get_highlighted_index(state)) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  defp action_cursor_first(state) do
    case find_first_enabled(state.data) do
      nil -> {:ok, state, []}
      new_index -> change_selection(state, new_index, false)
    end
  end

  defp action_cursor_last(state) do
    new_index = find_last_enabled(state.data)
    change_selection(state, new_index, false)
  end

  defp action_page_up(state) do
    current = get_highlighted_index(state) || 0
    data_height = get_data_height(state)
    target_index = max(0, current - data_height)

    new_index =
      case find_previous_enabled_from(state.data, target_index) do
        nil -> find_next_enabled_from(state.data, target_index) || find_first_enabled(state.data)
        index -> index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:ok, state, []}
    end
  end

  defp action_page_down(state) do
    current = get_highlighted_index(state) || 0
    data_height = get_data_height(state)
    target_index = min(length(state.data) - 1, current + data_height)

    new_index =
      case find_next_enabled_from(state.data, target_index) do
        nil ->
          find_previous_enabled_from(state.data, target_index) || find_last_enabled(state.data)

        index ->
          index
      end

    if new_index do
      change_selection(state, new_index, false)
    else
      {:ok, state, []}
    end
  end

  defp action_select_highlighted(state) do
    if highlighted_index = get_highlighted_index(state) do
      change_selection(state, highlighted_index, true)
    else
      {:ok, state, []}
    end
  end

  defp toggle_multiple_selection(state, highlighted_index) do
    new_selected =
      if selected?(state, highlighted_index),
        do: MapSet.delete(state.selected_indices, highlighted_index),
        else: MapSet.put(state.selected_indices, highlighted_index)

    new_state = %{state | selected_indices: new_selected}
    actions = fire_on_select(state.callbacks.on_select, new_state, state.data)

    if actions != [] do
      {:ok, new_state, actions}
    else
      {:ok, new_state}
    end
  end

  defp action_toggle_selection(state) do
    case get_highlighted_index(state) do
      nil ->
        {:ok, state}

      highlighted_index when state.selection_mode == :multiple ->
        toggle_multiple_selection(state, highlighted_index)

      highlighted_index ->
        change_selection(state, highlighted_index, true)
    end
  end

  defp move_cursor_horizontal(%{cursor_col: col} = state, :left) when col > 0 do
    new_state = %{state | cursor_col: col - 1} |> adjust_scroll_horizontal()
    {:ok, new_state, [:render_update]}
  end

  defp move_cursor_horizontal(state, :left), do: {:noreply, state}

  defp move_cursor_horizontal(%{cursor_col: col, columns: columns} = state, :right)
       when col < length(columns) - 1 do
    new_state = %{state | cursor_col: col + 1} |> adjust_scroll_horizontal()
    {:ok, new_state, [:render_update]}
  end

  defp move_cursor_horizontal(state, :right), do: {:noreply, state}

  defp handle_mouse_click(%{show_header: true} = state, x, 0) do
    handle_header_click(state, x)
  end

  defp handle_mouse_click(state, x, y) do
    click_region = determine_click_region(state, x, y)
    handle_click_by_region(state, x, y, click_region)
  end

  defp determine_click_region(state, x, y) do
    data_start_y = get_data_start_y(state)
    data_height = get_data_height(state)
    scrollbar_x = state.width - 1

    classify_click_region(state, x, y, scrollbar_x, data_start_y, data_height)
  end

  defp classify_click_region(
         %{show_scrollbars: true} = state,
         x,
         y,
         scrollbar_x,
         data_start_y,
         data_height
       )
       when x == scrollbar_x and y >= data_start_y and length(state.data) > data_height do
    :scrollbar
  end

  defp classify_click_region(_state, _x, y, _scrollbar_x, data_start_y, _data_height)
       when y >= data_start_y, do: :data_row

  defp classify_click_region(_state, _x, _y, _scrollbar_x, _data_start_y, _data_height),
    do: :other

  defp handle_click_by_region(state, _x, y, :scrollbar) do
    data_start_y = get_data_start_y(state)
    data_height = get_data_height(state)
    handle_scrollbar_click(state, y - data_start_y, data_height)
  end

  defp handle_click_by_region(state, x, y, :data_row) do
    data_start_y = get_data_start_y(state)
    data_y = y - data_start_y
    clicked_index = state.scroll.offset + data_y

    if clicked_index >= 0 and clicked_index < length(state.data) do
      {:ok, updated_state, actions} = change_selection(state, clicked_index, true)
      final_state = update_cursor_column(updated_state, x)
      {:ok, final_state, actions}
    else
      {:noreply, state}
    end
  end

  defp handle_click_by_region(state, _x, _y, :other) do
    {:noreply, state}
  end

  defp drag_scrollbar_to(state, _x, y) do
    data_start_y = get_data_start_y(state)
    data_height = get_data_height(state)
    relative_y = y - data_start_y |> max(0) |> min(data_height - 1)
    total_rows = length(state.data)

    if total_rows > data_height do
      scroll_range = max(1, data_height - 1)
      drag_ratio = relative_y / scroll_range
      target_scroll = Drafter.ScrollMath.from_ratio(drag_ratio, total_rows, data_height)
      {:ok, put_in(state.scroll.offset, target_scroll), [:render_update]}
    else
      {:ok, state}
    end
  end

  defp handle_mouse_drag(state, _x, _y) when state.drag.dragging_scrollbar == false, do: {:noreply, state}

  defp handle_mouse_drag(state, x, y) do
    case determine_click_region(state, x, y) do
      :scrollbar -> drag_scrollbar_to(state, x, y)
      _ -> {:ok, put_in(state.drag.dragging_scrollbar, false), [:render_update]}
    end
  end

  defp handle_mouse_release(state, _x, _y) do
    {:ok, put_in(state.drag.dragging_scrollbar, false), [:render_update]}
  end

  defp handle_mouse_move(state, x, y) do
    region = determine_click_region(state, x, y)
    hovering_scrollbar = region == :scrollbar

    if hovering_scrollbar != state.drag.hovering_scrollbar do
      {:ok, put_in(state.drag.hovering_scrollbar, hovering_scrollbar), [:render_update]}
    else
      {:noreply, state}
    end
  end

  defp update_cursor_column(state, x) do
    col_index = calculate_column_from_x(state, x)
    update_cursor_column_if_valid(state, col_index)
  end

  defp update_cursor_column_if_valid(state, col_index)
       when col_index >= 0 and col_index < length(state.columns) do
    %{state | cursor_col: col_index}
  end

  defp update_cursor_column_if_valid(state, _col_index), do: state

  defp get_data_start_y(%{show_header: true}), do: 1
  defp get_data_start_y(_state), do: 0

  defp get_data_height(%{show_header: true, viewport_height: vh}) when is_integer(vh) and vh > 0,
    do: vh - 1

  defp get_data_height(%{show_header: true, height: height}), do: height - 1
  defp get_data_height(%{viewport_height: vh}) when is_integer(vh) and vh > 0, do: vh
  defp get_data_height(%{height: height}), do: height

  defp cycle_sort(state, column_key) do
    cond do
      state.sort_column != column_key ->
        {:asc, sort_data(state._unsorted_data, column_key, :asc), column_key}

      state.sort_direction == :asc ->
        {:desc, sort_data(state._unsorted_data, column_key, :desc), column_key}

      true ->
        {:asc, state._unsorted_data, nil}
    end
  end

  defp apply_sort(state, column, col_index) do
    {new_direction, new_data, new_sort_col} = cycle_sort(state, column.key)

    new_state = %{
      state
      | data: new_data,
        sort_column: new_sort_col,
        sort_direction: new_direction,
        cursor_col: col_index
    }

    trigger_sort(new_state)
    {:ok, new_state}
  end

  defp handle_header_click(state, x) do
    col_index = calculate_column_from_x(state, x)

    if col_index < length(state.columns) do
      column = Enum.at(get_ordered_columns(state), col_index)

      if state.callbacks.on_header_select, do: state.callbacks.on_header_select.(column.key)

      if state.sortable && column.sortable do
        apply_sort(state, column, col_index)
      else
        {:ok, %{state | cursor_col: col_index}}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_scrollbar_click(state, relative_y, data_height) do
    total_rows = length(state.data)

    if total_rows > data_height do
      scroll_range = max(1, data_height - 1)
      click_ratio = relative_y / scroll_range
      target_scroll = Drafter.ScrollMath.from_ratio(click_ratio, total_rows, data_height)

      new_state = %{
        state
        | scroll: %{state.scroll | offset: target_scroll},
          drag: %{state.drag | dragging_scrollbar: true, hovering_scrollbar: true}
      }

      {:ok, new_state, [:render_update]}
    else
      {:noreply, state}
    end
  end

  defp header_sort_indicator(state, column, width) when state.sortable and column.sortable and width > 1 do
    char = sort_indicator_char(state, column.key)
    {width - 1, char}
  end

  defp header_sort_indicator(_state, _column, width), do: {width, ""}

  defp sort_indicator_char(%{sort_column: key, sort_direction: :asc}, key), do: "↑"
  defp sort_indicator_char(%{sort_column: key, sort_direction: :desc}, key), do: "↓"
  defp sort_indicator_char(_state, _key), do: "↕"

  defp header_cell_cursor?(state, col_index) do
    focused(state) and col_index == state.cursor_col and state.cursor_type != :none and state.show_cursor
  end

  defp header_segment(state, column, width, col_index) do
    {label_width, indicator} = header_sort_indicator(state, column, width)
    formatted_text = format_cell_content(column.label, label_width, column.align, 0) <> indicator

    style =
      if header_cell_cursor?(state, col_index) do
        Map.merge(state.styles.header, state.styles.cursor)
      else
        state.styles.header
      end

    Segment.new(formatted_text, style)
  end

  defp render_header(state, column_widths, total_width) do
    segments =
      get_ordered_columns(state)
      |> Enum.zip(column_widths)
      |> Enum.with_index()
      |> Enum.map(fn {{column, width}, col_index} ->
        header_segment(state, column, width, col_index)
      end)

    current_width = Enum.sum(column_widths)

    segments =
      if current_width < total_width do
        padding = String.duplicate(" ", total_width - current_width)
        segments ++ [Segment.new(padding, state.styles.header)]
      else
        segments
      end

    Strip.new(segments)
  end

  defp row_base_style(state, is_selected, is_zebra) do
    cond do
      is_selected -> state.styles.selected
      is_zebra -> Map.merge(state.styles.base, %{bg: adjust_color(state.styles.base.bg, -10)})
      true -> state.styles.base
    end
  end

  defp apply_color_fn(base_style, _raw_value, nil), do: base_style

  defp apply_color_fn(base_style, raw_value, color_fn) do
    case color_fn.(raw_value) do
      nil -> base_style
      %{bg: bg, fg: fg} -> base_style |> Map.put(:bg, bg) |> Map.put(:fg, fg)
      color -> Map.put(base_style, :bg, color)
    end
  end

  defp cursor_highlights_cell?(%{cursor_type: :row} = state, _col_index, is_highlighted) do
    is_highlighted and focused(state)
  end

  defp cursor_highlights_cell?(%{cursor_type: :cell} = state, col_index, is_highlighted) do
    is_highlighted and col_index == state.cursor_col and focused(state)
  end

  defp cursor_highlights_cell?(%{cursor_type: :column} = state, col_index, _is_highlighted) do
    col_index == state.cursor_col and focused(state)
  end

  defp cursor_highlights_cell?(_state, _col_index, _is_highlighted), do: false

  defp cell_style(state, base_style, raw_value, column, col_index, is_selected, is_highlighted) do
    cond do
      is_selected -> base_style
      cursor_highlights_cell?(state, col_index, is_highlighted) -> state.styles.cursor
      true -> apply_color_fn(base_style, raw_value, Map.get(column, :color_fn))
    end
  end

  defp render_row(state, row, row_index, column_widths, total_width) do
    is_selected = MapSet.member?(state.selected_indices, row_index)
    is_highlighted = state.highlighted_index == row_index
    is_zebra = state.zebra_stripes && rem(row_index, 2) == 1
    base_style = row_base_style(state, is_selected, is_zebra)

    segments =
      get_ordered_columns(state)
      |> Enum.zip(column_widths)
      |> Enum.with_index()
      |> Enum.map(fn {{column, width}, col_index} ->
        raw_value = Map.get(row, column.key, "")
        formatted_text = format_cell_content(to_string(raw_value), width, column.align, state.cell_padding)
        style = cell_style(state, base_style, raw_value, column, col_index, is_selected, is_highlighted)
        Segment.new(formatted_text, style)
      end)

    current_width = Enum.sum(column_widths)

    segments =
      if current_width < total_width do
        padding = String.duplicate(" ", total_width - current_width)
        segments ++ [Segment.new(padding, state.styles.base)]
      else
        segments
      end

    Strip.new(segments)
  end

  defp normalize_columns(columns) do
    Enum.map(columns, fn
      %{} = col ->
        Map.merge(%{width: :auto, align: :left, sortable: true, color_fn: nil}, col)

      {key, label} ->
        %{key: key, label: label, width: :auto, align: :left, sortable: true, color_fn: nil}

      key when is_atom(key) ->
        %{
          key: key,
          label: to_string(key),
          width: :auto,
          align: :left,
          sortable: true,
          color_fn: nil
        }
    end)
  end

  defp distribute_remainder(widths, 0), do: widths

  defp distribute_remainder(widths, remainder) do
    {first_part, rest} = Enum.split(widths, remainder)
    Enum.map(first_part, &(&1 + 1)) ++ rest
  end

  defp calculate_column_widths([], _total_width, _fit_mode, _data), do: []

  defp calculate_column_widths(columns, total_width, :fit, _data) do
    col_count = length(columns)
    base_width = div(total_width, col_count)
    remainder = rem(total_width, col_count)
    List.duplicate(base_width, col_count) |> distribute_remainder(remainder)
  end

  defp calculate_column_widths(columns, total_width, :expand, data) do
    calculate_content_based_widths(columns, data, total_width)
  end

  defp optimal_column_width(column, data) do
    header_width = String.length(column.label) + 2

    content_width =
      data
      |> Enum.take(20)
      |> Enum.map(fn row -> Map.get(row, column.key, "") |> to_string() |> String.length() end)
      |> Enum.max(fn -> 0 end)

    width = max(header_width, content_width)
    max(8, min(30, width))
  end

  defp expand_widths_to_fill(optimal_widths, min_total_width) do
    total_optimal = Enum.sum(optimal_widths)

    if total_optimal < min_total_width do
      extra_space = min_total_width - total_optimal
      extra_per_col = div(extra_space, length(optimal_widths))
      remainder = rem(extra_space, length(optimal_widths))
      Enum.map(optimal_widths, &(&1 + extra_per_col)) |> distribute_remainder(remainder)
    else
      optimal_widths
    end
  end

  defp calculate_content_based_widths(columns, data, min_total_width) do
    optimal_widths = Enum.map(columns, &optimal_column_width(&1, data))
    expand_widths_to_fill(optimal_widths, min_total_width)
  end

  defp format_cell_content(content, width, align, cell_padding) when width > 0 do
    pad = String.duplicate(" ", cell_padding)
    inner_width = max(0, width - 2 * cell_padding)

    truncated =
      if String.length(content) > inner_width do
        String.slice(content, 0, max(0, inner_width - 1)) <> "…"
      else
        content
      end

    aligned =
      case align do
        :left ->
          String.pad_trailing(truncated, inner_width)

        :right ->
          String.pad_leading(truncated, inner_width)

        :center ->
          total_padding = inner_width - String.length(truncated)
          left_padding = div(total_padding, 2)
          right_padding = total_padding - left_padding
          String.duplicate(" ", left_padding) <> truncated <> String.duplicate(" ", right_padding)
      end

    pad <> aligned <> pad
  end

  defp format_cell_content(_content, _width, _align, _cell_padding), do: ""

  defp calculate_column_from_x(state, x) do
    column_widths = get_column_widths(state, state.width)

    {col_index, _} =
      column_widths
      |> Enum.with_index()
      |> Enum.reduce_while({0, 0}, fn {width, col_index}, {current_x, _} ->
        if x >= current_x && x < current_x + width do
          {:halt, {col_index, current_x}}
        else
          {:cont, {current_x + width, col_index}}
        end
      end)

    col_index
  end

  defp fixed_col_widths_for(state, fixed_cols) do
    Enum.slice(state.columns, 0, fixed_cols)
    |> Enum.map(fn col -> if col.width == :auto, do: 10, else: col.width end)
  end

  defp compute_scroll_offset(state, fixed_cols, num_scrollable, remaining_width) when remaining_width > 0 do
    avg_col_width = div(remaining_width, num_scrollable)
    visible_cols = div(remaining_width - 1, avg_col_width + 1) + 1
    offset = max(0, state.cursor_col - fixed_cols - visible_cols + 1)

    if state.cursor_col < fixed_cols do
      0
    else
      min(offset, max(0, num_scrollable - visible_cols))
    end
  end

  defp compute_scroll_offset(_state, _fixed_cols, _num_scrollable, _remaining_width), do: 0

  defp adjust_scroll_horizontal(state) do
    fixed_cols = state.fixed_columns

    if length(state.columns) <= fixed_cols do
      state
    else
      num_scrollable = length(state.columns) - fixed_cols

      if num_scrollable == 0 do
        state
      else
        fixed_widths = fixed_col_widths_for(state, fixed_cols)
        fixed_width = Enum.sum(fixed_widths) + length(fixed_widths) - 1
        remaining_width = max(0, state.width - fixed_width)
        offset = compute_scroll_offset(state, fixed_cols, num_scrollable, remaining_width)
        %{state | scroll: %{state.scroll | offset_col: offset}, fixed_col_widths: fixed_widths}
      end
    end
  end

  defp sort_data(data, column_key, direction) do
    sorted =
      Enum.sort_by(data, fn row ->
        Map.get(row, column_key, "")
      end)

    if direction == :desc do
      Enum.reverse(sorted)
    else
      sorted
    end
  end

  defp adjust_color({r, g, b}, adjustment) do
    {
      max(0, min(255, r + adjustment)),
      max(0, min(255, g + adjustment)),
      max(0, min(255, b + adjustment))
    }
  end

  defp adjust_color(color, _adjustment), do: color

  defp scrollbar_thumb_position(state, data_start_y, data_height) do
    max_scroll = length(state.data) - data_height

    cond do
      max_scroll <= 0 ->
        data_start_y

      state.scroll.offset >= max_scroll ->
        data_start_y + data_height - 1

      true ->
        scroll_ratio = state.scroll.offset / max_scroll
        pos = round(scroll_ratio * (data_height - 1))
        data_start_y + pos
    end
  end

  defp scrollbar_char_at(index, scrollbar_pos, data_start_y) do
    cond do
      index == scrollbar_pos -> "█"
      index >= data_start_y -> "│"
      true -> " "
    end
  end

  defp scrollbar_style_at(index, scrollbar_pos, hovering) do
    cond do
      index == scrollbar_pos and hovering -> %{fg: {255, 255, 255}, bg: {0, 150, 255}}
      index == scrollbar_pos -> %{fg: {200, 200, 200}, bg: {100, 100, 100}}
      true -> %{fg: {100, 100, 100}, bg: {60, 60, 60}}
    end
  end

  defp append_scrollbar_segment(strip, index, scrollbar_pos, data_start_y, hovering) do
    char = scrollbar_char_at(index, scrollbar_pos, data_start_y)
    style = scrollbar_style_at(index, scrollbar_pos, hovering)
    segment = Segment.new(char, style)
    existing = strip.segments || []
    Strip.new(existing ++ [segment])
  end

  defp add_vertical_scrollbar(strips, state, _total_width, data_height) do
    total_rows = length(state.data)

    if total_rows > data_height do
      data_start_y = get_data_start_y(state)
      scrollbar_pos = scrollbar_thumb_position(state, data_start_y, data_height)

      strips
      |> Enum.with_index()
      |> Enum.map(fn {strip, index} ->
        append_scrollbar_segment(strip, index, scrollbar_pos, data_start_y, state.drag.hovering_scrollbar)
      end)
    else
      strips
    end
  end

  defp get_highlighted_index(state), do: state.highlighted_index

  defp selected?(state, index), do: MapSet.member?(state.selected_indices, index)

  defp apply_selection_update(state, _target_index, :none), do: state

  defp apply_selection_update(state, target_index, :single) do
    new_selected =
      if selected?(state, target_index),
        do: MapSet.new(),
        else: MapSet.new([target_index])

    %{state | selected_indices: new_selected}
  end

  defp apply_selection_update(state, target_index, :multiple) do
    new_selected =
      if selected?(state, target_index),
        do: MapSet.delete(state.selected_indices, target_index),
        else: MapSet.put(state.selected_indices, target_index)

    %{state | selected_indices: new_selected}
  end

  defp fire_on_select(nil, _new_state, _data), do: []

  defp fire_on_select(on_select, new_state, data) do
    selected_items =
      new_state.selected_indices
      |> MapSet.to_list()
      |> Enum.map(fn index -> Enum.at(data, index) end)
      |> Enum.filter(& &1)

    [on_select.(selected_items)]
  end

  defp change_selection(state, target_index, trigger_select) do
    if target_index >= 0 and target_index < length(state.data) do
      new_state =
        %{state | highlighted_index: target_index}
        |> ensure_visible_index(target_index, get_data_height(state))

      if state.callbacks.on_row_highlight && target_index != state.highlighted_index do
        row = Enum.at(state.data, target_index)
        state.callbacks.on_row_highlight.(row)
      end

      new_state =
        if trigger_select do
          apply_selection_update(new_state, target_index, state.selection_mode)
        else
          new_state
        end

      select_actions =
        if trigger_select do
          fire_on_select(state.callbacks.on_select, new_state, state.data)
        else
          []
        end

      {:ok, new_state, [:render_update | select_actions]}
    else
      {:ok, state, []}
    end
  end

  defp ensure_visible_index(state, target_index, visible_height) do
    cond do
      target_index < state.scroll.offset ->
        put_in(state.scroll.offset, target_index)

      target_index >= state.scroll.offset + visible_height ->
        new_offset = target_index - visible_height + 1
        put_in(state.scroll.offset, max(0, new_offset))

      true ->
        state
    end
  end

  defp find_first_enabled(data) do
    Enum.find_index(data, fn _row -> true end)
  end

  defp find_last_enabled(data) do
    length(data) - 1
  end

  defp find_next_enabled(data, current_index) do
    start_index = if current_index, do: current_index + 1, else: 0
    if start_index < length(data), do: start_index, else: nil
  end

  defp find_previous_enabled(_data, current_index) do
    if current_index && current_index > 0, do: current_index - 1, else: nil
  end

  defp find_next_enabled_from(data, start_index) do
    if start_index && start_index < length(data) - 1, do: start_index, else: nil
  end

  defp find_previous_enabled_from(_data, end_index) do
    if end_index && end_index > 0, do: end_index, else: nil
  end

  defp trigger_sort(state) do
    if state.callbacks.on_sort do
      try do
        state.callbacks.on_sort.(state.sort_column, state.sort_direction)
      rescue
        _error -> :ok
      end
    end
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, :auto)

  def component_tag, do: :data_table

  def from_component_opts(_args, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 80, height: 20})
    theme = Keyword.get(opts, :__theme__)
    custom_styles = Keyword.get(opts, :styles, %{})

    base = %{
      columns: Keyword.get(opts, :columns, []),
      data: Keyword.get(opts, :data, []),
      sort_by: Keyword.get(opts, :sort_by),
      selection_mode: Keyword.get(opts, :selection_mode, :single),
      show_header: Keyword.get(opts, :show_header, true),
      show_cursor: Keyword.get(opts, :show_cursor, true),
      zebra_stripes: Keyword.get(opts, :zebra_stripes, true),
      show_scrollbars: Keyword.get(opts, :show_scrollbars, true),
      column_fit_mode: Keyword.get(opts, :column_fit_mode, :fit),
      mouse_scroll_moves_selection: Keyword.get(opts, :mouse_scroll_moves_selection, true),
      width: Keyword.get(opts, :width, rect.width),
      height:
        case Keyword.get(opts, :height, rect.height) do
          :auto -> 8
          h -> h
        end,
      fixed_columns: Keyword.get(opts, :fixed_columns, 0),
      sortable: Keyword.get(opts, :sortable, true),
      locked: Keyword.get(opts, :locked, true),
      col_widths: Keyword.get(opts, :col_widths),
      col_order: Keyword.get(opts, :col_order),
      cursor_type: Keyword.get(opts, :cursor_type, :row),
      cell_padding: Keyword.get(opts, :cell_padding, 0),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select)),
      on_sort: Callback.wrap_2(Keyword.get(opts, :on_sort)),
      on_layout_change: Callback.wrap_1(Keyword.get(opts, :on_layout_change)),
      on_row_highlight: Callback.wrap_1(Keyword.get(opts, :on_row_highlight)),
      on_header_select: Callback.wrap_1(Keyword.get(opts, :on_header_select))
    }

    if theme do
      Map.merge(base, %{
        style: Map.get(custom_styles, :style, %{fg: theme.text_primary, bg: theme.background}),
        header_style:
          Map.get(custom_styles, :header_style, %{
            fg: theme.text_primary,
            bg: theme.surface,
            bold: true
          }),
        selected_style:
          Map.get(custom_styles, :selected_style, %{fg: theme.text_primary, bg: theme.primary}),
        cursor_style:
          Map.get(custom_styles, :cursor_style, %{
            fg: theme.text_primary,
            bg: theme.primary,
            bold: true
          })
      })
    else
      base
    end
  end

  def update_props_from_mount(mount_props, existing_state, _opts) do
    base = %{
      on_select: mount_props.on_select,
      on_sort: mount_props.on_sort,
      on_layout_change: mount_props.on_layout_change,
      on_row_highlight: mount_props.on_row_highlight,
      on_header_select: mount_props.on_header_select,
      columns: mount_props.columns,
      data: mount_props.data,
      selection_mode: mount_props.selection_mode,
      sortable: mount_props.sortable,
      locked: mount_props.locked,
      cursor_type: mount_props.cursor_type,
      cell_padding: mount_props.cell_padding,
      fixed_columns: mount_props.fixed_columns
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
      | styles: %{
          base: %{fg: theme.text_primary, bg: theme.background},
          header: %{fg: theme.text_primary, bg: theme.surface, bold: true},
          selected: %{fg: theme.text_primary, bg: theme.primary},
          cursor: %{fg: theme.text_primary, bg: theme.primary, bold: true}
        }
    }
  end

  defp get_column_widths(state, table_width) do
    state._col_widths ||
      calculate_column_widths(state.columns, table_width, state.column_fit_mode, state.data)
  end

  defp do_column_resize(state, x) do
    delta = x - state.drag.resize_start_x
    new_width = max(3, state.drag.resize_start_width + delta)
    new_col_widths = List.replace_at(state._col_widths, state.drag.resize_col, new_width)
    {:ok, %{state | _col_widths: new_col_widths}, [:render_update]}
  end

  defp resize_cursor_col(state, delta) do
    col = state.cursor_col
    widths = get_column_widths(state, state.width)
    current = Enum.at(widths, col, 10)
    new_width = max(3, current + delta)
    new_col_widths = List.replace_at(widths, col, new_width)
    new_state = %{state | _col_widths: new_col_widths}
    trigger_layout_change(new_state)
    {:ok, new_state, [:render_update]}
  end

  defp get_ordered_columns(state) do
    case state._col_order do
      nil -> state.columns
      order -> Enum.map(order, &Enum.at(state.columns, &1))
    end
  end

  defp get_col_order_list(state) do
    count = length(state.columns)
    state._col_order || if count > 0, do: Enum.to_list(0..(count - 1)), else: []
  end

  defp do_column_reorder(state, x) do
    target_col = calculate_column_from_x(state, x)
    source_col = state.drag.reorder_col

    if target_col != source_col do
      new_col_order = swap_in_list(state._col_order, source_col, target_col)
      new_col_widths = swap_in_list(state._col_widths, source_col, target_col)

      new_state = %{
        state
        | _col_order: new_col_order,
          _col_widths: new_col_widths,
          drag: %{state.drag | reorder_col: target_col},
          cursor_col: target_col
      }

      {:ok, new_state, [:render_update]}
    else
      {:ok, state}
    end
  end

  defp reorder_column(state, display_col, :left) when display_col > 0 do
    widths = get_column_widths(state, state.width)
    col_order = get_col_order_list(state)
    new_col_order = swap_in_list(col_order, display_col, display_col - 1)
    new_col_widths = swap_in_list(widths, display_col, display_col - 1)

    new_state = %{
      state
      | _col_order: new_col_order,
        _col_widths: new_col_widths,
        cursor_col: display_col - 1
    }

    trigger_layout_change(new_state)
    {:ok, new_state, [:render_update]}
  end

  defp reorder_column(state, _display_col, :left), do: {:ok, state}

  defp reorder_column(state, display_col, :right) when display_col < length(state.columns) - 1 do
    widths = get_column_widths(state, state.width)
    col_order = get_col_order_list(state)
    new_col_order = swap_in_list(col_order, display_col, display_col + 1)
    new_col_widths = swap_in_list(widths, display_col, display_col + 1)

    new_state = %{
      state
      | _col_order: new_col_order,
        _col_widths: new_col_widths,
        cursor_col: display_col + 1
    }

    trigger_layout_change(new_state)
    {:ok, new_state, [:render_update]}
  end

  defp reorder_column(state, _display_col, :right), do: {:ok, state}

  defp swap_in_list(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end

  defp trigger_layout_change(state) do
    if state.callbacks.on_layout_change do
      col_widths = get_column_widths(state, state.width)
      col_order = get_col_order_list(state)
      state.callbacks.on_layout_change.(%{col_widths: col_widths, col_order: col_order})
    end
  end
end
