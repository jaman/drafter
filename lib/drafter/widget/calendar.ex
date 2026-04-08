defmodule Drafter.Widget.Calendar do
  @moduledoc """
  A monthly calendar grid widget with date selection and keyboard navigation.

  Displays a single month at a time with a title row showing the month name and year,
  a weekday header row (Su Mo Tu We Th Fr Sa), and up to six week rows. Today's date
  is highlighted automatically, and the selected date receives a distinct visual treatment.

  ## Options

    * `:selected_date` - a `Date.t()` or `nil` to highlight (default: `nil`)
    * `:on_select` - callback fired when the user confirms a date; receives the `Date.t()`
    * `:min_date` - earliest navigable date (default: `nil`, no constraint)
    * `:max_date` - latest navigable date (default: `nil`, no constraint)
    * `:style` - map of inline style overrides
    * `:classes` - list of theme class atoms

  ## Key bindings

    * `←` / `→` — move cursor one day backward/forward
    * `↑` / `↓` — move cursor one week backward/forward
    * `Enter` / `Space` — select the highlighted date and fire `:on_select`
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

  @impl Drafter.Widget
  def handle_key(:left, state), do: move_cursor(state, -1)
  def handle_key(:right, state), do: move_cursor(state, 1)
  def handle_key(:up, state), do: move_cursor(state, -7)
  def handle_key(:down, state), do: move_cursor(state, 7)
  def handle_key(:enter, state), do: select_cursor(state)
  def handle_key(:" ", state), do: select_cursor(state)
  def handle_key(_key, state), do: {:bubble, state}

  @impl Drafter.Widget
  def handle_press(x, y, state) do
    case date_at_position(state, x, y) do
      nil -> {:ok, state}
      date -> confirm_date(%{state | cursor_date: date}, date)
    end
  end

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

  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 9

  @spec component_tag() :: :calendar
  def component_tag, do: :calendar

  @spec from_component_opts(term(), keyword()) :: map()
  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      selected_date: Keyword.get(opts, :selected_date),
      on_select: Callback.wrap_1(Keyword.get(opts, :on_select)),
      min_date: Keyword.get(opts, :min_date),
      max_date: Keyword.get(opts, :max_date),
      style: Keyword.get(opts, :style, %{}),
      classes: classes
    }
  end

  @spec update_props_from_mount(map(), t(), keyword()) :: map()
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
          [Segment.new(String.duplicate(" ", padding_width), %{fg: theme.text_primary, bg: theme.background})]
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
