defmodule Drafter.Prompt.Select do
  @moduledoc """
  The component behind `Drafter.Prompt.select/3`, `multiselect/3` and `search/3`: a
  list to pick one or several entries from.

  ## Options

    * `:label` - the question
    * `:choices` - the entries, each anything `Drafter.Prompt.Choice.new/1` accepts
    * `:source` - `(query -> choices)`, called with the typed text on every change, in
      place of `:choices`
    * `:multiple` - `true` picks several entries and returns their values as a list
    * `:filter` - `true` narrows the list to the entries containing the typed text,
      ignoring case. Always on with `:source`
    * `:default` - the value highlighted first, or with `:multiple` the list of values
      picked first
    * `:min` and `:max` - with `:multiple`, the fewest and most entries that may be
      picked. Defaults `0` and no limit
    * `:limit` - the most entries shown at once. Default
      `config :drafter, prompt_limit: 7`

  ## Keys

  Up, Down, Ctrl+P, Ctrl+N, Page Up, Page Down, Home and End move the highlight, which
  skips disabled entries and wraps at either end. Enter picks. Esc clears the typed
  text if there is any and otherwise stops the prompt with `:cancelled`.

  Without `:filter`, `k` and `j` also move. With `:multiple`, Tab picks or unpicks
  the highlighted entry and Ctrl+A all of them; without `:filter`, Space and `a` do
  the same.
  """

  @behaviour Drafter.Prompt.Component

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.{Choice, Editor, Frame, Style, Window}

  defstruct label: "",
            choices: [],
            shown: [],
            source: nil,
            filter: nil,
            cursor: 0,
            limit: 7,
            multiple: false,
            picked: MapSet.new(),
            min: 0,
            max: nil,
            error: nil

  @impl true
  def init(opts) do
    source = Keyword.get(opts, :source)
    choices = opts |> Keyword.get(:choices, []) |> first_choices(source)
    multiple = Keyword.get(opts, :multiple, false)
    default = Keyword.get(opts, :default)

    %__MODULE__{
      label: Keyword.get(opts, :label, ""),
      choices: choices,
      shown: choices,
      source: source,
      filter: filter(source != nil or Keyword.get(opts, :filter, false)),
      limit: Keyword.get(opts, :limit, Application.get_env(:drafter, :prompt_limit, 7)),
      multiple: multiple,
      picked: picked(choices, multiple, default),
      min: Keyword.get(opts, :min, 0),
      max: Keyword.get(opts, :max)
    }
    |> highlight(multiple, default)
  end

  @impl true
  def handle_event({:key, :up}, state), do: {:cont, move(state, -1)}
  def handle_event({:key, :down}, state), do: {:cont, move(state, 1)}
  def handle_event({:key, :p, [:ctrl]}, state), do: {:cont, move(state, -1)}
  def handle_event({:key, :n, [:ctrl]}, state), do: {:cont, move(state, 1)}
  def handle_event({:key, :k}, %__MODULE__{filter: nil} = state), do: {:cont, move(state, -1)}
  def handle_event({:key, :j}, %__MODULE__{filter: nil} = state), do: {:cont, move(state, 1)}
  def handle_event({:key, :page_up}, state), do: {:cont, page(state, -1)}
  def handle_event({:key, :page_down}, state), do: {:cont, page(state, 1)}
  def handle_event({:key, :home}, state), do: {:cont, settle(%{state | cursor: 0}, 1)}
  def handle_event({:key, :end}, state), do: {:cont, settle(%{state | cursor: last(state)}, -1)}
  def handle_event({:key, :enter}, %__MODULE__{multiple: true} = state), do: submit_picked(state)
  def handle_event({:key, :enter}, state), do: submit(current(state), state)
  def handle_event({:key, :tab}, %__MODULE__{multiple: true} = state), do: {:cont, toggle(state)}

  def handle_event({:key, :a, [:ctrl]}, %__MODULE__{multiple: true} = state),
    do: {:cont, toggle_all(state)}

  def handle_event({:key, :" "}, %__MODULE__{multiple: true, filter: nil} = state),
    do: {:cont, toggle(state)}

  def handle_event({:key, :a}, %__MODULE__{multiple: true, filter: nil} = state),
    do: {:cont, toggle_all(state)}

  def handle_event({:key, :escape}, %__MODULE__{filter: %Editor{before: [], after: []}} = state),
    do: {:stop, :cancelled, state}

  def handle_event({:key, :escape}, %__MODULE__{filter: %Editor{}} = state),
    do: {:cont, refilter(%{state | filter: Editor.new()})}

  def handle_event({:key, :escape}, state), do: {:stop, :cancelled, state}

  def handle_event(event, %__MODULE__{filter: %Editor{} = filter} = state) do
    case Editor.edit(filter, event) do
      {:ok, filter} -> {:cont, refilter(%{state | filter: filter, error: nil})}
      :ignored -> {:cont, state}
    end
  end

  def handle_event(_event, state), do: {:cont, state}

  @impl true
  def render(state, :active, %{style: style, width: width, rows: rows}) do
    head = head(state, style)
    head_width = head |> Strip.new() |> Strip.width()
    {query, cursor} = query(state, style, max(width - head_width, 4), head_width)
    limit = state.limit |> min(rows - 3) |> max(1)

    Frame.new(
      [Strip.new(head ++ query)] ++ rows(state, limit, style) ++ error_lines(state, style),
      cursor
    )
  end

  def render(state, {:done, _value}, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :success, Style.symbol(style, :done)),
        Style.segment(style, :strong, " " <> state.label <> " "),
        Style.segment(style, :muted, Style.symbol(style, :separator) <> " "),
        Style.segment(style, :plain, answer(state))
      ])
    ])
  end

  def render(state, {:stopped, _reason}, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :error, Style.symbol(style, :failed)),
        Style.segment(style, :muted, " " <> state.label)
      ])
    ])
  end

  @impl true
  def line_prompt(%__MODULE__{source: source, label: label}) when is_function(source),
    do: [label, ": "]

  def line_prompt(%__MODULE__{multiple: true} = state),
    do: [
      state.label,
      "\n",
      numbered(state),
      "Numbers, separated by commas",
      line_default(state),
      ": "
    ]

  def line_prompt(state),
    do: [state.label, "\n", numbered(state), "Number", line_default(state), ": "]

  @impl true
  def parse_line(line, %__MODULE__{source: source}) when is_function(source) do
    case line |> source.() |> Enum.map(&Choice.new/1) |> Enum.reject(& &1.disabled) do
      [choice | _rest] -> {:ok, choice.value}
      [] -> {:error, "Nothing matches."}
    end
  end

  def parse_line(line, %__MODULE__{multiple: true} = state) do
    with {:ok, positions} <- positions(String.trim(line), state),
         :ok <- within(length(positions), state) do
      {:ok, values(state, MapSet.new(positions))}
    end
  end

  def parse_line(line, state) do
    case positions(String.trim(line), state) do
      {:ok, [position]} ->
        {:ok, state.choices |> Enum.at(position) |> elem(0) |> Map.fetch!(:value)}

      {:ok, _several} ->
        {:error, "Enter one number."}

      error ->
        error
    end
  end

  defp first_choices(choices, nil), do: indexed(choices)
  defp first_choices(_choices, source), do: indexed(source.(""))

  defp indexed(choices), do: choices |> Enum.map(&Choice.new/1) |> Enum.with_index()

  defp filter(true), do: Editor.new()
  defp filter(false), do: nil

  defp picked(choices, true, defaults) when is_list(defaults),
    do: for({choice, index} <- choices, choice.value in defaults, into: MapSet.new(), do: index)

  defp picked(_choices, _multiple, _default), do: MapSet.new()

  defp highlight(state, false, default) when default != nil do
    case Enum.find_index(state.shown, fn {choice, _index} -> choice.value == default end) do
      nil -> settle(state, 1)
      position -> settle(%{state | cursor: position}, 1)
    end
  end

  defp highlight(state, _multiple, _default), do: settle(state, 1)

  defp last(state), do: max(length(state.shown) - 1, 0)

  defp current(state), do: Enum.at(state.shown, state.cursor)

  defp enabled?(nil), do: false
  defp enabled?({choice, _index}), do: not choice.disabled

  defp move(%__MODULE__{shown: []} = state, _by), do: state

  defp move(state, by) do
    count = length(state.shown)

    1..count
    |> Enum.map(&Integer.mod(state.cursor + by * &1, count))
    |> Enum.find(state.cursor, &enabled?(Enum.at(state.shown, &1)))
    |> then(&%{state | cursor: &1})
  end

  defp page(state, direction) do
    target = (state.cursor + direction * state.limit) |> max(0) |> min(last(state))
    settle(%{state | cursor: target}, -direction)
  end

  defp settle(state, toward) do
    if enabled?(current(state)) or state.shown == [], do: state, else: move(state, toward)
  end

  defp submit(nil, state), do: {:cont, state}
  defp submit({%Choice{disabled: true}, _index}, state), do: {:cont, state}
  defp submit({choice, _index}, state), do: {:done, choice.value, state}

  defp submit_picked(state) do
    case within(MapSet.size(state.picked), state) do
      :ok -> {:done, values(state, state.picked), state}
      {:error, message} -> {:cont, %{state | error: message}}
    end
  end

  defp within(count, %__MODULE__{min: min}) when count < min,
    do: {:error, "Pick at least #{min}."}

  defp within(count, %__MODULE__{max: max}) when is_integer(max) and count > max,
    do: {:error, "Pick at most #{max}."}

  defp within(_count, _state), do: :ok

  defp values(state, picked),
    do: for({choice, index} <- state.choices, index in picked, do: choice.value)

  defp toggle(state), do: toggle(current(state), state)

  defp toggle({%Choice{disabled: false}, index}, state) do
    picked =
      if index in state.picked,
        do: MapSet.delete(state.picked, index),
        else: MapSet.put(state.picked, index)

    %{state | picked: picked, error: nil}
  end

  defp toggle(_none, state), do: state

  defp toggle_all(state) do
    listed = for {%Choice{disabled: false}, index} <- state.shown, into: MapSet.new(), do: index

    picked =
      if MapSet.subset?(listed, state.picked),
        do: MapSet.difference(state.picked, listed),
        else: MapSet.union(state.picked, listed)

    %{state | picked: picked, error: nil}
  end

  defp refilter(%__MODULE__{source: nil} = state) do
    query = state.filter |> Editor.text() |> String.downcase()

    shown =
      Enum.filter(state.choices, fn {choice, _index} ->
        String.contains?(String.downcase(choice.label), query)
      end)

    settle(%{state | shown: shown, cursor: 0}, 1)
  end

  defp refilter(%__MODULE__{source: source} = state) do
    choices = state.filter |> Editor.text() |> source.() |> indexed()
    settle(%{state | choices: choices, shown: choices, cursor: 0}, 1)
  end

  defp head(state, style) do
    [
      Style.segment(style, :accent, Style.symbol(style, :question)),
      Style.segment(style, :strong, " " <> state.label <> " ")
    ]
  end

  defp query(%__MODULE__{filter: nil, multiple: false}, _style, _room, _head_width), do: {[], nil}

  defp query(%__MODULE__{filter: nil} = state, style, _room, _head_width),
    do: {[Style.segment(style, :muted, keys(state))], nil}

  defp query(
         %__MODULE__{filter: %Editor{before: [], after: []}} = state,
         style,
         _room,
         head_width
       ) do
    prompt = Style.symbol(style, :prompt) <> " "

    {[Style.segment(style, :muted, prompt <> "type to filter" <> keys(state))],
     {0, head_width + 2}}
  end

  defp query(%__MODULE__{filter: filter}, style, room, head_width) do
    {text, column} = Editor.view(filter, max(room - 2, 2))

    {[
       Style.segment(style, :muted, Style.symbol(style, :prompt) <> " "),
       Style.segment(style, :plain, text)
     ], {0, head_width + 2 + column}}
  end

  defp keys(%__MODULE__{multiple: true, filter: nil}),
    do: "(space picks, a picks all, enter confirms)"

  defp keys(%__MODULE__{multiple: true}), do: " (tab picks, enter confirms)"
  defp keys(_state), do: ""

  defp rows(%__MODULE__{shown: []}, _limit, style),
    do: [Strip.new([Style.segment(style, :muted, "  Nothing matches")])]

  defp rows(state, limit, style) do
    count = length(state.shown)
    window = Window.range(count, state.cursor, limit)

    listed =
      state.shown
      |> Enum.with_index()
      |> Enum.slice(window)
      |> Enum.map(fn {{choice, index}, position} ->
        row(choice, position == state.cursor, index in state.picked, state.multiple, style)
      end)

    listed ++ Window.footer(window, count, style)
  end

  defp row(choice, highlighted?, picked?, multiple?, style) do
    Strip.new(
      [pointer(highlighted?, style)] ++
        box(multiple?, picked?, style) ++
        [label(choice, highlighted?, style)] ++ hint(choice.hint, style)
    )
  end

  defp pointer(true, style),
    do: Style.segment(style, :accent, Style.symbol(style, :pointer) <> " ")

  defp pointer(false, style), do: Style.segment(style, :plain, "  ")

  defp box(false, _picked?, _style), do: []

  defp box(true, true, style),
    do: [Style.segment(style, :success, Style.symbol(style, :on) <> " ")]

  defp box(true, false, style),
    do: [Style.segment(style, :muted, Style.symbol(style, :off) <> " ")]

  defp label(%Choice{disabled: true, label: label}, _highlighted?, style),
    do: Style.segment(style, :muted, label <> " (unavailable)")

  defp label(%Choice{label: label}, true, style), do: Style.segment(style, :accent, label)
  defp label(%Choice{label: label}, false, style), do: Style.segment(style, :plain, label)

  defp hint(nil, _style), do: []
  defp hint(text, style), do: [Style.segment(style, :muted, "  " <> text)]

  defp error_lines(%__MODULE__{error: nil}, _style), do: []

  defp error_lines(%__MODULE__{error: message}, style) do
    [
      Strip.new([
        Style.segment(style, :error, "  " <> Style.symbol(style, :failed) <> " " <> message)
      ])
    ]
  end

  defp answer(%__MODULE__{multiple: true} = state) do
    case for({choice, index} <- state.choices, index in state.picked, do: choice.label) do
      [] -> "none"
      labels -> Enum.join(labels, ", ")
    end
  end

  defp answer(state) do
    {choice, _index} = current(state)
    choice.label
  end

  defp numbered(state) do
    Enum.map(state.choices, fn
      {%Choice{disabled: true, label: label}, index} -> "  #{index + 1}) #{label} (unavailable)\n"
      {%Choice{label: label}, index} -> "  #{index + 1}) #{label}\n"
    end)
  end

  defp line_default(%__MODULE__{multiple: true, picked: picked}) do
    case picked |> Enum.sort() |> Enum.map_join(",", &(&1 + 1)) do
      "" -> ""
      numbers -> " [" <> numbers <> "]"
    end
  end

  defp line_default(state) do
    case current(state) do
      {%Choice{disabled: false}, index} -> " [#{index + 1}]"
      _none -> ""
    end
  end

  defp positions("", %__MODULE__{multiple: true, picked: picked}), do: {:ok, Enum.sort(picked)}

  defp positions("", state) do
    case current(state) do
      {%Choice{disabled: false}, index} -> {:ok, [index]}
      _none -> {:error, "Enter a number."}
    end
  end

  defp positions(line, state) do
    line
    |> String.split([",", " "], trim: true)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, positions} ->
      case position(entry, state) do
        {:ok, position} -> {:cont, {:ok, [position | positions]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, positions} -> {:ok, positions |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp position(entry, state) do
    with {number, ""} when number >= 1 <- Integer.parse(entry),
         {%Choice{disabled: false}, index} <- Enum.at(state.choices, number - 1) do
      {:ok, index}
    else
      _invalid -> {:error, "#{entry} is not one of the numbers listed."}
    end
  end
end
