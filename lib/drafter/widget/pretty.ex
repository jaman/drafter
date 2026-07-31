defmodule Drafter.Widget.Pretty do
  @moduledoc """
  Renders any Elixir term with syntax-highlighted pretty-printing.

  Atoms use atom key syntax (`key: value`) for maps with atom keys, and
  `=>` only for non-atom keys, mirroring idiomatic Elixir syntax. Structs
  are displayed with their short module name. The `:expand` option forces
  multi-line output with one entry per line.

  ## Options

    * `:data` - any Elixir term to display
    * `:expand` - render collections multi-line: `true` / `false` (default)
    * `:syntax_highlighting` - apply colour to tokens: `true` (default) / `false`
    * `:style` - map of style properties
    * `:classes` - list of theme class atoms

  ## Usage

      pretty(data: %{name: "Alice", age: 30, active: true})
      pretty(data: my_struct, expand: true)
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

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 5)

  def component_tag, do: :pretty

  def from_component_opts(data, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      data: data,
      expand: Keyword.get(opts, :expand, false),
      syntax_highlighting: Keyword.get(opts, :syntax_highlighting, true),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

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

  @impl Drafter.Widget
  def handle_event(_event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    {:noreply, state}
  end

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

  def syntax_colors, do: @syntax_colors

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
