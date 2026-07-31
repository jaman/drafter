defmodule Drafter.Widget.Rule do
  @moduledoc """
  Renders a horizontal or vertical divider line, optionally with an embedded title.

  ## Options

    * `:orientation` - `:horizontal` (default) or `:vertical`
    * `:title` - optional string to embed in the centre of a horizontal rule
    * `:title_align` - `:left`, `:center` (default), `:right`
    * `:line_style` - `:solid` (default), `:double`, `:dashed`, `:thick`
    * `:style` - map of style overrides

  ## Usage

      rule()
      rule(title: "Section", line_style: :double)
      rule(orientation: :vertical)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @horizontal_chars %{solid: "─", double: "═", dashed: "╌", thick: "━"}
  @vertical_chars %{solid: "│", double: "║", dashed: "╎", thick: "┃"}

  defstruct orientation: :horizontal,
            title: nil,
            title_align: :center,
            style: %{},
            line_style: :solid,
            app_module: nil

  @type t :: %__MODULE__{
          orientation: :horizontal | :vertical,
          title: String.t() | nil,
          title_align: :left | :center | :right,
          style: map(),
          line_style: :solid | :double | :dashed | :thick,
          app_module: module() | nil
        }

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      orientation: Map.get(props, :orientation, :horizontal),
      title: Map.get(props, :title),
      title_align: Map.get(props, :title_align, :center),
      style: Map.get(props, :style, %{}),
      line_style: Map.get(props, :line_style, :solid),
      app_module: Map.get(props, :app_module)
    }
  end

  @impl Drafter.Widget
  def update(props, state) do
    Enum.reduce(props, state, fn {key, value}, acc ->
      case key do
        :orientation -> %{acc | orientation: value}
        :title -> %{acc | title: value}
        :title_align -> %{acc | title_align: value}
        :style -> %{acc | style: value}
        :line_style -> %{acc | line_style: value}
        :app_module -> %{acc | app_module: value}
        _ -> acc
      end
    end)
  end

  @impl Drafter.Widget
  def render(state, rect) do
    computed_opts = [style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:rule, state, computed_opts)
    segment_style = Computed.to_segment_style(computed)

    case state.orientation do
      :horizontal -> render_horizontal(state, rect, segment_style)
      :vertical -> render_vertical(state, rect, segment_style)
    end
  end

  @impl Drafter.Widget
  def handle_event(_event, state) do
    {:noreply, state}
  end

  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 1)

  def component_tag, do: :rule

  def from_component_opts(_args, opts) do
    %{
      orientation: Keyword.get(opts, :orientation, :horizontal),
      title: Keyword.get(opts, :title),
      title_align: Keyword.get(opts, :title_align, :center),
      style: Keyword.get(opts, :style, %{}),
      line_style: Keyword.get(opts, :line_style, :solid),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp render_horizontal(state, rect, segment_style) do
    line_char = Map.fetch!(@horizontal_chars, state.line_style)
    mid_row = div(rect.height, 2)
    empty_segment = Segment.new(String.duplicate(" ", rect.width), segment_style)

    Enum.map(0..(rect.height - 1)//1, fn row ->
      if row == mid_row do
        strip_segment = build_horizontal_line(state, rect.width, line_char, segment_style)
        Strip.new([strip_segment])
      else
        Strip.new([empty_segment])
      end
    end)
  end

  defp build_horizontal_line(%{title: nil}, width, line_char, segment_style) do
    Segment.new(String.duplicate(line_char, width), segment_style)
  end

  defp build_horizontal_line(%{title: title, title_align: align}, width, line_char, segment_style) do
    embedded = " " <> title <> " "
    embedded_len = String.length(embedded)

    if embedded_len >= width do
      Segment.new(String.slice(embedded, 0, width), segment_style)
    else
      remaining = width - embedded_len

      {left_count, right_count} =
        case align do
          :left ->
            {0, remaining}

          :right ->
            {remaining, 0}

          :center ->
            left = div(remaining, 2)
            {left, remaining - left}
        end

      text =
        String.duplicate(line_char, left_count) <>
          embedded <>
          String.duplicate(line_char, right_count)

      Segment.new(text, segment_style)
    end
  end

  defp render_vertical(_state, %{width: width}, _segment_style) when width <= 0, do: []

  defp render_vertical(state, rect, segment_style) do
    line_char = Map.fetch!(@vertical_chars, state.line_style)
    padding = String.duplicate(" ", rect.width - 1)

    Enum.map(0..(rect.height - 1)//1, fn _row ->
      seg = Segment.new(line_char <> padding, segment_style)
      Strip.new([seg])
    end)
  end
end
