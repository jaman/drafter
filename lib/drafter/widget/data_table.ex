defmodule Drafter.Widget.DataTable do
  @moduledoc """
  A full-featured tabular data widget with column headers, sorting, row selection, and scrolling.

  Rows are provided as a list of maps. Each map key corresponds to a column `:key`. Data can be
  pre-sorted at mount time via `:sort_by`. Users can sort any sortable column by clicking its
  header, cycling through ascending -> descending -> unsorted. Sort direction is indicated by `↑`
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
    * Mouse click on header — sort by that column (cycles through ascending -> descending -> unsorted)
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
    traits: [:focusable],
    handles: [:scroll, :keyboard, :mouse_up, :drag, :hover]

  alias Drafter.ThemeManager
  alias Drafter.Widget.Callback
  alias __MODULE__.{Columns, Rendering, Selection, Sorting}

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
            base: map(),
            header: map(),
            selected: map(),
            cursor: map()
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

  def get_data_start_y(%{show_header: true}), do: 1
  def get_data_start_y(_state), do: 0

  def get_data_height(%{show_header: true, viewport_height: vh}) when is_integer(vh) and vh > 0,
    do: vh - 1

  def get_data_height(%{show_header: true, height: height}), do: height - 1
  def get_data_height(%{viewport_height: vh}) when is_integer(vh) and vh > 0, do: vh
  def get_data_height(%{height: height}), do: height

  @impl Drafter.Widget
  def mount(props) do
    columns = Map.get(props, :columns, [])
    data = Map.get(props, :data, [])
    height = Map.get(props, :height, 20)
    selection_mode = Map.get(props, :selection_mode, :single)

    {sorted_data, sort_col, sort_dir} =
      case Map.get(props, :sort_by) do
        {column, direction} when direction in [:asc, :desc] ->
          {Sorting.sort_data(data, column, direction), column, direction}

        column when is_atom(column) ->
          {Sorting.sort_data(data, column, :asc), column, :asc}

        _ ->
          {data, nil, :asc}
      end

    _data_height = if Map.get(props, :show_header, true), do: height - 1, else: height

    highlighted_index = if sorted_data != [], do: 0, else: nil
    selected_indices = MapSet.new()

    fixed_columns = Map.get(props, :fixed_columns, 0)

    %__MODULE__{
      columns: Columns.normalize_columns(columns),
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

  @impl Drafter.Widget
  def render(state, rect) do
    st = state |> Rendering.normalize_state() |> Rendering.apply_theme_styles(ThemeManager.get_current_theme())

    content_width = min(st.width, rect.width)
    content_height = st.viewport_height || rect.height
    data_height = get_data_height(st)
    tbl_width = Rendering.table_width(st, content_width, data_height)
    column_widths = Columns.get_column_widths(st, tbl_width)

    header_strips =
      if st.show_header,
        do: [Rendering.render_header(st, column_widths, tbl_width, focused(st))],
        else: []
    data_strips = Rendering.render_data_strips(st, column_widths, tbl_width, data_height)

    final_strips =
      (header_strips ++ data_strips)
      |> Rendering.pad_strips_to_height(content_height, tbl_width, st.styles.base)

    if st.show_scrollbars && length(st.data) > data_height do
      Rendering.add_vertical_scrollbar(final_strips, st, content_width, data_height)
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
  def handle_key(?+, state), do: Columns.resize_cursor_col(state, 2, &Selection.trigger_layout_change/1)
  def handle_key(?-, state), do: Columns.resize_cursor_col(state, -2, &Selection.trigger_layout_change/1)
  def handle_key(:+, state), do: Columns.resize_cursor_col(state, 2, &Selection.trigger_layout_change/1)
  def handle_key(:-, state), do: Columns.resize_cursor_col(state, -2, &Selection.trigger_layout_change/1)

  def handle_key(:left, state) do
    if focused(state) do
      Selection.move_cursor_horizontal(state, :left)
    else
      {:bubble, state}
    end
  end

  def handle_key(:right, state) do
    if focused(state) do
      Selection.move_cursor_horizontal(state, :right)
    else
      {:bubble, state}
    end
  end

  def handle_key(:up, state), do: Selection.action_cursor_up(state)
  def handle_key(:down, state), do: Selection.action_cursor_down(state)
  def handle_key(:home, state), do: Selection.action_cursor_first(state)
  def handle_key(:end, state), do: Selection.action_cursor_last(state)
  def handle_key(:page_up, state), do: Selection.action_page_up(state, get_data_height(state))
  def handle_key(:page_down, state), do: Selection.action_page_down(state, get_data_height(state))
  def handle_key(:enter, state), do: Selection.action_select_highlighted(state)
  def handle_key(:space, state), do: Selection.action_toggle_selection(state)
  def handle_key(_key, state), do: {:bubble, state}

  def handle_key(:left, [:shift], state), do: Columns.reorder_column(state, state.cursor_col, :left, &Selection.trigger_layout_change/1)
  def handle_key(:right, [:shift], state), do: Columns.reorder_column(state, state.cursor_col, :right, &Selection.trigger_layout_change/1)
  def handle_key(_key, _mods, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_scroll(direction, state) do
    if state.scroll.mouse_scroll_moves_selection do
      case direction do
        :up -> Selection.action_cursor_up(state)
        :down -> Selection.action_cursor_down(state)
      end
    else
      case direction do
        :up -> Selection.action_scroll_up(state)
        :down -> Selection.action_scroll_down(state, get_data_height(state))
      end
    end
  end

  @impl Drafter.Widget
  def handle_mouse_up(x, y, state) do
    was_resizing = state.drag.resize_col != nil
    was_reordering = state.drag.reorder_col != nil

    state = put_in(state.drag, %{state.drag | resize_col: nil, resize_start_x: nil, resize_start_width: nil, reorder_col: nil})

    if was_resizing or was_reordering do
      Selection.trigger_layout_change(state)
      {:ok, state}
    else
      Selection.handle_mouse_click(state, x, y)
    end
  end

  @impl Drafter.Widget
  def handle_drag(_x, y, state) when state.drag.dragging_scrollbar do
    Selection.drag_scrollbar_to(state, 0, y)
  end

  def handle_drag(x, _y, state) when state.drag.resize_col != nil do
    Columns.do_column_resize(state, x)
  end

  def handle_drag(x, _y, state) when state.drag.reorder_col != nil do
    Columns.do_column_reorder(state, x)
  end

  def handle_drag(x, y, state) when y == 0 and state.show_header and state.locked and state.resizable do
    col = Columns.calculate_column_from_x(state, x)
    widths = Columns.get_column_widths(state, state.width)
    start_width = Enum.at(widths, col, 10)
    {:ok, %{state | drag: %{state.drag | resize_col: col, resize_start_x: x, resize_start_width: start_width}, _col_widths: widths}}
  end

  def handle_drag(x, y, state) when y == 0 and state.show_header and not state.locked do
    col = Columns.calculate_column_from_x(state, x)
    widths = Columns.get_column_widths(state, state.width)
    col_order = Columns.get_col_order_list(state)
    {:ok, %{state | drag: %{state.drag | reorder_col: col}, _col_widths: widths, _col_order: col_order}}
  end

  def handle_drag(x, y, state), do: Selection.handle_mouse_drag(state, x, y)

  @impl Drafter.Widget
  def handle_hover(x, y, state) do
    Selection.handle_mouse_move(state, x, y)
  end

  @impl Drafter.Widget
  def handle_custom_event({:mouse, %{type: :mouse_up, x: x, y: y}}, state) do
    cond do
      state.drag.resize_col ->
        {:ok, %{state | drag: %{state.drag | resize_col: nil, resize_start_x: nil, resize_start_width: nil}}}

      state.drag.dragging_scrollbar ->
        Selection.handle_mouse_release(state, x, y)

      true ->
        Selection.handle_mouse_click(state, x, y)
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
    new_columns = Columns.normalize_columns(Map.get(props, :columns, state.columns))

    sorted_data =
      if new_data != state.data && state.sort_column do
        Sorting.sort_data(new_data, state.sort_column, state.sort_direction)
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
end
