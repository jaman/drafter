defmodule Drafter.ContentRenderer do
  @moduledoc false

  alias Drafter.Draw.{Segment, Strip}

  @doc """
  Render a component tree (vertical layout) to a list of strips.
  """
  def render_vertical_layout(components, width, height) do
    render_vertical_layout(components, 0, 0, width, height, %{})
  end

  defp render_vertical_layout(components, x, y, width, height, _opts) do
    rect = %{x: x, y: y, width: width, height: height}

    Enum.flat_map(components, fn component ->
      render_component_to_strips(component, rect)
    end)
  end

  defp render_component_to_strips({:label, text, opts}, rect), do: render_label(text, opts, rect)
  defp render_component_to_strips({:button, text, opts}, rect), do: render_button(text, opts, rect)
  defp render_component_to_strips({:checkbox, label, opts}, rect), do: render_checkbox(label, opts, rect)
  defp render_component_to_strips({:text_input, opts}, rect), do: render_text_input(opts, rect)
  defp render_component_to_strips({:text_area, opts}, rect), do: render_text_area(opts, rect)
  defp render_component_to_strips({:loading_indicator, opts}, rect), do: render_loading_indicator(opts, rect)
  defp render_component_to_strips({:link, text, opts}, rect), do: render_link(text, opts, rect)
  defp render_component_to_strips({:masked_input, opts}, rect), do: render_masked_input(opts, rect)
  defp render_component_to_strips({:log, opts}, rect), do: render_log(opts, rect)
  defp render_component_to_strips({:rich_log, opts}, rect), do: render_rich_log(opts, rect)
  defp render_component_to_strips({:pretty, data, opts}, rect), do: render_pretty(data, opts, rect)
  defp render_component_to_strips({:sparkline, data, opts}, rect), do: render_sparkline(data, opts, rect)
  defp render_component_to_strips({:progress_bar, opts}, rect), do: render_progress_bar(opts, rect)
  defp render_component_to_strips({:switch, opts}, rect), do: render_switch(opts, rect)
  defp render_component_to_strips({:digits, value, opts}, rect), do: render_digits(value, opts, rect)
  defp render_component_to_strips({:markdown, content, opts}, rect), do: render_markdown(content, opts, rect)
  defp render_component_to_strips({:placeholder, opts}, rect), do: render_placeholder(opts, rect)
  defp render_component_to_strips({:static, content, opts}, rect), do: render_static(content, opts, rect)
  defp render_component_to_strips({:rule, opts}, rect), do: render_rule(opts, rect)
  defp render_component_to_strips({:layout, :vertical, children, _opts}, rect), do: render_vertical_layout(children, rect.width, rect.height)
  defp render_component_to_strips({:layout, :horizontal, children, _opts}, rect), do: render_horizontal_layout(children, rect)
  defp render_component_to_strips(_, rect), do: render_empty(rect)

  defp render_label(text, opts, rect) do
    alias Drafter.Style.Computed

    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    computed = Computed.for_widget(:label, %{classes: classes}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    stripped_text = String.slice(text, 0, rect.width)
    padded = String.pad_trailing(stripped_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_button(text, opts, rect) do
    alias Drafter.Style.Computed

    button_type = Keyword.get(opts, :type, :default)
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    computed = Computed.for_widget(:button, %{type: button_type, classes: classes}, [])
    fg = computed[:color] || {255, 255, 255}
    bg = computed[:background] || {50, 50, 150}

    stripped_text = String.slice(text, 0, rect.width - 4)
    button_text = "[ #{stripped_text} ]"
    padded = String.pad_trailing(button_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_checkbox(label, opts, rect) do
    alias Drafter.Style.Computed

    checked = Keyword.get(opts, :checked, false)
    classes = Keyword.get(opts, :class, [])

    computed = Computed.for_widget(:checkbox, %{classes: classes}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    checkbox_str = if checked, do: "[✓]", else: "[ ]"
    text = "#{checkbox_str} #{label}"
    stripped_text = String.slice(text, 0, rect.width)
    padded = String.pad_trailing(stripped_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_text_input(_opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:text_input, %{}, [])
    fg = computed[:color] || {255, 255, 255}
    bg = computed[:background] || {50, 50, 50}

    text = String.pad_trailing("", rect.width - 2, " ")
    padded = "[ #{text}]"

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_text_area(_opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:text_area, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {40, 40, 40}

    lines = 1..rect.height
    |> Enum.map(fn _ ->
      String.duplicate(" ", rect.width - 2)
    end)

    lines
    |> Enum.map(fn line ->
      line = "│#{line}│"
      Strip.new([Segment.new(line, %{fg: fg, bg: bg})])
    end)
  end

  defp render_loading_indicator(opts, rect) do
    alias Drafter.Style.Computed

    spinner_type = Keyword.get(opts, :spinner_type, :default)
    running = Keyword.get(opts, :running, true)
    text = Keyword.get(opts, :text, "Loading...")

    computed = Computed.for_widget(:loading_indicator, %{}, [])
    fg = computed[:color] || {100, 200, 100}
    bg = computed[:background] || {30, 30, 30}

    spinner_char = if running do
      case spinner_type do
        :dots -> "⣾"
        :line -> "-"
        :arrow -> "→"
        _ -> "⠋"
      end
    else
      "✓"
    end

    display_text = "#{spinner_char} #{text}"
    stripped_text = String.slice(display_text, 0, rect.width)
    padded = String.pad_trailing(stripped_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_link(text, opts, rect) do
    alias Drafter.Style.Computed

    url = Keyword.get(opts, :url)

    computed = Computed.for_widget(:link, %{url: url}, [])
    fg = computed[:color] || {100, 150, 255}
    bg = computed[:background] || {30, 30, 30}

    display_text = if url, do: "#{text} (#{url})", else: text
    stripped_text = String.slice(display_text, 0, rect.width)
    padded = String.pad_trailing(stripped_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg, underline: true})])]
  end

  defp render_masked_input(opts, rect) do
    alias Drafter.Style.Computed

    mask = Keyword.get(opts, :mask, "###")

    computed = Computed.for_widget(:masked_input, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    stripped_mask = String.slice(mask, 0, rect.width)
    padded = String.pad_trailing(stripped_mask, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_log(opts, rect) do
    alias Drafter.Style.Computed

    lines = Keyword.get(opts, :lines, [])

    computed = Computed.for_widget(:log, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    lines
    |> Enum.take(rect.height)
    |> Enum.map(fn line ->
      stripped_line = String.slice(line, 0, rect.width - 4)
      padded = String.pad_trailing("│ #{stripped_line} │", rect.width, " ")
      Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])
    end)
  end

  defp render_rich_log(opts, rect) do
    alias Drafter.Style.Computed

    lines = Keyword.get(opts, :lines, [])

    computed = Computed.for_widget(:rich_log, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    lines
    |> Enum.take(rect.height)
    |> Enum.map(fn {line, _meta} ->
      stripped_line = String.slice(line, 0, rect.width - 4)
      padded = String.pad_trailing("│ #{stripped_line} │", rect.width, " ")
      Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])
    end)
  end

  defp render_pretty(data, opts, rect) do
    alias Drafter.Style.Computed

    expand = Keyword.get(opts, :expand, false)

    computed = Computed.for_widget(:pretty, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    formatted = format_pretty(data, expand)
    lines = String.split(formatted, "\n")

    lines
    |> Enum.take(rect.height)
    |> Enum.map(fn line ->
      stripped_line = String.slice(line, 0, rect.width)
      padded = String.pad_trailing(stripped_line, rect.width, " ")
      Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])
    end)
  end

  defp render_sparkline(data, opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:sparkline, %{}, [])
    fg = computed[:color] || {100, 200, 100}
    bg = computed[:background] || {30, 30, 30}

    summary = Keyword.get(opts, :summary, false)

    min_val = Enum.min(data)
    max_val = Enum.max(data)

    sparkline = render_sparkline_bars(data, min_val, max_val, rect.width - 20)

    summary_str = if summary do
      " min: #{min_val} max: #{max_val} avg: #{round(Enum.sum(data) / length(data))}"
    else
      ""
    end

    display_text = IO.iodata_to_binary([sparkline, summary_str])
    padded = String.pad_trailing(display_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_sparkline_bars(data, min_val, max_val, width) do
    range = max_val - min_val
    bars = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    Enum.map_join(Enum.take(data, width), fn value ->
      if range > 0 do
        normalized = (value - min_val) / range
        bar_index = round(normalized * 8)
        Enum.at(bars, min(8, max(0, bar_index)))
      else
        "▄"
      end
    end)
  end

  defp render_progress_bar(opts, rect) do
    alias Drafter.Style.Computed

    progress = Keyword.get(opts, :progress, 0.5)
    show_percentage = Keyword.get(opts, :show_percentage, true)

    computed = Computed.for_widget(:progress_bar, %{}, [])
    fg = computed[:color] || {100, 200, 100}
    bg = computed[:background] || {30, 30, 30}

    bar_width = rect.width - 2
    filled = round(progress * bar_width)
    empty = bar_width - filled

    bar = IO.iodata_to_binary(["[", String.duplicate("█", filled), String.duplicate("░", empty), "]"])

    display_text = if show_percentage do
      pct = round(progress * 100)
      "#{bar} #{pct}%"
    else
      bar
    end

    padded = String.pad_trailing(display_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_switch(opts, rect) do
    alias Drafter.Style.Computed

    active = Keyword.get(opts, :active, false)

    computed = Computed.for_widget(:switch, %{active: active}, [])
    on_fg = computed[:color] || {100, 255, 100}
    off_fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    switch_str = if active, do: "ON", else: "OFF"
    fg = if active, do: on_fg, else: off_fg

    display_text = "[ #{switch_str} ]"
    padded = String.pad_trailing(display_text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_digits(value, _opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:digits, %{}, [])
    fg = computed[:color] || {100, 200, 100}
    bg = computed[:background] || {30, 30, 30}

    digits_str = to_string(value)
    padded = String.pad_trailing(digits_str, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_markdown(content, _opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:markdown, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    lines = String.split(content, "\n")

    lines
    |> Enum.take(rect.height)
    |> Enum.map(fn line ->
      stripped_line = String.slice(line, 0, rect.width)
      padded = String.pad_trailing(stripped_line, rect.width, " ")
      Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])
    end)
  end

  defp render_placeholder(_opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:placeholder, %{}, [])
    fg = computed[:color] || {150, 150, 150}
    bg = computed[:background] || {30, 30, 30}

    text = "Placeholder #{rect.width}x#{rect.height}"
    padded = String.pad_trailing(text, rect.width, " ")

    [Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])]
  end

  defp render_static(content, _opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:static, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    lines = String.split(content, "\n")

    lines
    |> Enum.take(rect.height)
    |> Enum.map(fn line ->
      stripped_line = String.slice(line, 0, rect.width)
      padded = String.pad_trailing(stripped_line, rect.width, " ")
      Strip.new([Segment.new(padded, %{fg: fg, bg: bg})])
    end)
  end

  defp render_rule(_opts, rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:rule, %{}, [])
    fg = computed[:color] || {150, 150, 150}
    bg = computed[:background] || {30, 30, 30}

    rule = String.duplicate("─", rect.width)

    [Strip.new([Segment.new(rule, %{fg: fg, bg: bg})])]
  end

  defp render_horizontal_layout(children, rect) do
    gap = 2

    total_gap = gap * (max(0, length(children) - 1))
    available_width = rect.width - total_gap

    child_widths = calculate_child_widths(children, available_width)

    children_with_widths = Enum.zip(children, child_widths)

    all_child_strips = Enum.map(children_with_widths, fn {child, width} ->
      render_component_to_strips(child, %{rect | width: width})
    end)

    max_height = all_child_strips
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)

    if max_height == 0 do
      render_empty(rect)
    else
      Enum.map(0..(max_height - 1), fn line_index ->
        render_horizontal_line(children_with_widths, all_child_strips, line_index, gap)
      end)
    end
  end

  defp render_horizontal_line(children_with_widths, all_child_strips, line_index, gap) do
    segments = Enum.with_index(children_with_widths)
    |> Enum.flat_map(fn {{_child, width}, child_index} ->
      child_strips = Enum.at(all_child_strips, child_index, [])
      strip = Enum.at(child_strips, line_index)

      item_segments = if strip do
        strip.segments
      else
        fg = {200, 200, 200}
        bg = {30, 30, 30}
        [Segment.new(String.duplicate(" ", width), %{fg: fg, bg: bg})]
      end

      gap_segments = if child_index < length(children_with_widths) - 1 do
        fg = {200, 200, 200}
        bg = {30, 30, 30}
        [Segment.new(String.duplicate(" ", gap), %{fg: fg, bg: bg})]
      else
        []
      end

      item_segments ++ gap_segments
    end)

    Strip.new(segments)
  end

  defp calculate_child_widths([], _available_width), do: []

  defp calculate_child_widths(children, available_width) do
    num_children = length(children)
    base_width = div(available_width, num_children)
    remainder = rem(available_width, num_children)

    Enum.map(0..(num_children - 1), fn index ->
      child_width(base_width, index, remainder)
    end)
  end

  defp child_width(base_width, index, remainder) when index < remainder, do: base_width + 1
  defp child_width(base_width, _index, _remainder), do: base_width

  defp render_empty(rect) do
    alias Drafter.Style.Computed

    computed = Computed.for_widget(:label, %{}, [])
    fg = computed[:color] || {200, 200, 200}
    bg = computed[:background] || {30, 30, 30}

    text = String.duplicate(" ", rect.width)
    [Strip.new([Segment.new(text, %{fg: fg, bg: bg})])]
  end

  defp format_pretty(data, _expand) when is_nil(data), do: "nil"
  defp format_pretty(data, _expand) when is_boolean(data), do: "#{data}"
  defp format_pretty(data, _expand) when is_atom(data), do: ":#{data}"
  defp format_pretty(data, _expand) when is_integer(data), do: "#{data}"
  defp format_pretty(data, _expand) when is_float(data), do: "#{data}"
  defp format_pretty(data, _expand) when is_binary(data), do: inspect(data, binaries: :as_strings)

  defp format_pretty(data, expand) when is_list(data) do
    if Keyword.keyword?(data) do
      format_keyword(data, expand)
    else
      format_list(data, expand)
    end
  end

  defp format_pretty(data, expand) when is_map(data) do
    if Map.has_key?(data, :__struct__) && Map.get(data, :__struct__) != nil do
      format_struct(data, expand)
    else
      format_map(data, expand)
    end
  end

  defp format_list(data, false), do: "[#{Enum.map_join(data, ", ", &format_simple/1)}]"
  defp format_list(data, true) do
    inner = Enum.map_join(data, ",\n  ", &format_simple/1)
    "[\n  #{inner}\n]"
  end

  defp format_keyword(data, false) do
    pairs = Enum.map(data, fn {k, v} -> "#{format_simple(k)}: #{format_simple(v)}" end)
    "[#{Enum.join(pairs, ", ")}]"
  end
  defp format_keyword(data, true) do
    pairs = Enum.map(data, fn {k, v} -> "#{format_simple(k)}: #{format_simple(v)}" end)
    "[\n  #{Enum.join(pairs, ",\n  ")}\n]"
  end

  defp format_map(data, false) do
    pairs = Enum.map(data, fn {k, v} -> "#{format_simple(k)} => #{format_simple(v)}" end)
    "%{#{Enum.join(pairs, ", ")}}"
  end
  defp format_map(data, true) do
    pairs = Enum.map(data, fn {k, v} -> "#{format_simple(k)} => #{format_simple(v)}" end)
    "%{\n  #{Enum.join(pairs, ",\n  ")}\n}"
  end

  defp format_struct(data, false) do
    fields = data |> Map.delete(:__struct__) |> Enum.map(fn {k, v} -> "#{format_simple(k)}: #{format_simple(v)}" end)
    struct_name = data.__struct__ |> Module.split() |> List.last()
    "%#{struct_name}{#{Enum.join(fields, ", ")}}"
  end
  defp format_struct(data, true) do
    fields = data |> Map.delete(:__struct__) |> Enum.map(fn {k, v} -> "#{format_simple(k)}: #{format_simple(v)}" end)
    struct_name = data.__struct__ |> Module.split() |> List.last()
    "%#{struct_name}{\n  #{Enum.join(fields, ",\n  ")}\n}"
  end

  defp format_simple(item) when is_nil(item), do: "nil"
  defp format_simple(item) when is_boolean(item), do: "#{item}"
  defp format_simple(item) when is_atom(item), do: ":#{item}"
  defp format_simple(item) when is_integer(item), do: "#{item}"
  defp format_simple(item) when is_float(item), do: "#{item}"
  defp format_simple(item) when is_binary(item), do: inspect(item, binaries: :as_strings)
  defp format_simple(_item), do: "..."
end
