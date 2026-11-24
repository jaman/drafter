defmodule Drafter.Widget.SourceList do
  @moduledoc """
  A sidebar list in sections, as a desktop app's window sidebar draws it: rows of
  an icon and a title under section headings, with the row of what is open drawn
  as selected.

  ## Component tag

  Tag `:source_list`, built by `Drafter.App` as `{:source_list, rows, opts}`:

      source_list(
        [
          %{id: :new_chat, title: "New chat", icon: "✎"},
          {:heading, "Chats"},
          %{id: {:chat, 1}, title: "Reverse a list", icon: "□"},
          {:heading, "Pages"},
          %{id: :models, title: "Models", icon: "⬡"}
        ],
        selected: {:chat, 1},
        on_select: :navigate
      )

  ## Rows

    * `%{id: id, title: title}`, with an optional `:icon` string drawn before the
      title - a row that can be opened. `id` is any term
    * `{:heading, title}` - a section heading. It cannot be opened, and a blank
      line is drawn above it unless it is the first row

  ## Options

    * `:selected` - the id of the row drawn as selected, such as the page or
      document that is open. Default `nil`. Changing it moves the keyboard cursor
      onto that row
    * `:on_select` - atom event name or `(id -> term())`, called with a row's id
      when the row is opened with `enter`, `space` or a mouse press. Default `nil`.
      The opened row is drawn as selected at once; the app keeps `:selected`
      current for what it then shows
    * `:visible_height` - the rows shown, which the keyboard cursor is kept
      within by scrolling. Default: the height of the rect the parent allocated

  The list fills the height it is given. A title wider than its row ends in `…`.

  ## Colours

  From the stylesheet: `source_list` (the list's text and background),
  `source_list::heading`, `source_list::icon`, `source_list::item:selected` (the
  selected row) and `source_list::item:hover` (the keyboard cursor, shown while the
  list has focus).

  ## Key bindings

    * `up` / `down` - move the cursor to the previous or next row, bubbling at the
      ends
    * `home` / `end` - the first or last row
    * `enter` / `space` - open the row under the cursor
    * mouse press - open the row pressed
    * mouse wheel - scroll
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :press, :scroll]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  defstruct lines: [],
            selected: nil,
            cursor: nil,
            scroll_offset: 0,
            visible_height: 10,
            on_select: nil,
            focused: false

  @typedoc "A row, a section heading, or the blank line drawn above a heading."
  @type line ::
          {:row,
           %{
             required(:id) => term(),
             required(:title) => String.t(),
             optional(:icon) => String.t()
           }}
          | {:heading, String.t()}
          | :blank

  @type t :: %__MODULE__{
          lines: [line()],
          selected: term(),
          cursor: term(),
          scroll_offset: non_neg_integer(),
          visible_height: pos_integer(),
          on_select: (term() -> term()) | nil,
          focused: boolean()
        }

  @doc """
  Builds the list from `props`: `:rows` (see "Rows"), `:selected`, `:on_select`,
  `:visible_height` and `:focused`. The keyboard cursor starts on the selected row,
  or on the first row.

      iex> list = Drafter.Widget.SourceList.mount(%{rows: [{:heading, "A"}, %{id: 1, title: "One"}]})
      iex> {list.cursor, length(list.lines)}
      {1, 2}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    lines = lines(Map.get(props, :rows, []))
    selected = Map.get(props, :selected)

    %__MODULE__{
      lines: lines,
      selected: selected,
      cursor: cursor_on(lines, selected),
      visible_height: Map.get(props, :visible_height, 10),
      on_select: Map.get(props, :on_select),
      focused: Map.get(props, :focused, false)
    }
  end

  @doc "Draws the visible lines into `rect`, filling its height."
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    base =
      :source_list
      |> Computed.for_widget(%{focused: state.focused})
      |> Computed.to_segment_style()

    state.lines
    |> Enum.drop(state.scroll_offset)
    |> Enum.take(rect.height)
    |> Enum.map(&render_line(&1, state, base, rect.width))
    |> pad_rows(rect, base)
  end

  @doc """
  Moves the keyboard cursor or opens the row under it; every other key bubbles.

      iex> rows = [%{id: :a, title: "A"}, {:heading, "H"}, %{id: :b, title: "B"}]
      iex> list = Drafter.Widget.SourceList.mount(%{rows: rows})
      iex> {:ok, moved} = Drafter.Widget.SourceList.handle_key(:down, list)
      iex> moved.cursor
      :b
  """
  @spec handle_key(atom(), t()) :: {:ok, t()} | {:ok, t(), list()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_key(:up, state), do: move(state, previous_row(state.lines, state.cursor))
  def handle_key(:down, state), do: move(state, next_row(state.lines, state.cursor))
  def handle_key(:home, state), do: move(state, first_row(state.lines))
  def handle_key(:end, state), do: move(state, first_row(Enum.reverse(state.lines)))
  def handle_key(:enter, state), do: open(state, state.cursor)
  def handle_key(:" ", state), do: open(state, state.cursor)
  def handle_key(_key, state), do: {:bubble, state}

  @doc "Opens the row on line `y` of the rect; a heading or blank line does nothing."
  @spec handle_press(integer(), integer(), t()) ::
          {:ok, t()} | {:ok, t(), list()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_press(_x, y, state) do
    case Enum.at(state.lines, y + state.scroll_offset) do
      {:row, row} -> open(state, row.id)
      _other -> {:noreply, state}
    end
  end

  @doc "Scrolls the lines by one, within the list."
  @spec handle_scroll(:up | :down, t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_scroll(:up, state),
    do: {:ok, %{state | scroll_offset: max(0, state.scroll_offset - 1)}}

  def handle_scroll(:down, state),
    do: {:ok, %{state | scroll_offset: min(max_offset(state), state.scroll_offset + 1)}}

  @doc """
  Takes `{:focus}` itself, putting the cursor on the selected row when it has
  none, and passes every other event to the generated dispatch.
  """
  @spec handle_event(term(), t()) :: term()
  @impl Drafter.Widget
  def handle_event({:focus}, state),
    do:
      {:ok,
       %{state | focused: true, cursor: state.cursor || cursor_on(state.lines, state.selected)}}

  def handle_event(event, state), do: super(event, state)

  @doc "Merges `props` into the state."
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state), do: state |> Map.merge(props) |> visible_cursor()

  @doc """
  The rows the element asks for: `opts[:height]` when given, otherwise one per row
  and heading and a blank line above each heading after the first row.

      iex> Drafter.Widget.SourceList.preferred_height([%{id: 1, title: "A"}, {:heading, "B"}], [])
      3
  """
  @spec preferred_height(list() | nil, keyword()) :: non_neg_integer()
  def preferred_height(rows, opts), do: Keyword.get(opts, :height, length(lines(rows || [])))

  @doc "The component tag this widget registers under."
  @spec component_tag() :: :source_list
  def component_tag, do: :source_list

  @doc """
  Builds the props for a `{:source_list, rows, opts}` element. An atom
  `:on_select` is wrapped so the app event carries the row's id.
  """
  @spec from_component_opts(list() | nil, keyword()) :: Drafter.Widget.props()
  def from_component_opts(rows, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 30, height: 10})

    %{
      rows: rows || [],
      lines: lines(rows || []),
      selected: Keyword.get(opts, :selected),
      visible_height: Keyword.get(opts, :visible_height, rect.height),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select))
    }
  end

  @doc """
  Narrows a re-render to the lines, the selected row, the callback and the
  visible height; the keyboard cursor moves only when the selected row changed.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(props, existing, _opts) do
    base = Map.take(props, [:lines, :selected, :visible_height, :on_select])

    if props.selected == existing.selected,
      do: base,
      else: Map.put(base, :cursor, cursor_on(props.lines, props.selected))
  end

  defp lines(rows) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:heading, title}, 0} -> [{:heading, title}]
      {{:heading, title}, _index} -> [:blank, {:heading, title}]
      {%{id: _id, title: _title} = row, _index} -> [{:row, row}]
    end)
  end

  defp render_line(:blank, _state, base, width), do: Strip.new([Segment.new(spaces(width), base)])

  defp render_line({:heading, title}, state, base, width) do
    style = Map.merge(base, Map.take(part(:heading, state, %{}, base), [:fg, :bold]))
    Strip.new([Segment.new(" " <> fit(title, width - 1), style)])
  end

  defp render_line({:row, row}, state, base, width) do
    item_state = %{
      selected: row.id == state.selected,
      hovered: state.focused and row.id == state.cursor
    }

    item = part(:item, state, item_state, base)
    icon = Map.merge(item, Map.take(part(:icon, state, item_state, item), [:fg]))
    title = if item_state.selected, do: Map.put(item, :bold, true), else: item
    icon_text = icon_text(Map.get(row, :icon))
    inner = max(0, width - 2)
    title_width = max(0, inner - 1 - String.length(icon_text))

    Strip.new([
      Segment.new(" ", base),
      Segment.new(" ", item),
      Segment.new(icon_text, icon),
      Segment.new(String.pad_trailing(fit(row.title, title_width), title_width), title),
      Segment.new(" ", base)
    ])
  end

  defp part(name, state, item_state, base) do
    :source_list
    |> Computed.for_part(Map.merge(%{focused: state.focused}, item_state), name)
    |> Computed.to_segment_style()
    |> then(&Map.merge(base, &1))
  end

  defp icon_text(nil), do: ""
  defp icon_text(icon), do: icon <> " "

  defp fit(text, width) when width <= 0, do: String.slice(text, 0, 0)

  defp fit(text, width) do
    if String.length(text) > width, do: String.slice(text, 0, width - 1) <> "…", else: text
  end

  defp spaces(width), do: String.duplicate(" ", max(0, width))

  defp pad_rows(strips, rect, base) do
    blank = Strip.new([Segment.new(spaces(rect.width), base)])
    strips ++ List.duplicate(blank, max(0, rect.height - length(strips)))
  end

  defp row_ids(lines), do: for({:row, row} <- lines, do: row.id)

  defp first_row(lines), do: List.first(row_ids(lines))

  defp next_row(lines, cursor) do
    ids = row_ids(lines)

    case Enum.find_index(ids, &(&1 == cursor)) do
      nil -> List.first(ids)
      index -> Enum.at(ids, index + 1)
    end
  end

  defp previous_row(lines, cursor) do
    ids = row_ids(lines)

    case Enum.find_index(ids, &(&1 == cursor)) do
      nil -> List.first(ids)
      0 -> nil
      index -> Enum.at(ids, index - 1)
    end
  end

  defp cursor_on(lines, selected) do
    if selected in row_ids(lines), do: selected, else: first_row(lines)
  end

  defp move(state, nil), do: {:bubble, state}
  defp move(state, id), do: {:ok, visible_cursor(%{state | cursor: id})}

  defp open(state, nil), do: {:noreply, state}

  defp open(state, id) do
    opened = visible_cursor(%{state | cursor: id, selected: id})

    case state.on_select do
      nil -> {:ok, opened}
      callback -> {:ok, opened, [callback.(id)]}
    end
  end

  defp visible_cursor(state) do
    cursor = state.cursor

    case Enum.find_index(state.lines, &match?({:row, %{id: ^cursor}}, &1)) do
      nil ->
        %{state | scroll_offset: min(state.scroll_offset, max_offset(state))}

      index ->
        offset =
          Drafter.ScrollMath.ensure_visible(state.scroll_offset, index, state.visible_height)

        %{state | scroll_offset: offset}
    end
  end

  defp max_offset(state), do: max(0, length(state.lines) - state.visible_height)
end
