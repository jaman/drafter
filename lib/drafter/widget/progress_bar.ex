defmodule Drafter.Widget.ProgressBar do
  @moduledoc """
  Renders a horizontal progress bar with optional percentage, value, and ETA display.

  Supports both a determinate mode (showing progress toward a known maximum) and
  an indeterminate mode that animates a sliding block when the total is unknown.

  ## Options

    * `:progress` - current progress value (default `0.0`)
    * `:max_value` - maximum value representing 100% (default `100.0`)
    * `:label` - optional label text displayed alongside the bar
    * `:show_percentage` - show percentage text: `true` (default) / `false`
    * `:show_value` - show raw value text: `true` / `false` (default)
    * `:show_eta` - show estimated time remaining: `true` (default) / `false`
    * `:indeterminate` - animated sliding mode: `true` / `false` (default)
    * `:width` - bar width in columns (default `50`)
    * `:height` - bar height in rows (default `1`)

  ## Usage

      progress_bar(progress: 42.0, max_value: 100.0)
      progress_bar(progress: 7, max_value: 20, show_percentage: false, show_value: true)
      progress_bar(indeterminate: true)
  """

  use Drafter.Widget

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :progress,
    :max_value,
    :label,
    :show_percentage,
    :show_value,
    :show_eta,
    :width,
    :height,
    :indeterminate,
    :start_time,
    :last_update_time,
    :last_progress,
    :spin_position
  ]

  @impl Drafter.Widget
  def mount(props) do
    current_time = System.monotonic_time(:millisecond)
    indeterminate = Map.get(props, :indeterminate, false)

    %__MODULE__{
      progress: Map.get(props, :progress, 0.0),
      max_value: Map.get(props, :max_value, 100.0),
      label: Map.get(props, :label),
      show_percentage: Map.get(props, :show_percentage, true),
      show_value: Map.get(props, :show_value, false),
      show_eta: Map.get(props, :show_eta, true),
      width: Map.get(props, :width, 50),
      height: Map.get(props, :height, 1),
      indeterminate: indeterminate,
      start_time: current_time,
      last_update_time: current_time,
      last_progress: Map.get(props, :progress, 0.0),
      spin_position: 0
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    normalized_state =
      if is_struct(state, __MODULE__) do
        state
      else
        mount(state)
      end

    computed = Computed.for_widget(:progress_bar, normalized_state)
    bar_computed = Computed.for_part(:progress_bar, normalized_state, :bar)
    track_computed = Computed.for_part(:progress_bar, normalized_state, :track)

    bg_style = Computed.to_segment_style(computed)
    bar_color = bar_computed[:color] || {0, 178, 255}
    empty_color = track_computed[:color] || {60, 60, 60}
    text_color = bg_style[:fg] || {150, 150, 150}
    bg_color = bg_style[:bg] || {30, 30, 30}

    segments =
      if normalized_state.indeterminate do
        render_indeterminate(normalized_state, rect, bar_color, empty_color, bg_color)
      else
        render_determinate(normalized_state, rect, bar_color, empty_color, text_color, bg_color)
      end

    strip = Strip.new(Enum.reverse(segments))

    if rect.height > 1 do
      empty_line = Segment.new(String.duplicate(" ", rect.width), %{fg: text_color, bg: bg_color})
      empty_strip = Strip.new([empty_line])
      padding = List.duplicate(empty_strip, rect.height - 1)
      [strip | padding]
    else
      [strip]
    end
  end

  @impl Drafter.Widget
  def handle_event(_event, state) do
    {:noreply, state}
  end

  @impl Drafter.Widget
  def update(props, state) do
    current_time = System.monotonic_time(:millisecond)
    new_progress = Map.get(props, :progress, state.progress)
    indeterminate = Map.get(props, :indeterminate, state.indeterminate)

    new_spin_position =
      if indeterminate do
        rem(state.spin_position + 1, 40)
      else
        state.spin_position
      end

    %{
      state
      | progress: new_progress,
        max_value: Map.get(props, :max_value, state.max_value),
        label: Map.get(props, :label, state.label),
        show_percentage: Map.get(props, :show_percentage, state.show_percentage),
        show_value: Map.get(props, :show_value, state.show_value),
        show_eta: Map.get(props, :show_eta, state.show_eta),
        width: Map.get(props, :width, state.width),
        height: Map.get(props, :height, state.height),
        indeterminate: indeterminate,
        last_update_time: current_time,
        last_progress: new_progress,
        spin_position: new_spin_position
    }
  end

  defp render_determinate(state, rect, bar_color, empty_color, text_color, bg_color) do
    percentage =
      if state.max_value > 0 do
        (state.progress / state.max_value) |> min(1.0) |> max(0.0)
      else
        0.0
      end

    status_text = build_status_text(state, percentage)

    status_width = String.length(status_text)
    bar_width = max(0, rect.width - status_width)

    completed_width = round(percentage * bar_width)
    empty_width = bar_width - completed_width

    segments = []

    segments =
      if completed_width > 0 do
        completed_text = String.duplicate(CharacterSet.box(:h_bold), completed_width)
        [Segment.new(completed_text, %{fg: bar_color, bg: bg_color}) | segments]
      else
        segments
      end

    segments =
      if empty_width > 0 do
        empty_text = String.duplicate(CharacterSet.box(:h_bold), empty_width)
        [Segment.new(empty_text, %{fg: empty_color, bg: bg_color}) | segments]
      else
        segments
      end

    if String.length(status_text) > 0 do
      [Segment.new(status_text, %{fg: text_color, bg: bg_color}) | segments]
    else
      segments
    end
  end

  defp render_indeterminate(_state, %{width: width}, _bar, _empty, _bg) when width <= 0, do: []

  defp render_indeterminate(state, rect, bar_color, empty_color, bg_color) do
    bar_width = rect.width
    spinner_width = min(10, div(bar_width, 4))

    spin_start = rem(state.spin_position, bar_width + spinner_width) - spinner_width
    spin_start = max(0, min(spin_start, bar_width - spinner_width))

    segments = []

    segments =
      if spin_start > 0 do
        empty_text = String.duplicate(CharacterSet.box(:h_bold), spin_start)
        [Segment.new(empty_text, %{fg: empty_color, bg: bg_color}) | segments]
      else
        segments
      end

    segments =
      if spinner_width > 0 do
        spin_text = String.duplicate(CharacterSet.box(:h_double), spinner_width)
        [Segment.new(spin_text, %{fg: bar_color, bg: bg_color}) | segments]
      else
        segments
      end

    remaining_width = bar_width - spin_start - spinner_width

    segments =
      if remaining_width > 0 do
        empty_text = String.duplicate(CharacterSet.box(:h_bold), remaining_width)
        [Segment.new(empty_text, %{fg: empty_color, bg: bg_color}) | segments]
      else
        segments
      end

    segments
  end

  defp build_status_text(%{show_percentage: true, show_eta: true} = state, percentage) do
    " #{round(percentage * 100)}% #{calculate_eta(state, percentage)}"
  end

  defp build_status_text(%{show_percentage: true}, percentage), do: " #{round(percentage * 100)}%"

  defp build_status_text(%{show_eta: true} = state, percentage),
    do: " #{calculate_eta(state, percentage)}"

  defp build_status_text(_, _percentage), do: ""

  defp calculate_eta(state, percentage) when percentage > 0.001 and state.progress > 0 do
    elapsed = System.monotonic_time(:millisecond) - state.start_time
    compute_eta(state, elapsed)
  end

  defp calculate_eta(_state, _percentage), do: "..."

  defp compute_eta(_state, elapsed) when elapsed <= 1000, do: "..."

  defp compute_eta(state, elapsed) do
    rate = state.progress / elapsed
    if rate > 0, do: format_eta(round((state.max_value - state.progress) / rate)), else: "∞"
  end

  defp format_eta(milliseconds) do
    seconds = div(milliseconds, 1000)

    cond do
      seconds < 60 ->
        "#{seconds}s"

      seconds < 3600 ->
        mins = div(seconds, 60)
        secs = rem(seconds, 60)
        "#{mins}m #{secs}s"

      true ->
        hours = div(seconds, 3600)
        mins = div(rem(seconds, 3600), 60)
        "#{hours}h #{mins}m"
    end
  end

  def preferred_height(_args, opts) do
    if Keyword.get(opts, :orientation, :horizontal) == :vertical, do: 8, else: 1
  end

  def component_tag, do: :progress_bar

  def from_component_opts(_args, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 50, height: 1})
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      progress: Keyword.get(opts, :progress, 0.0),
      max_value: Keyword.get(opts, :max_value, 100.0),
      label: Keyword.get(opts, :label),
      show_percentage: Keyword.get(opts, :show_percentage, true),
      show_value: Keyword.get(opts, :show_value, false),
      show_eta: Keyword.get(opts, :show_eta, true),
      indeterminate: Keyword.get(opts, :indeterminate, false),
      pulse: Keyword.get(opts, :pulse, false),
      classes: classes,
      width: Keyword.get(opts, :width, rect.width),
      height: Keyword.get(opts, :height, rect.height)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      progress: mount_props.progress,
      max_value: mount_props.max_value,
      label: mount_props.label,
      show_percentage: mount_props.show_percentage,
      show_value: mount_props.show_value,
      indeterminate: mount_props.indeterminate,
      classes: mount_props.classes
    }
  end

  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    case Drafter.RingBuffer.last(buffer) do
      nil -> state
      value -> %{state | progress: value}
    end
  end
end
