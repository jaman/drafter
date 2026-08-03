defmodule Drafter.Widget.ProgressBar do
  @moduledoc """
  Renders a horizontal progress bar with optional percentage, value, and ETA display.

  Supports both a determinate mode (showing progress toward a known maximum) and
  an indeterminate mode that animates a sliding block when the total is unknown.

  ## Component tag

  Tag `:progress_bar`, built by `Drafter.App` as `{:progress_bar, opts}`:

      progress_bar(opts)

  There is no positional argument; every prop comes from `opts`.

  ## Options

    * `:progress` - `t:number/0` current progress. Default `0.0`. The filled
      fraction is `progress / max_value`, clamped into `0.0..1.0`.
    * `:max_value` - `t:number/0` value representing 100%. Default `100.0`. A
      `max_value` of `0` or less renders as 0%.
    * `:show_percentage` - `t:boolean/0`, append the rounded percentage. Default
      `true`.
    * `:show_eta` - `t:boolean/0`, append an estimated time remaining. Default
      `true`. Shows `"..."` until at least one second of wall clock has passed
      since mount and progress is above zero, then `"12s"`, `"3m 4s"` or
      `"1h 2m"`, and `"∞"` when the computed rate is not positive.
    * `:indeterminate` - `t:boolean/0`. Default `false`. Animates a sliding block
      whose position advances by one on each `update/2` and ignores `:progress`,
      `:show_percentage` and `:show_eta`.
    * `:label` - `t:String.t/0` or `nil`. Default `nil`. Held on the state and
      never drawn.
    * `:show_value` - `t:boolean/0`. Default `false`. Held on the state and never
      drawn; the status text is built from `:show_percentage` and `:show_eta` only.
    * `:width` - `t:pos_integer/0`. Default `50` when mounting directly, and the
      width of `opts[:__rect__]` through the element. Held on the state and never
      read by `render/2`, which uses the rect it is given.
    * `:height` - `t:pos_integer/0`. Default `1` when mounting directly, and the
      height of `opts[:__rect__]` through the element. Held on the state and never
      read by `render/2`.
    * `:pulse` - read by `from_component_opts/2` with default `false` and dropped
      by `mount/1`; the state has no such field.
    * `:class` - theme class atom or list of them, normalised into `:classes` by
      `from_component_opts/2` with default `[]` and dropped by `mount/1`.

  `update/2` accepts `:progress`, `:max_value`, `:label`, `:show_percentage`,
  `:show_value`, `:show_eta`, `:width`, `:height` and `:indeterminate`, and
  refreshes the animation clock on every call. Through the component tree,
  `update_props_from_mount/3` narrows that to `:progress`, `:max_value`, `:label`,
  `:show_percentage`, `:show_value`, `:indeterminate` and `:classes` — `:show_eta`,
  `:width` and `:height` are mount-only.

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

  @type t :: %__MODULE__{
          progress: number(),
          max_value: number(),
          label: String.t() | nil,
          show_percentage: boolean(),
          show_value: boolean(),
          show_eta: boolean(),
          width: pos_integer(),
          height: pos_integer(),
          indeterminate: boolean(),
          start_time: integer(),
          last_update_time: integer(),
          last_progress: number(),
          spin_position: non_neg_integer()
        }

  @doc """
  Builds the widget state from `props`.

  Every option listed in the module doc is read here with the default stated there.
  `:start_time` and `:last_update_time` are set to the current monotonic
  millisecond, which is what the ETA is measured against, and `:spin_position`
  starts at `0`.

      iex> state = Drafter.Widget.ProgressBar.mount(%{})
      iex> {state.progress, state.max_value, state.indeterminate, state.spin_position}
      {0.0, 100.0, false, 0}

      iex> state = Drafter.Widget.ProgressBar.mount(%{progress: 7, max_value: 20})
      iex> {state.progress, state.last_progress, state.show_percentage, state.show_eta}
      {7, 7, true, true}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the bar into `rect`.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. The bar always fills `rect.width`; the status text is drawn at the right
  and the track takes what is left. Returns `rect.height` strips, the first the bar
  and the rest blank.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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

  @doc """
  Ignores every event and returns `{:noreply, state}`. The bar is not focusable.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(_event, state) do
    {:noreply, state}
  end

  @doc """
  Replaces the state fields named in `props`, keeping the current value for any key
  that is absent.

  Also refreshes `:last_update_time` and `:last_progress`, and advances
  `:spin_position` by one modulo `40` while the bar is indeterminate.

      iex> state = Drafter.Widget.ProgressBar.mount(%{indeterminate: true})
      iex> Drafter.Widget.ProgressBar.update(%{}, state).spin_position
      1

      iex> state = Drafter.Widget.ProgressBar.mount(%{progress: 1})
      iex> updated = Drafter.Widget.ProgressBar.update(%{progress: 40}, state)
      iex> {updated.progress, updated.last_progress, updated.spin_position}
      {40, 40, 0}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  The number of rows the element asks for: `1`, or `8` when `opts[:orientation]` is
  `:vertical`.

  `:orientation` is not otherwise an option of this widget — `render/2` always
  draws horizontally — so a progress bar built from the component tree asks for one
  row.

      iex> Drafter.Widget.ProgressBar.preferred_height(nil, [])
      1

      iex> Drafter.Widget.ProgressBar.preferred_height(nil, orientation: :vertical)
      8
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts) do
    if Keyword.get(opts, :orientation, :horizontal) == :vertical, do: 8, else: 1
  end

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.ProgressBar.component_tag()
      :progress_bar
  """
  @spec component_tag() :: :progress_bar
  def component_tag, do: :progress_bar

  @doc """
  Builds the props map for a `{:progress_bar, opts}` element.

  The positional argument is ignored. `:width` and `:height` fall back to the width
  and height of `opts[:__rect__]`, itself defaulting to `%{width: 50, height: 1}`.
  `:class` is normalised into `:classes`. The result also carries `:pulse` and
  `:classes`, which `mount/1` drops.

      iex> props = Drafter.Widget.ProgressBar.from_component_opts(nil, progress: 3, max_value: 6)
      iex> {props.progress, props.max_value, props.width, props.height}
      {3, 6, 50, 1}

      iex> props = Drafter.Widget.ProgressBar.from_component_opts(nil, __rect__: %{width: 80, height: 2})
      iex> {props.width, props.height}
      {80, 2}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    rect = Keyword.get(opts, :__rect__, %{width: 50, height: 1})
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

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

  @doc """
  Narrows a re-render to the props that may change after mount.

  Returns `:progress`, `:max_value`, `:label`, `:show_percentage`, `:show_value`,
  `:indeterminate` and `:classes`. `:show_eta`, `:width` and `:height` are dropped,
  so they are mount-only through the component tree.

      iex> props = Drafter.Widget.ProgressBar.from_component_opts(nil, progress: 3)
      iex> Drafter.Widget.ProgressBar.update_props_from_mount(props, %{}, []) |> Map.keys() |> Enum.sort()
      [:classes, :indeterminate, :label, :max_value, :progress, :show_percentage, :show_value]
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
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

  @doc """
  Sets `:progress` from the newest entry of a `Drafter.RingBuffer`.

  Returns `state` unchanged when the buffer is empty. The rect is ignored.
  """
  @spec apply_data_buffer(t(), Drafter.RingBuffer.t(), Drafter.Widget.rect()) :: t()
  @impl Drafter.Widget
  def apply_data_buffer(state, buffer, _rect) do
    case Drafter.RingBuffer.last(buffer) do
      nil -> state
      value -> %{state | progress: value}
    end
  end
end
