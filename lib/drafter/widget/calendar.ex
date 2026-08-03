defmodule Drafter.Widget.Calendar do
  @moduledoc """
  A monthly calendar grid widget with date selection and keyboard navigation.

  Displays a single month at a time with a title row showing the month name and year,
  a weekday header row (Su Mo Tu We Th Fr Sa), and up to six week rows. Today's date
  is highlighted automatically, and the selected date receives a distinct visual treatment.

  ## Component tag

  Tag `:calendar`, built by `Drafter.App` as `{:calendar, opts}`:

      calendar(opts)

  There is no positional argument; every prop comes from `opts`.
  `from_component_opts/2` wraps `:on_select` with `Drafter.Widget.Callback`, so
  it may be given as an atom event name.

  ## Options

    * `:selected_date` - `t:Date.t/0` to highlight. Default `nil`. The cursor starts
      on this date, or on `Date.utc_today/0` when it is `nil`
    * `:on_select` - atom event name or one-arity function receiving the confirmed
      `t:Date.t/0`. Default `nil`. Its return value is discarded, so it cannot emit
      an action; use it for its side effect
    * `:min_date` - earliest navigable `t:Date.t/0`. Default `nil`, no constraint
    * `:max_date` - latest navigable `t:Date.t/0`. Default `nil`, no constraint
    * `:style` - `t:map/0` of inline style overrides. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`

  `update/2` re-reads `:selected_date`, `:min_date`, `:max_date`, `:on_select`,
  `:style` and `:classes`. `:cursor_date` and `:view_date` are owned by the widget
  and survive a re-render, so changing `:selected_date` after mount moves the
  highlight but not the cursor or the displayed month.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget; the chosen date
  is reported through `:on_select`.

  ## Key bindings

    * `←` / `→` — move cursor one day backward/forward
    * `↑` / `↓` — move cursor one week backward/forward
    * `Enter` / `Space` — select the highlighted date and fire `:on_select`

  A move that would leave the `:min_date`..`:max_date` range is ignored. Crossing a
  month boundary scrolls the view to the new month. Every other key bubbles.

  ## Usage

      calendar(selected_date: ~D[2026-08-02], on_select: :date_chosen)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :press]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.ThemeManager
  alias Drafter.Widget.Callback

  @cell_width 4
  @cols 7
  @grid_width @cell_width * @cols

  defstruct [
    :cursor_date,
    :selected_date,
    :view_date,
    :min_date,
    :max_date,
    :style,
    :classes,
    :on_select
  ]

  @type t :: %__MODULE__{
          cursor_date: Date.t(),
          selected_date: Date.t() | nil,
          view_date: Date.t(),
          min_date: Date.t() | nil,
          max_date: Date.t() | nil,
          style: map(),
          classes: [atom()],
          on_select: (Date.t() -> term()) | nil
        }

  @doc """
  Builds the calendar state from `props`.

  The cursor starts on `:selected_date`, or on `Date.utc_today/0` when that is
  `nil`, and the view opens on the first day of the cursor's month.

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> {cal.cursor_date, cal.view_date, cal.selected_date}
      {~D[2026-08-02], ~D[2026-08-01], ~D[2026-08-02]}

      iex> cal = Drafter.Widget.Calendar.mount(%{})
      iex> {cal.selected_date, cal.min_date, cal.max_date, cal.classes, cal.style}
      {nil, nil, nil, [], %{}}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    today = Date.utc_today()
    selected = Map.get(props, :selected_date)
    cursor = selected || today

    %__MODULE__{
      cursor_date: cursor,
      selected_date: selected,
      view_date: Date.beginning_of_month(cursor),
      min_date: Map.get(props, :min_date),
      max_date: Map.get(props, :max_date),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      on_select: Map.get(props, :on_select)
    }
  end

  @doc """
  Draws the month into `rect`.

  Always returns nine strips: a title row, a weekday header row, up to six week
  rows, and blank rows making up the difference. `rect.height` is not consulted, and
  `rect.width` is widened to at least 28 columns, four per weekday column.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    theme = ThemeManager.get_current_theme()
    width = max(rect.width, @grid_width)

    title_strip = render_title(state, theme, width)
    header_strip = render_weekday_header(theme, width)
    week_strips = render_weeks(state, theme, width)

    bg_style = %{fg: theme.text_primary, bg: theme.background}
    empty_strip = Strip.new([Segment.new(String.duplicate(" ", width), bg_style)])

    padding_count = max(0, 9 - (2 + length(week_strips)))
    padding = List.duplicate(empty_strip, padding_count)

    [title_strip, header_strip] ++ week_strips ++ padding
  end

  @doc """
  Moves the cursor or confirms the date under it.

  Arrow keys return `{:ok, state}`, with the state unchanged when the target date
  falls outside `:min_date`..`:max_date`. `:enter` and `:" "` set `:selected_date`
  to the cursor date, call `:on_select`, and return `{:ok, state}`. Every other key
  returns `{:bubble, state}`.

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> {:ok, moved} = Drafter.Widget.Calendar.handle_key(:down, cal)
      iex> moved.cursor_date
      ~D[2026-08-09]

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> {:ok, moved} = Drafter.Widget.Calendar.handle_key(:left, cal)
      iex> {moved.cursor_date, moved.view_date}
      {~D[2026-08-01], ~D[2026-08-01]}

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02], min_date: ~D[2026-08-02]})
      iex> {:ok, blocked} = Drafter.Widget.Calendar.handle_key(:left, cal)
      iex> blocked.cursor_date
      ~D[2026-08-02]

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-31]})
      iex> {:ok, next} = Drafter.Widget.Calendar.handle_key(:right, cal)
      iex> {next.cursor_date, next.view_date}
      {~D[2026-09-01], ~D[2026-09-01]}

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> {:ok, chosen} = Drafter.Widget.Calendar.handle_key(:enter, cal)
      iex> chosen.selected_date
      ~D[2026-08-02]

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> Drafter.Widget.Calendar.handle_key(:escape, cal) |> elem(0)
      :bubble
  """
  @spec handle_key(Drafter.Widget.key(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_key(:left, state), do: move_cursor(state, -1)
  def handle_key(:right, state), do: move_cursor(state, 1)
  def handle_key(:up, state), do: move_cursor(state, -7)
  def handle_key(:down, state), do: move_cursor(state, 7)
  def handle_key(:enter, state), do: select_cursor(state)
  def handle_key(:" ", state), do: select_cursor(state)
  def handle_key(_key, state), do: {:bubble, state}

  @doc """
  Selects the date under the pressed cell.

  Rows `2` through `7` are the week rows and every four columns are one weekday
  column, so the cell is `{div(x, 4), y - 2}`. A press on the title or header row,
  or beyond the seventh column, returns `{:ok, state}` unchanged. A hit moves the
  cursor to that date, sets `:selected_date`, and calls `:on_select`; the
  `:min_date`/`:max_date` range is not applied on this path.
  """
  @spec handle_press(integer(), integer(), t()) :: {:ok, t()}
  @impl Drafter.Widget
  def handle_press(x, y, state) do
    case date_at_position(state, x, y) do
      nil -> {:ok, state}
      date -> confirm_date(%{state | cursor_date: date}, date)
    end
  end

  @doc """
  Folds fresh props into `state`.

  Re-reads `:selected_date`, `:min_date`, `:max_date`, `:on_select`, `:style` and
  `:classes`. `:cursor_date` and `:view_date` are left untouched, so the displayed
  month does not follow a new `:selected_date`.

      iex> cal = Drafter.Widget.Calendar.mount(%{selected_date: ~D[2026-08-02]})
      iex> updated = Drafter.Widget.Calendar.update(%{selected_date: ~D[2026-12-25]}, cal)
      iex> {updated.selected_date, updated.view_date}
      {~D[2026-12-25], ~D[2026-08-01]}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | selected_date: Map.get(props, :selected_date, state.selected_date),
        min_date: Map.get(props, :min_date, state.min_date),
        max_date: Map.get(props, :max_date, state.max_date),
        on_select: Map.get(props, :on_select, state.on_select),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes)
    }
  end

  @doc """
  Always `9`: a title row, a weekday header row and six week rows.

      iex> Drafter.Widget.Calendar.preferred_height(nil, [])
      9
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 9

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Calendar.component_tag()
      :calendar
  """
  @spec component_tag() :: :calendar
  def component_tag, do: :calendar

  @doc """
  Turns the `{:calendar, opts}` element into a props map for `mount/1`.

  The positional argument is ignored; every prop comes from `opts`. `:class` is
  normalised into `:classes` and `:on_select` is wrapped by
  `Drafter.Widget.Callback.wrap_1/1`.

      iex> props = Drafter.Widget.Calendar.from_component_opts(nil, selected_date: ~D[2026-08-02])
      iex> {props.selected_date, props.on_select, props.min_date, props.style, props.classes}
      {~D[2026-08-02], nil, nil, %{}, []}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    %{
      selected_date: Keyword.get(opts, :selected_date),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select)),
      min_date: Keyword.get(opts, :min_date),
      max_date: Keyword.get(opts, :max_date),
      style: Keyword.get(opts, :style, %{}),
      classes: classes
    }
  end

  @doc """
  Returns `mount_props` unchanged, so a re-render passes every option through to
  `update/2`.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp render_title(state, theme, width) do
    month_name = Calendar.strftime(state.view_date, "%B %Y")
    left_arrow = "◀ "
    right_arrow = " ▶"
    inner = left_arrow <> month_name <> right_arrow
    padded = String.pad_trailing(center_text(inner, width), width)

    Strip.new([
      Segment.new(padded, %{fg: theme.text_primary, bg: theme.surface, bold: true})
    ])
  end

  defp render_weekday_header(theme, width) do
    header_text =
      ~w(Su Mo Tu We Th Fr Sa)
      |> Enum.map_join(fn day -> String.pad_trailing(day, @cell_width) end)

    padded = String.pad_trailing(header_text, width)

    Strip.new([
      Segment.new(padded, %{fg: theme.text_muted, bg: theme.surface})
    ])
  end

  defp render_weeks(state, theme, width) do
    first_of_month = state.view_date
    last_of_month = Date.end_of_month(first_of_month)
    start_dow = Date.day_of_week(first_of_month, :sunday)
    first_visible = Date.add(first_of_month, -(start_dow - 1))

    today = Date.utc_today()

    weeks =
      Stream.iterate(first_visible, &Date.add(&1, 1))
      |> Stream.chunk_every(7)
      |> Stream.take_while(fn week ->
        List.first(week) |> Date.compare(Date.add(last_of_month, 6)) != :gt
      end)
      |> Enum.take(6)

    Enum.map(weeks, fn week ->
      segments =
        Enum.map(week, fn date ->
          in_month = date.month == first_of_month.month and date.year == first_of_month.year
          is_today = Date.compare(date, today) == :eq
          is_selected = state.selected_date && Date.compare(date, state.selected_date) == :eq
          is_cursor = Date.compare(date, state.cursor_date) == :eq

          day_str = date.day |> Integer.to_string() |> String.pad_leading(2)
          cell_text = String.pad_trailing(day_str, @cell_width)

          style = day_style(theme, in_month, is_today, is_selected, is_cursor, focused(state))
          Segment.new(cell_text, style)
        end)

      padding_width = max(0, width - @grid_width)

      trailing =
        if padding_width > 0 do
          [
            Segment.new(String.duplicate(" ", padding_width), %{
              fg: theme.text_primary,
              bg: theme.background
            })
          ]
        else
          []
        end

      Strip.new(segments ++ trailing)
    end)
  end

  defp day_style(theme, in_month, is_today, is_selected, is_cursor, is_focused) do
    cond do
      is_selected ->
        %{fg: theme.text_primary, bg: theme.primary, bold: true}

      is_cursor and is_focused ->
        %{fg: theme.text_primary, bg: theme.primary_muted}

      is_today ->
        %{fg: theme.accent, bg: theme.background, bold: true}

      in_month ->
        %{fg: theme.text_primary, bg: theme.background}

      true ->
        %{fg: theme.text_muted, bg: theme.background}
    end
  end

  defp move_cursor(state, days) do
    new_date = Date.add(state.cursor_date, days)

    if date_in_bounds?(new_date, state.min_date, state.max_date) do
      new_view =
        if new_date.month != state.view_date.month or new_date.year != state.view_date.year do
          Date.beginning_of_month(new_date)
        else
          state.view_date
        end

      {:ok, %{state | cursor_date: new_date, view_date: new_view}}
    else
      {:ok, state}
    end
  end

  defp select_cursor(state) do
    confirm_date(state, state.cursor_date)
  end

  defp confirm_date(state, date) do
    new_state = %{state | selected_date: date}

    if state.on_select do
      state.on_select.(date)
    end

    {:ok, new_state}
  end

  defp date_at_position(state, x, y) when y >= 2 and y <= 7 do
    col = div(x, @cell_width)

    if col >= 0 and col < @cols do
      first_of_month = state.view_date
      start_dow = Date.day_of_week(first_of_month, :sunday)
      first_visible = Date.add(first_of_month, -(start_dow - 1))
      week_index = y - 2
      day_offset = week_index * 7 + col
      Date.add(first_visible, day_offset)
    else
      nil
    end
  end

  defp date_at_position(_state, _x, _y), do: nil

  defp date_in_bounds?(date, min_date, max_date) do
    above_min = is_nil(min_date) or Date.compare(date, min_date) != :lt
    below_max = is_nil(max_date) or Date.compare(date, max_date) != :gt
    above_min and below_max
  end

  defp center_text(text, width) do
    text_len = String.length(text)

    if text_len >= width do
      text
    else
      left_pad = div(width - text_len, 2)
      String.duplicate(" ", left_pad) <> text
    end
  end
end
