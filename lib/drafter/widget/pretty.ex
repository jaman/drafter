defmodule Drafter.Widget.Pretty do
  @moduledoc """
  Renders an Elixir term with syntax-highlighted pretty-printing.

  Maps and keyword lists print an atom key as `:key: value` and every other key as
  `key => value`. Structs are displayed with the last segment of their module name.
  The `:expand` option forces multi-line output with one entry per line.

  Collections nested inside a collection are not descended into: they print as
  `...`. Only `nil`, booleans, atoms, integers, floats, binaries, lists, keyword
  lists, maps and structs can be rendered at the top level — any other term, a
  tuple or a pid among them, raises `FunctionClauseError` from `format_pretty/3`.

  ## Component tag

  Tag `:pretty`, built by `Drafter.App` as `{:pretty, data, opts}`:

      pretty(data, opts)

  The positional argument becomes `:data` directly; it is never re-read from
  `opts`. Pass the term positionally. Writing `pretty(data: term)` puts a keyword
  list in the positional slot, which the renderer then treats as options, leaving
  `:data` as `nil` and rendering nothing.

  ## Options

    * `:data` - the term to display. Default `nil`, which renders the text `nil`.
      Supplied positionally through the `pretty/2` element.
    * `:expand` - `t:boolean/0`, put one entry per line. Default `false`.
    * `:syntax_highlighting` - `t:boolean/0`, colour the tokens. Default `true`.
    * `:style` - `t:map/0` of style overrides passed to the theme computation.
      Default `%{}`.
    * `:class` - theme class atom or list of them, normalised by
      `Drafter.Style.normalize_classes/1` and reaching `mount/1` as `:classes`.
      Default `[]`.
    * `:height` - `t:pos_integer/0` read only by `preferred_height/2`, never by
      `mount/1`. Default `5`.

  `update/2` accepts every option above. Through the component tree only `:data`
  is live-updatable — `update_props_from_mount/3` returns `:data` and
  `:app_module` alone, so `:expand`, `:syntax_highlighting`, `:style` and
  `:classes` are mount-only.

  ## Usage

      pretty(%{name: "Alice", age: 30, active: true})
      pretty(my_struct, expand: true)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @syntax_colors %{
    nil: {150, 150, 150},
    boolean: {86, 156, 214},
    atom: {86, 156, 214},
    integer: {181, 206, 168},
    float: {181, 206, 168},
    string: {235, 203, 139},
    keyword_key: {86, 156, 214},
    map_key: {156, 220, 254},
    struct_name: {255, 255, 255},
    separator: {150, 150, 150},
    default: {200, 200, 200}
  }

  defstruct [
    :data,
    :style,
    :classes,
    :app_module,
    :expand,
    :syntax_highlighting
  ]

  @type t :: %__MODULE__{
          data: term(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          expand: boolean(),
          syntax_highlighting: boolean()
        }

  @doc """
  Builds the widget state from `props`.

  Reads `:data` (default `nil`), `:expand` (default `false`),
  `:syntax_highlighting` (default `true`), `:style` (default `%{}`), `:classes`
  (default `[]`) and `:app_module` (default `nil`).

      iex> state = Drafter.Widget.Pretty.mount(%{data: %{a: 1}})
      iex> {state.data, state.expand, state.syntax_highlighting}
      {%{a: 1}, false, true}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      data: Map.get(props, :data),
      expand: Map.get(props, :expand, false),
      syntax_highlighting: Map.get(props, :syntax_highlighting, true),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @doc """
  Draws the formatted term into `rect`, one strip per line of output.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. Each line is padded with spaces or truncated to `rect.width`. The number
  of strips follows the formatted term, not `rect.height`.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    classes = state.classes
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:pretty, state, computed_opts)

    default_bg = computed[:background] || {30, 30, 30}

    colorized = format_pretty(state.data, state.syntax_highlighting, state.expand)

    lines = String.split(colorized, "\n")

    Enum.map(lines, fn line ->
      segments = parse_colorized_line(line, default_bg)
      padded_segments = pad_and_truncate(segments, rect.width, default_bg)
      Strip.new(padded_segments)
    end)
  end

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `5`.

      iex> Drafter.Widget.Pretty.preferred_height(nil, [])
      5

      iex> Drafter.Widget.Pretty.preferred_height(%{a: 1}, height: 12)
      12
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Pretty.component_tag()
      :pretty
  """
  @spec component_tag() :: :pretty
  def component_tag, do: :pretty

  @doc """
  Builds the props map for a `{:pretty, data, opts}` element.

  `data` becomes `:data` as it stands and is never re-read from `opts`, so
  `pretty(data: term)` leaves `:data` as the keyword list itself only if the
  renderer passes it positionally. `:class` is normalised into `:classes` and
  `:__app_module__` becomes `:app_module`.

      iex> props = Drafter.Widget.Pretty.from_component_opts(%{a: 1}, expand: true)
      iex> {props.data, props.expand, props.syntax_highlighting, props.classes}
      {%{a: 1}, true, true, []}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(data, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    %{
      data: data,
      expand: Keyword.get(opts, :expand, false),
      syntax_highlighting: Keyword.get(opts, :syntax_highlighting, true),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Narrows a re-render to `:data` and `:app_module`.

  `:expand`, `:syntax_highlighting`, `:style` and `:classes` are dropped, so they
  are mount-only through the component tree.

      iex> props = Drafter.Widget.Pretty.from_component_opts(%{a: 1}, expand: true)
      iex> Drafter.Widget.Pretty.update_props_from_mount(props, %{}, [])
      %{data: %{a: 1}, app_module: nil}
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      data: mount_props.data,
      app_module: mount_props.app_module
    }
  end

  defp parse_colorized_line(line, bg) do
    case line do
      "" ->
        [Segment.new(" ", %{fg: @syntax_colors.default, bg: bg})]

      _ ->
        case Regex.run(~r/^(.+?)§(\{[^}]+\})(.*)$/, line, capture: :all_but_first) do
          [text, color_spec, rest] ->
            color = parse_color_spec(color_spec)
            [Segment.new(text, %{fg: color, bg: bg}) | parse_colorized_line(rest, bg)]

          nil ->
            [Segment.new(line, %{fg: @syntax_colors.default, bg: bg})]
        end
    end
  end

  @syntax_color_lookup Map.new(@syntax_colors, fn {k, v} -> {Atom.to_string(k), v} end)

  @doc """
  The `{r, g, b}` colour for a `"{token_kind}"` marker.

  `spec` must start with `{` — anything else raises `FunctionClauseError`. An
  unknown token kind falls back to the `:default` colour, `{200, 200, 200}`.

      iex> Drafter.Widget.Pretty.parse_color_spec("{integer}")
      {181, 206, 168}

      iex> Drafter.Widget.Pretty.parse_color_spec("{not_a_token}")
      {200, 200, 200}
  """
  @spec parse_color_spec(String.t()) :: {0..255, 0..255, 0..255}
  def parse_color_spec("{" <> spec) do
    key = String.slice(spec, 0..-2//1)
    Map.get(@syntax_color_lookup, key, @syntax_colors.default)
  end

  defp pad_and_truncate(segments, width, bg) do
    current_width =
      Enum.reduce(segments, 0, fn seg, acc ->
        acc + String.length(seg.text)
      end)

    cond do
      current_width < width ->
        padding = String.duplicate(" ", width - current_width)
        segments ++ [Segment.new(padding, %{fg: @syntax_colors.separator, bg: bg})]

      current_width > width ->
        truncate_segments(segments, width)

      true ->
        segments
    end
  end

  defp truncate_segments(segments, max_width) do
    Enum.reduce_while(segments, {[], 0}, fn segment, {acc, current_width} ->
      truncate_single_segment(segment, acc, current_width, max_width)
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp truncate_single_segment(segment, acc, current_width, max_width) do
    segment_width = String.length(segment.text)
    new_width = current_width + segment_width

    cond do
      new_width <= max_width ->
        {:cont, {[segment | acc], new_width}}

      max_width - current_width > 0 ->
        truncated = String.slice(segment.text, 0, max_width - current_width)
        {:halt, {[Segment.new(truncated, segment.style) | acc], max_width}}

      true ->
        {:halt, {acc, current_width}}
    end
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`.

  A plain props map is passed through `mount/1` first, so the returned state is
  always a `t:t/0`. The widget is not focusable.
  """
  @spec handle_event(Drafter.Event.t(), t() | Drafter.Widget.props()) :: {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(_event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    {:noreply, state}
  end

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  Accepts `:data`, `:expand`, `:syntax_highlighting`, `:style`, `:classes` and
  `:app_module`. A `:data` of `nil` in `props` counts as a value and clears the
  term.

      iex> state = Drafter.Widget.Pretty.mount(%{data: 1})
      iex> updated = Drafter.Widget.Pretty.update(%{expand: true}, state)
      iex> {updated.data, updated.expand}
      {1, true}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | data: Map.get(props, :data, state.data),
        expand: Map.get(props, :expand, state.expand),
        syntax_highlighting: Map.get(props, :syntax_highlighting, state.syntax_highlighting),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  @doc """
  The token colour table, keyed by token kind.

      iex> Drafter.Widget.Pretty.syntax_colors() |> Map.keys() |> Enum.sort()
      [:atom, :boolean, :default, :float, :integer, :keyword_key, :map_key, nil, :separator, :string, :struct_name]

      iex> Drafter.Widget.Pretty.syntax_colors().string
      {235, 203, 139}
  """
  @spec syntax_colors() :: %{atom() => {0..255, 0..255, 0..255}}
  def syntax_colors, do: @syntax_colors

  @doc """
  Formats `data` into the widget's marked-up text.

  With `highlight` set, each token is followed by a `§{kind}` marker that
  `render/2` turns into a colour; without it the result is plain text. `expand`
  puts one entry of a collection per line.

  Handles `nil`, booleans, atoms, integers, floats, binaries, lists, keyword lists,
  maps and structs. Any other term raises `FunctionClauseError`.

      iex> Drafter.Widget.Pretty.format_pretty(nil, false, false)
      "nil"

      iex> Drafter.Widget.Pretty.format_pretty(42, true, false)
      "42§{integer}"

      iex> Drafter.Widget.Pretty.format_pretty("hi", false, false)
      "\\"hi\\""

      iex> Drafter.Widget.Pretty.format_pretty([1, 2, 3], false, false)
      "[1, 2, 3]"

      iex> Drafter.Widget.Pretty.format_pretty([a: 1, b: 2], false, false)
      "[:a: 1, :b: 2]"

      iex> Drafter.Widget.Pretty.format_pretty(%{a: 1}, false, false)
      "%{:a: 1}"

      iex> Drafter.Widget.Pretty.format_pretty(%{"k" => 1}, false, false)
      "%{\\"k\\" => 1}"

      iex> Drafter.Widget.Pretty.format_pretty([1, [2]], false, false)
      "[1, ...]"
  """
  @spec format_pretty(term(), boolean(), boolean()) :: String.t()
  def format_pretty(data, highlight, _expand) when is_nil(data) do
    if highlight, do: "nil§{nil}", else: "nil"
  end

  def format_pretty(data, highlight, _expand) when is_boolean(data) do
    if highlight, do: "#{data}§{boolean}", else: "#{data}"
  end

  def format_pretty(data, highlight, _expand) when is_atom(data) do
    if highlight, do: ":#{data}§{atom}", else: ":#{data}"
  end

  def format_pretty(data, highlight, _expand) when is_integer(data) do
    if highlight, do: "#{data}§{integer}", else: "#{data}"
  end

  def format_pretty(data, highlight, _expand) when is_float(data) do
    if highlight, do: "#{data}§{float}", else: "#{data}"
  end

  def format_pretty(data, highlight, _expand) when is_binary(data) do
    inspected = inspect(data, binaries: :as_strings)

    if highlight do
      "#{inspected}§{string}"
    else
      inspected
    end
  end

  def format_pretty(data, highlight, expand) when is_list(data) do
    if Keyword.keyword?(data) do
      format_keyword(data, highlight, expand)
    else
      format_list(data, highlight, expand)
    end
  end

  def format_pretty(data, highlight, expand) when is_map(data) do
    if Map.has_key?(data, :__struct__) && Map.get(data, :__struct__) != nil do
      format_struct(data, highlight, expand)
    else
      format_map(data, highlight, expand)
    end
  end

  @doc """
  Formats a plain list. Each element goes through `format_simple/2`, so a nested
  collection prints as `...`.

      iex> Drafter.Widget.Pretty.format_list([1, 2], false, false)
      "[1, 2]"

      iex> Drafter.Widget.Pretty.format_list([1, 2], false, true)
      "[\\n  1,\\n  2\\n]"
  """
  @spec format_list(list(), boolean(), boolean()) :: String.t()
  def format_list(data, highlight, false) do
    inner = Enum.map_join(data, ", ", &format_simple(&1, highlight))
    separator = if highlight, do: "§{separator}", else: ""
    "[#{separator}#{inner}#{separator}]#{separator}"
  end

  def format_list(data, highlight, true) do
    inner = Enum.map_join(data, ",\n  ", &format_simple(&1, highlight))
    separator = if highlight, do: "§{separator}", else: ""
    "[#{separator}\n  #{inner}\n]#{separator}"
  end

  @doc """
  Formats a keyword list. Keys are written with a leading colon and a trailing
  colon, so `[a: 1]` prints as `[:a: 1]`.

      iex> Drafter.Widget.Pretty.format_keyword([a: 1, b: 2], false, false)
      "[:a: 1, :b: 2]"

      iex> Drafter.Widget.Pretty.format_keyword([a: 1], false, true)
      "[\\n  :a: 1\\n]"
  """
  @spec format_keyword(keyword(), boolean(), boolean()) :: String.t()
  def format_keyword(data, highlight, false) do
    pairs =
      Enum.map(data, fn {k, v} ->
        key_str =
          if highlight, do: ":#{Atom.to_string(k)}§{keyword_key}", else: ":#{Atom.to_string(k)}"

        "#{key_str}: #{format_simple(v, highlight)}"
      end)

    separator = if highlight, do: "§{separator}", else: ""
    "[#{separator}#{Enum.join(pairs, ", ")}]#{separator}"
  end

  def format_keyword(data, highlight, true) do
    pairs =
      Enum.map(data, fn {k, v} ->
        key_str =
          if highlight, do: ":#{Atom.to_string(k)}§{keyword_key}", else: ":#{Atom.to_string(k)}"

        "#{key_str}: #{format_simple(v, highlight)}"
      end)

    separator = if highlight, do: "§{separator}", else: ""
    "[#{separator}\n  #{Enum.join(pairs, ",\n  ")}\n]#{separator}"
  end

  @doc """
  Formats a map that is not a struct, one `format_pair/3` per entry in key order.

      iex> Drafter.Widget.Pretty.format_map(%{a: 1}, false, false)
      "%{:a: 1}"

      iex> Drafter.Widget.Pretty.format_map(%{a: 1}, false, true)
      "%{\\n  :a: 1\\n}"
  """
  @spec format_map(map(), boolean(), boolean()) :: String.t()
  def format_map(data, highlight, false) do
    pairs =
      Enum.map(data, fn {k, v} ->
        format_pair(k, v, highlight)
      end)

    separator = if highlight, do: "§{separator}", else: ""
    "%#{separator}{#{Enum.join(pairs, ", ")}}#{separator}"
  end

  def format_map(data, highlight, true) do
    pairs =
      Enum.map(data, fn {k, v} ->
        format_pair(k, v, highlight)
      end)

    separator = if highlight, do: "§{separator}", else: ""
    "%#{separator}{\n  #{Enum.join(pairs, ",\n  ")}\n}#{separator}"
  end

  @doc """
  Formats one map entry.

  An atom key becomes `:key: value`; every other key becomes `key => value`.

      iex> Drafter.Widget.Pretty.format_pair(:a, 1, false)
      ":a: 1"

      iex> Drafter.Widget.Pretty.format_pair("k", 1, false)
      "\\"k\\" => 1"
  """
  @spec format_pair(term(), term(), boolean()) :: String.t()
  def format_pair(k, v, highlight) when is_atom(k) do
    key_str =
      if highlight, do: ":#{Atom.to_string(k)}§{keyword_key}", else: ":#{Atom.to_string(k)}"

    "#{key_str}: #{format_simple(v, highlight)}"
  end

  def format_pair(k, v, highlight) do
    key_str =
      if highlight,
        do: "#{format_simple(k, highlight)}§{map_key}",
        else: format_simple(k, highlight)

    "#{key_str} => #{format_simple(v, highlight)}"
  end

  @doc """
  Formats a struct, headed by the last segment of its module name.

  Field names go through `format_simple/2`, so they carry a leading colon.

      iex> Drafter.Widget.Pretty.format_struct(1..3, false, false)
      "%Range{:first: 1, :last: 3, :step: 1}"

      iex> Drafter.Widget.Pretty.format_struct(1..2//1, false, true)
      "%Range{\\n  :first: 1,\\n  :last: 2,\\n  :step: 1\\n}"
  """
  @spec format_struct(struct(), boolean(), boolean()) :: String.t()
  def format_struct(data, highlight, false) do
    fields =
      data
      |> Map.delete(:__struct__)
      |> Enum.map(fn {k, v} ->
        "#{format_simple(k, highlight)}: #{format_simple(v, highlight)}"
      end)

    struct_name = data.__struct__ |> Module.split() |> List.last()
    name_str = if highlight, do: "%#{struct_name}§{struct_name}", else: "%#{struct_name}"
    "#{name_str}{#{Enum.join(fields, ", ")}}"
  end

  def format_struct(data, highlight, true) do
    fields =
      data
      |> Map.delete(:__struct__)
      |> Enum.map(fn {k, v} ->
        "#{format_simple(k, highlight)}: #{format_simple(v, highlight)}"
      end)

    struct_name = data.__struct__ |> Module.split() |> List.last()
    name_str = if highlight, do: "%#{struct_name}§{struct_name}", else: "%#{struct_name}"
    "#{name_str}{\n  #{Enum.join(fields, ",\n  ")}\n}"
  end

  @doc """
  Formats a single value nested inside a collection.

  Handles `nil`, booleans, atoms, integers, floats and binaries. Anything else,
  including a nested list, map or tuple, returns `"..."` rather than recursing.

      iex> Drafter.Widget.Pretty.format_simple(:ok, false)
      ":ok"

      iex> Drafter.Widget.Pretty.format_simple(:ok, true)
      ":ok§{atom}"

      iex> Drafter.Widget.Pretty.format_simple([1, 2], false)
      "..."
  """
  @spec format_simple(term(), boolean()) :: String.t()
  def format_simple(item, highlight) when is_nil(item) do
    if highlight, do: "nil§{nil}", else: "nil"
  end

  def format_simple(item, highlight) when is_boolean(item) do
    if highlight, do: "#{item}§{boolean}", else: "#{item}"
  end

  def format_simple(item, highlight) when is_atom(item) do
    if highlight, do: ":#{item}§{atom}", else: ":#{item}"
  end

  def format_simple(item, highlight) when is_integer(item) do
    if highlight, do: "#{item}§{integer}", else: "#{item}"
  end

  def format_simple(item, highlight) when is_float(item) do
    if highlight, do: "#{item}§{float}", else: "#{item}"
  end

  def format_simple(item, highlight) when is_binary(item) do
    inspected = inspect(item, binaries: :as_strings)
    if highlight, do: "#{inspected}§{string}", else: inspected
  end

  def format_simple(_item, _highlight), do: "..."
end
