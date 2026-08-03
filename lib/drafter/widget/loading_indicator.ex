defmodule Drafter.Widget.LoadingIndicator do
  @moduledoc """
  Renders an animated spinner with an optional label.

  The spinner frame is read from the monotonic clock at render time, one frame per
  100 ms. An optional colour gradient cycles through the provided colours on its own
  clock, independent of the spinner frame. While `:running` is false both the frame
  and the gradient step are pinned to `0`.

  Send `:start` or `:stop` events to control animation at runtime.

  ## Component tag

  Tag `:loading_indicator`, built by `Drafter.App` as `{:loading_indicator, opts}`:

      loading_indicator(opts)

  There is no positional argument; every prop comes from `opts`. The renderer stamps
  the current monotonic time onto the props on each pass, which forces the widget to
  re-render; the frame itself is read from the clock, not from the stamp.

  ## Options

    * `:text` - `t:String.t/0` label shown after the spinner character. Default
      `"Loading..."`. `nil` renders the spinner alone
    * `:spinner_type` - `:default` (default), `:dots`, `:line`, `:points`, `:arrow`
      or `:bounce`. `:arrow` and `:bounce` use built-in four-frame sets; the rest
      come from the character set, with `:default` mapping to its `:dots` frames,
      `:dots` to its `:braille` frames, and anything unrecognised to `:dots`
    * `:running` - `t:boolean/0`, whether the spinner animates. Default `true`
    * `:gradient_colors` - list of `{r, g, b}` tuples to cycle the spinner colour
      through. Default `nil`, leaving the spinner the computed theme colour. A
      one-colour list is used as a constant colour
    * `:gradient_speed` - milliseconds per gradient step. Default `50`
    * `:style` - `t:map/0` of style properties. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:app_module` - module supplying a per-app theme. Default `nil`

  `update/2` re-reads every option. Through the component tree a re-render passes
  only a fresh `:_render_timestamp`, so every other option is effectively mount-only
  there.

  ## Widget value

  `Drafter.get_widget_value/1` returns the indicator's `:text`, because the value
  extractor reads the `:text` field.

  ## Usage

      loading_indicator(text: "Fetching data...")
      loading_indicator(spinner_type: :dots, gradient_colors: [{255, 0, 100}, {0, 100, 255}])
  """

  use Drafter.Widget

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @spinner_speed 100
  @fallback_spinner_sets %{
    arrow: ["←", "↑", "→", "↓"],
    bounce: ["⠁", "⠂", "⠄", "⠂"]
  }

  defstruct [
    :text,
    :spinner_type,
    :style,
    :classes,
    :app_module,
    :running,
    :_render_timestamp,
    :gradient_colors,
    :gradient_speed
  ]

  @type spinner_type :: :default | :dots | :line | :points | :arrow | :bounce

  @type t :: %__MODULE__{
          text: String.t() | nil,
          spinner_type: spinner_type(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          running: boolean(),
          _render_timestamp: integer(),
          gradient_colors: [{0..255, 0..255, 0..255}] | nil,
          gradient_speed: pos_integer()
        }

  @doc """
  Builds the indicator state from `props`.

  `:_render_timestamp` defaults to the current monotonic millisecond.

      iex> li = Drafter.Widget.LoadingIndicator.mount(%{text: "Fetching..."})
      iex> {li.text, li.spinner_type, li.running, li.gradient_speed, li.gradient_colors}
      {"Fetching...", :default, true, 50, nil}

      iex> li = Drafter.Widget.LoadingIndicator.mount(%{})
      iex> {li.text, li.style, li.classes}
      {"Loading...", %{}, []}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    spinner_type = Map.get(props, :spinner_type, :default)
    text = Map.get(props, :text, "Loading...")
    running = Map.get(props, :running, true)
    timestamp = Map.get(props, :_render_timestamp, System.monotonic_time(:millisecond))

    gradient_colors = Map.get(props, :gradient_colors)
    gradient_speed = Map.get(props, :gradient_speed, 50)

    %__MODULE__{
      text: text,
      spinner_type: spinner_type,
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      running: running,
      _render_timestamp: timestamp,
      gradient_colors: gradient_colors,
      gradient_speed: gradient_speed
    }
  end

  @doc """
  Draws the spinner and label as a single strip.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. The strip is
  `" <frame> <text> "` with `:text` and `" <frame> "` without it. `rect` is not
  consulted, so the strip is neither cropped nor padded to it.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, _rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    computed_opts = [classes: state.classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:loading_indicator, state, computed_opts)

    spinner_char = current_spinner_char(state)
    fg = resolve_fg_color(state, computed)
    bg = computed[:background] || {30, 30, 30}

    label_text = if state.text, do: " #{spinner_char} #{state.text} ", else: " #{spinner_char} "
    [Strip.new([Segment.new(label_text, %{fg: fg, bg: bg})])]
  end

  defp current_spinner_char(state) do
    spinner_chars =
      case Map.fetch(@fallback_spinner_sets, state.spinner_type) do
        {:ok, frames} -> frames
        :error -> CharacterSet.spinner(spinner_type_to_skin_key(state.spinner_type))
      end

    frame =
      if state.running, do: System.monotonic_time(:millisecond) |> div(@spinner_speed), else: 0

    Enum.at(spinner_chars, rem(frame, length(spinner_chars)))
  end

  defp resolve_fg_color(%{gradient_colors: nil}, computed),
    do: computed[:color] || {200, 200, 200}

  defp resolve_fg_color(state, _computed) do
    gradient_frame =
      if state.running,
        do: System.monotonic_time(:millisecond) |> div(state.gradient_speed),
        else: 0

    interpolate_gradient(state.gradient_colors, gradient_frame)
  end

  @doc """
  Starts and stops the animation.

  `:start` sets `:running` and `:stop` clears it, both returning `{:ok, state}`.
  Everything else returns `{:noreply, state}`.

      iex> li = Drafter.Widget.LoadingIndicator.mount(%{})
      iex> {:ok, stopped} = Drafter.Widget.LoadingIndicator.handle_event(:stop, li)
      iex> stopped.running
      false

      iex> li = Drafter.Widget.LoadingIndicator.mount(%{})
      iex> Drafter.Widget.LoadingIndicator.handle_event({:key, :enter}, li) |> elem(0)
      :noreply
  """
  @spec handle_event(Drafter.Event.t() | :start | :stop, t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case event do
      :start ->
        {:ok, %{state | running: true}}

      :stop ->
        {:ok, %{state | running: false}}

      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Folds fresh props into `state`, re-reading every option.

  `:_render_timestamp` is taken from `props` or re-stamped from the monotonic clock.

      iex> li = Drafter.Widget.LoadingIndicator.mount(%{})
      iex> Drafter.Widget.LoadingIndicator.update(%{text: "Almost there"}, li).text
      "Almost there"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    timestamp = Map.get(props, :_render_timestamp, System.monotonic_time(:millisecond))

    %{
      state
      | text: Map.get(props, :text, state.text),
        spinner_type: Map.get(props, :spinner_type, state.spinner_type),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        running: Map.get(props, :running, state.running),
        _render_timestamp: timestamp,
        gradient_colors: Map.get(props, :gradient_colors, state.gradient_colors),
        gradient_speed: Map.get(props, :gradient_speed, state.gradient_speed)
    }
  end

  @doc """
  The render cache key, the current monotonic millisecond.

  It never repeats, so the widget is redrawn on every frame and the animation keeps
  moving.
  """
  @spec get_render_key(t()) :: integer()
  def get_render_key(_state) do
    System.monotonic_time(:millisecond)
  end

  @doc "Always `1`: the indicator occupies a single row."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.LoadingIndicator.component_tag()
      :loading_indicator
  """
  @spec component_tag() :: :loading_indicator
  def component_tag, do: :loading_indicator

  @doc """
  Turns the `{:loading_indicator, opts}` element into a props map for `mount/1`.

  The positional argument is ignored. `:class` is normalised into `:classes` and a
  fresh `:_render_timestamp` is stamped from the monotonic clock.

      iex> props = Drafter.Widget.LoadingIndicator.from_component_opts(nil, text: "Wait")
      iex> {props.text, props.spinner_type, props.running, props.gradient_speed, props.classes}
      {"Wait", :default, true, 50, []}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      text: Keyword.get(opts, :text, "Loading..."),
      spinner_type: Keyword.get(opts, :spinner_type, :default),
      running: Keyword.get(opts, :running, true),
      gradient_colors: Keyword.get(opts, :gradient_colors),
      gradient_speed: Keyword.get(opts, :gradient_speed, 50),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      _render_timestamp: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Narrows the props a re-render feeds to `update/2` to a fresh
  `:_render_timestamp`, so no other option changes after mount through the component
  tree.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(_mount_props, _existing_state, _opts) do
    %{_render_timestamp: System.monotonic_time(:millisecond)}
  end

  defp spinner_type_to_skin_key(:default), do: :dots
  defp spinner_type_to_skin_key(:dots), do: :braille
  defp spinner_type_to_skin_key(:line), do: :line
  defp spinner_type_to_skin_key(:points), do: :points
  defp spinner_type_to_skin_key(_), do: :dots

  defp interpolate_gradient(colors, frame) do
    num_colors = length(colors)

    if num_colors < 2 do
      List.first(colors) || {200, 200, 200}
    else
      pos = rem(frame, num_colors * 100) / 100
      idx_float = pos * (num_colors - 1)
      idx = trunc(idx_float)
      next_idx = rem(idx + 1, num_colors)
      t = idx_float - idx

      {r1, g1, b1} = Enum.at(colors, idx)
      {r2, g2, b2} = Enum.at(colors, next_idx)

      r = round(r1 + (r2 - r1) * t)
      g = round(g1 + (g2 - g1) * t)
      b = round(b1 + (b2 - b1) * t)

      {r, g, b}
    end
  end
end
