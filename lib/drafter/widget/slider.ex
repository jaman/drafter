defmodule Drafter.Widget.Slider do
  @moduledoc """
  A draggable value slider: a track, a fill up to the current value, a thumb, and an
  optional label and value readout.

  The value lives on the widget. Keys, the mouse and the scroll wheel all move it,
  `:on_change` reports it, and `bind:` keeps it in step with a key of the app state.

  ## Component tag

  Tag `:slider`, built by `Drafter.App` as `{:slider, opts}`:

      slider(opts)
      slider(value, opts)

  The two-argument form puts `value` into `opts` under `:value`. `:value` and
  `:on_change` go through `Drafter.Binding`, so `bind: :some_key` reads the value from
  that app-state key and writes each new one back.

  ## Options

    * `:value` - `t:number/0` the slider starts at, clamped into the range and snapped
      to `:step`. Default `:min`.
    * `:min` - `t:number/0` low end of the range. Default `0.0`.
    * `:max` - `t:number/0` high end of the range. Default `1.0`.
    * `:step` - `t:number/0` the value moves in. Default `nil`, a hundredth of the
      range — whole numbers when `:min` and `:max` are both integers. A range whose
      bounds and step are all integers keeps integer values; any other range works in
      floats.
    * `:bind` - app-state key atom for two-way binding of the value. Default: none.
      Without it a later `:value` prop does not reach the mounted widget, which owns
      whatever the user set it to.
    * `:label` - `t:String.t/0` drawn ahead of the track, or `nil`. Default `nil`.
    * `:show_value` - `t:boolean/0`, draw the value after the track. Default `true`.
      The readout reserves the width of the widest value in the range, so the track
      does not move as the value changes.
    * `:format` - `(number() -> String.t())` for the readout. Default `nil`, which
      writes the number with `:precision` decimals.
    * `:precision` - decimals in the readout. Default: as many as `:step` needs.
    * `:orientation` - `:horizontal | :vertical`. Default `:horizontal`. A vertical
      slider runs bottom to top, with the label on its first row and the readout on
      its last.
    * `:disabled` - `t:boolean/0`. Default `false`. A disabled slider draws muted and
      bubbles every key and click.
    * `:track_color` / `:fill_color` / `:thumb_color` - `{r, g, b}` overrides for the
      three parts. Default `nil`, which takes them from the theme.
    * `:renderer` - `:text` (default) draws characters; `:braille` draws the shape
      through `Drafter.Widget.Slider.Pixel`; a graphics protocol atom (`:pixel`,
      `:kitty`, `:iterm2`, `:sixel`, `:auto`) transmits a picture, falling back to
      braille where the terminal has no protocol. Unset, the mode the app was run with
      applies; `DRAFTER_MODE` overrides both.
    * `:class` - theme class atom or list of them. Default `[]`.
    * `:style` - inline style map merged over the theme. Default `%{}`.

  `update/2` accepts every option above except `:class` and `:style`, which are
  mount-only. Through the component tree `update_props_from_mount/3` narrows that
  further, adding `:value` only when `:bind` is set and the bound value differs from
  the widget's own.

  ## Key bindings

    * `→`, `↑` - one step up; `←`, `↓` - one step down
    * `PageUp`, `PageDown` - ten steps
    * `Home`, `End` - the ends of the range

  A press or drag anywhere on the track moves the thumb there, and the scroll wheel
  moves one step.

  ## Widget value

  `Drafter.get_widget_value/1` returns the number, and `Drafter.set_widget_value/2`
  writes one, clamped and snapped like any other.

  ## Usage

      slider(value: 0.5, label: "Gain", on_change: :set_gain)
      slider(min: 0, max: 11, step: 1, bind: :volume)
      slider(value: 0.546, precision: 3, renderer: :auto)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :press, :mouse_up, :drag, :hover, :scroll]

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style
  alias Drafter.Style.Computed
  alias Drafter.Theme
  alias Drafter.Widget.Slider.{Pixel, Scale}

  @min_track 3
  @page_steps 10
  @default_track {70, 75, 85}
  @default_fill {80, 160, 255}
  @default_thumb {150, 200, 255}
  @default_text {180, 180, 180}

  defstruct value: 0.0,
            min: 0.0,
            max: 1.0,
            step: nil,
            label: nil,
            format: nil,
            precision: nil,
            orientation: :horizontal,
            show_value: true,
            on_change: nil,
            track_color: nil,
            fill_color: nil,
            thumb_color: nil,
            renderer: nil,
            classes: [],
            style: %{},
            app_module: nil,
            width: nil,
            height: nil,
            disabled: false,
            dragging: false,
            focused: false,
            hovered: false

  @type rgb :: {0..255, 0..255, 0..255}

  @type t :: %__MODULE__{
          value: number(),
          min: number(),
          max: number(),
          step: number() | nil,
          label: String.t() | nil,
          format: (number() -> String.t()) | nil,
          precision: non_neg_integer() | nil,
          orientation: :horizontal | :vertical,
          show_value: boolean(),
          on_change: (number() -> term()) | nil,
          track_color: rgb() | nil,
          fill_color: rgb() | nil,
          thumb_color: rgb() | nil,
          renderer: atom() | nil,
          classes: [atom()],
          style: map(),
          app_module: module() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          disabled: boolean(),
          dragging: boolean(),
          focused: boolean(),
          hovered: boolean()
        }

  @doc """
  Builds the widget state from `props`.

  The value is clamped into `:min`..`:max` and snapped to `:step`, so a slider can
  never mount off its own scale.

      iex> state = Drafter.Widget.Slider.mount(%{})
      iex> {state.value, state.min, state.max, state.orientation}
      {0.0, 0.0, 1.0, :horizontal}

      iex> Drafter.Widget.Slider.mount(%{value: 0.37, step: 0.25}).value
      0.25

      iex> Drafter.Widget.Slider.mount(%{value: 42, min: 0, max: 10, step: 1}).value
      10
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    min_value = Map.get(props, :min, 0.0)
    max_value = Map.get(props, :max, 1.0)
    step = Map.get(props, :step)

    %__MODULE__{
      value: Scale.snap(Map.get(props, :value, min_value), min_value, max_value, step),
      min: min_value,
      max: max_value,
      step: step,
      label: Map.get(props, :label),
      format: Map.get(props, :format),
      precision: Map.get(props, :precision),
      orientation: Map.get(props, :orientation, :horizontal),
      show_value: Map.get(props, :show_value, true),
      on_change: Map.get(props, :on_change),
      track_color: Map.get(props, :track_color),
      fill_color: Map.get(props, :fill_color),
      thumb_color: Map.get(props, :thumb_color),
      renderer: Map.get(props, :renderer),
      classes: Map.get(props, :classes, []),
      style: Map.get(props, :style, %{}),
      app_module: Map.get(props, :app_module),
      width: Map.get(props, :width),
      height: Map.get(props, :height),
      disabled: Map.get(props, :disabled, false),
      focused: Map.get(props, :focused, false),
      hovered: Map.get(props, :hovered, false)
    }
  end

  @doc """
  Records the rect the layout gave the widget, so a click can be turned into a value.

      iex> state = Drafter.Widget.Slider.mount(%{})
      iex> sized = Drafter.Widget.Slider.on_rect_change(%{x: 0, y: 0, width: 40, height: 1}, state)
      iex> {sized.width, sized.height}
      {40, 1}
  """
  @spec on_rect_change(Drafter.Widget.rect(), t()) :: t()
  def on_rect_change(rect, state), do: %{state | width: rect.width, height: rect.height}

  @doc """
  Draws the slider into `rect`, returning exactly `rect.height` strips.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. The renderer decides the track: a `:text` slider draws characters, a
  `:braille` one the braille shape, and a `:pixel` one leaves the track blank for the
  picture the widget server transmits. The label and the readout are characters in
  every mode. A rect with no width draws nothing.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(_state, %{width: width}) when width <= 0, do: []

  def render(_state, %{height: height}) when height <= 0, do: []

  def render(state, rect) do
    state = normalize(state)

    case Pixel.mode(state.renderer) do
      :pixel -> render_shape(state, rect, fn _size -> nil end)
      :braille -> render_shape(state, rect, &Pixel.braille_strips(spec(state), &1))
      :text -> render_text(state, rect)
    end
  end

  @doc """
  Whether this slider is drawing a transmitted image rather than characters.

  Only a `:pixel` mode on a terminal with a graphics protocol draws one; a `:text` or
  `:braille` slider costs nothing on the image path.

      iex> Drafter.Widget.Slider.image_active?(Drafter.Widget.Slider.mount(%{renderer: :text}))
      false
  """
  @spec image_active?(t()) :: boolean()
  @impl Drafter.Widget
  def image_active?(state), do: Pixel.mode(normalize(state).renderer) == :pixel

  @doc false
  def image(state, rect, id) do
    state = normalize(state)

    with :pixel <- Pixel.mode(state.renderer),
         {cols, rows, dx, dy} when cols > 0 and rows > 0 <- shape_box(state, rect),
         {paint, clear} <- Pixel.image(spec(state), {cols, rows}, state.renderer, id) do
      {paint, clear, %{dx: dx, dy: dy, cols: cols, rows: rows}}
    else
      _ -> nil
    end
  end

  @doc """
  Moves the value by one step for `→` and `↑`, down one for `←` and `↓`, ten for the
  page keys, and to the ends of the range for `Home` and `End`.

  A key that does not move the value still returns `{:ok, state}`; every other key,
  and every key at all while `:disabled`, bubbles.

      iex> state = Drafter.Widget.Slider.mount(%{value: 0.5, step: 0.1})
      iex> {:ok, moved} = Drafter.Widget.Slider.handle_key(:right, state)
      iex> moved.value
      0.6

      iex> state = Drafter.Widget.Slider.mount(%{value: 0.5})
      iex> {:ok, moved} = Drafter.Widget.Slider.handle_key(:home, state)
      iex> moved.value
      0.0
  """
  @spec handle_key(Drafter.Widget.key(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_key(_key, %{disabled: true} = state), do: {:bubble, state}
  def handle_key(key, state) when key in [:right, :up], do: move(state, 1)
  def handle_key(key, state) when key in [:left, :down], do: move(state, -1)
  def handle_key(:page_up, state), do: move(state, @page_steps)
  def handle_key(:page_down, state), do: move(state, -@page_steps)
  def handle_key(:home, state), do: set_value(state, state.min)
  def handle_key(:end, state), do: set_value(state, state.max)
  def handle_key(_key, state), do: {:bubble, state}

  @doc """
  Moves the thumb to the pointer and starts a drag gesture, so later motion keeps
  tracking even once the pointer leaves the widget.

  `x` and `y` are widget-relative cells.
  """
  @spec handle_press(integer(), integer(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_press(_x, _y, %{disabled: true} = state), do: {:bubble, state}

  def handle_press(x, y, state) do
    {:ok, moved} = set_value(state, pointer_value(state, x, y))
    {:ok, %{moved | dragging: true}}
  end

  @doc "Moves the thumb to the pointer while a button is held."
  @spec handle_drag(integer(), integer(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_drag(_x, _y, %{disabled: true} = state), do: {:bubble, state}
  def handle_drag(x, y, state), do: set_value(state, pointer_value(state, x, y))

  @doc "Moves the thumb to the pointer and ends the drag gesture."
  @spec handle_mouse_up(integer(), integer(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_mouse_up(_x, _y, %{disabled: true} = state), do: {:bubble, state}

  def handle_mouse_up(x, y, state) do
    {:ok, moved} = set_value(state, pointer_value(state, x, y))
    {:ok, %{moved | dragging: false}}
  end

  @doc "Moves the value one step per wheel notch."
  @spec handle_scroll(Drafter.Widget.scroll_direction(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_scroll(_direction, %{disabled: true} = state), do: {:bubble, state}
  def handle_scroll(:up, state), do: move(state, 1)
  def handle_scroll(:down, state), do: move(state, -1)

  @doc "Tracks `:hover` and `:unhover`; every other event bubbles."
  @spec handle_custom_event(Drafter.Event.t(), t()) :: {:ok, t()} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_custom_event(:hover, state), do: {:ok, %{state | hovered: true}}
  def handle_custom_event(:unhover, state), do: {:ok, %{state | hovered: false}}
  def handle_custom_event(_event, state), do: {:bubble, state}

  @doc """
  Folds fresh props into `state`, keeping the current value for any key that is
  absent.

  The value is re-snapped against whichever range the props leave behind, so moving
  `:min`, `:max` or `:step` never leaves the thumb off its scale.

      iex> state = Drafter.Widget.Slider.mount(%{value: 90, min: 0, max: 100})
      iex> Drafter.Widget.Slider.update(%{max: 50}, state).value
      50
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    min_value = Map.get(props, :min, state.min)
    max_value = Map.get(props, :max, state.max)
    step = Map.get(props, :step, state.step)

    %{
      state
      | value: Scale.snap(Map.get(props, :value, state.value), min_value, max_value, step),
        min: min_value,
        max: max_value,
        step: step,
        label: Map.get(props, :label, state.label),
        format: Map.get(props, :format, state.format),
        precision: Map.get(props, :precision, state.precision),
        orientation: Map.get(props, :orientation, state.orientation),
        show_value: Map.get(props, :show_value, state.show_value),
        on_change: Map.get(props, :on_change, state.on_change),
        track_color: Map.get(props, :track_color, state.track_color),
        fill_color: Map.get(props, :fill_color, state.fill_color),
        thumb_color: Map.get(props, :thumb_color, state.thumb_color),
        renderer: Map.get(props, :renderer, state.renderer),
        disabled: Map.get(props, :disabled, state.disabled),
        width: Map.get(props, :width, state.width),
        height: Map.get(props, :height, state.height)
    }
  end

  @doc """
  The number of rows the element asks for: `:height`, defaulting to `8` for a vertical
  slider and `1` for a horizontal one.

      iex> Drafter.Widget.Slider.preferred_height(nil, [])
      1

      iex> Drafter.Widget.Slider.preferred_height(nil, orientation: :vertical)
      8
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts) do
    if Keyword.get(opts, :orientation, :horizontal) == :vertical do
      Keyword.get(opts, :height, 8)
    else
      Keyword.get(opts, :height, 1)
    end
  end

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Slider.component_tag()
      :slider
  """
  @spec component_tag() :: :slider
  def component_tag, do: :slider

  @doc """
  Builds the props map for a `{:slider, opts}` element.

  The positional argument is ignored. `:value` comes from
  `Drafter.Binding.get_bound_value/3`, so `bind: :key` reads it from
  `opts[:__app_state__]`, and `:on_change` is the binding's writer. `:class` is
  normalised into `:classes` and `:__app_module__` into `:app_module`.

      iex> props = Drafter.Widget.Slider.from_component_opts(nil, min: 0, max: 10, step: 1)
      iex> {props.value, props.min, props.max, props.step}
      {0, 0, 10, 1}

      iex> opts = [bind: :gain, __app_state__: %{gain: 0.75}]
      iex> Drafter.Widget.Slider.from_component_opts(nil, opts).value
      0.75
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 20, height: 1})
    min_value = Keyword.get(opts, :min, 0.0)

    %{
      value: Drafter.Binding.get_bound_value(opts, app_state, min_value),
      min: min_value,
      max: Keyword.get(opts, :max, 1.0),
      step: Keyword.get(opts, :step),
      label: Keyword.get(opts, :label),
      format: Keyword.get(opts, :format),
      precision: Keyword.get(opts, :precision),
      orientation: Keyword.get(opts, :orientation, :horizontal),
      show_value: Keyword.get(opts, :show_value, true),
      on_change: Drafter.Binding.create_bound_callback(opts, :value),
      track_color: Keyword.get(opts, :track_color),
      fill_color: Keyword.get(opts, :fill_color),
      thumb_color: Keyword.get(opts, :thumb_color),
      renderer: Keyword.get(opts, :renderer),
      disabled: Keyword.get(opts, :disabled, false),
      classes: Drafter.Util.normalize_classes(Keyword.get(opts, :class, [])),
      style: Keyword.get(opts, :style, %{}),
      app_module: Keyword.get(opts, :__app_module__),
      width: Keyword.get(opts, :width, rect.width),
      height: Keyword.get(opts, :height, rect.height)
    }
  end

  @doc """
  Narrows a re-render to the props that may change after mount.

  `:value` is added only when `opts` carries `:bind` and the bound value differs from
  the widget's own, so an unbound slider keeps whatever the user dragged it to.
  `:class` and `:style` are dropped, making them mount-only.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t() | map(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, opts) do
    base = Map.drop(mount_props, [:value, :classes, :style, :app_module])

    if Drafter.Binding.has_binding?(opts) and
         mount_props.value != Map.get(existing_state, :value) do
      Map.put(base, :value, mount_props.value)
    else
      base
    end
  end

  defp normalize(state) when is_struct(state, __MODULE__), do: state
  defp normalize(props), do: mount(props)

  defp move(state, steps) do
    set_value(state, Scale.nudge(state.value, state.min, state.max, state.step, steps))
  end

  defp set_value(state, value) do
    snapped = Scale.snap(value, state.min, state.max, state.step)

    if snapped == state.value do
      {:ok, state}
    else
      new_state = %{state | value: snapped}
      trigger_change(new_state, snapped)
      {:ok, new_state}
    end
  end

  defp trigger_change(%{on_change: on_change}, value) when is_function(on_change, 1) do
    on_change.(value)
  rescue
    _ -> :ok
  end

  defp trigger_change(_state, _value), do: :ok

  defp pointer_value(%{orientation: :vertical} = state, _x, y) do
    rows = vertical_rows(state, height_of(state))
    span = max(1, rows - 1)
    offset = y - vertical_label_rows(state)
    Scale.value_at(1.0 - offset / span, state.min, state.max, state.step)
  end

  defp pointer_value(state, x, _y) do
    parts = layout(state, %{width: width_of(state), height: height_of(state)})
    span = max(1, parts.track - 1)
    Scale.value_at((x - parts.track_x) / span, state.min, state.max, state.step)
  end

  defp width_of(%{width: width}) when is_integer(width) and width > 0, do: width
  defp width_of(_state), do: 1

  defp height_of(%{height: height}) when is_integer(height) and height > 0, do: height
  defp height_of(_state), do: 1

  defp spec(state) do
    colors = colors(state)

    %{
      fraction: Scale.fraction(state.value, state.min, state.max),
      orientation: state.orientation,
      track: rgba(colors.track),
      fill: rgba(colors.fill),
      thumb: rgba(colors.thumb)
    }
  end

  defp rgba({r, g, b}), do: {r, g, b, 255}
  defp rgba({r, g, b, a}), do: {r, g, b, a}
  defp rgba(_color), do: {180, 180, 180, 255}

  defp render_text(state, rect) do
    case state.orientation do
      :vertical -> render_vertical_text(state, rect)
      _horizontal -> render_horizontal_text(state, rect)
    end
  end

  defp render_horizontal_text(state, rect) do
    colors = colors(state)
    parts = layout(state, rect)

    parts.label
    |> text_segments(colors.text, colors.bg)
    |> Kernel.++(horizontal_track_segments(state, parts.track, colors))
    |> Kernel.++(text_segments(parts.value, colors.value, colors.bg))
    |> row(rect.width, colors.bg)
    |> center_row(rect, colors.bg)
  end

  defp render_vertical_text(state, rect) do
    colors = colors(state)
    rows = vertical_rows(state, rect.height)
    fraction = Scale.fraction(state.value, state.min, state.max)
    thumb_row = rows - 1 - round(fraction * (rows - 1))

    track =
      for row <- 0..(rows - 1)//1 do
        {glyph, color} = vertical_cell(state, row, thumb_row, colors)
        row(centered_segments(glyph, rect.width, color, colors.bg), rect.width, colors.bg)
      end

    vertical_label_strips(state, rect.width, colors) ++
      track ++ vertical_value_strips(state, rect.width, colors)
  end

  defp vertical_cell(state, row, thumb_row, colors) when row == thumb_row,
    do: {thumb_glyph(state), colors.thumb}

  defp vertical_cell(_state, row, thumb_row, colors) when row > thumb_row,
    do: {CharacterSet.slider(:fill_v), colors.fill}

  defp vertical_cell(_state, _row, _thumb_row, colors),
    do: {CharacterSet.slider(:track_v), colors.track}

  defp render_shape(state, rect, draw) do
    case shape_box(state, rect) do
      {cols, rows, _dx, _dy} when cols <= 0 or rows <= 0 ->
        render_text(state, rect)

      {cols, rows, dx, dy} ->
        case draw.({cols, rows}) do
          nil -> blank_shape(state, rect, {cols, rows, dx, dy})
          strips -> compose_shape(state, rect, strips, {cols, rows, dx, dy})
        end
    end
  end

  defp blank_shape(state, rect, {cols, rows, dx, dy}) do
    colors = colors(state)
    blank = Strip.new([Segment.new(String.duplicate(" ", cols), %{bg: colors.bg})])
    compose_shape(state, rect, List.duplicate(blank, rows), {cols, rows, dx, dy})
  end

  defp compose_shape(state, rect, strips, {_cols, _rows, dx, dy}) do
    case state.orientation do
      :vertical -> compose_vertical_shape(state, rect, strips)
      _horizontal -> compose_horizontal_shape(state, rect, strips, dx, dy)
    end
  end

  defp compose_horizontal_shape(state, rect, strips, dx, _dy) do
    colors = colors(state)
    parts = layout(state, rect)
    middle = div(length(strips) - 1, 2)

    strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, index} ->
      on_middle = index == middle
      leading = shape_side(on_middle, parts.label, dx, colors.text, colors.bg)

      trailing =
        shape_side(on_middle, parts.value, side_width(parts, rect), colors.value, colors.bg)

      row(leading ++ strip.segments ++ trailing, rect.width, colors.bg)
    end)
  end

  defp compose_vertical_shape(state, rect, strips) do
    colors = colors(state)

    vertical_label_strips(state, rect.width, colors) ++
      Enum.map(strips, &row(&1.segments, rect.width, colors.bg)) ++
      vertical_value_strips(state, rect.width, colors)
  end

  defp side_width(parts, rect), do: max(0, rect.width - parts.track_x - parts.track)

  defp shape_side(true, text, _width, color, bg), do: text_segments(text, color, bg)
  defp shape_side(false, _text, width, _color, bg), do: blank_segments(width, bg)

  defp shape_box(state, rect) do
    case state.orientation do
      :vertical ->
        {rect.width, vertical_rows(state, rect.height), 0, vertical_label_rows(state)}

      _horizontal ->
        parts = layout(state, rect)
        {parts.track, rect.height, parts.track_x, 0}
    end
  end

  defp vertical_rows(state, height) do
    max(1, height - vertical_label_rows(state) - vertical_value_rows(state))
  end

  defp vertical_label_rows(%{label: label}) when is_binary(label), do: 1
  defp vertical_label_rows(_state), do: 0

  defp vertical_value_rows(%{show_value: true}), do: 1
  defp vertical_value_rows(_state), do: 0

  defp vertical_label_strips(%{label: label}, width, colors) when is_binary(label) do
    [row(centered_segments(label, width, colors.text, colors.bg), width, colors.bg)]
  end

  defp vertical_label_strips(_state, _width, _colors), do: []

  defp vertical_value_strips(%{show_value: true} = state, width, colors) do
    text = format_value(state, state.value)
    [row(centered_segments(text, width, colors.value, colors.bg), width, colors.bg)]
  end

  defp vertical_value_strips(_state, _width, _colors), do: []

  defp horizontal_track_segments(state, width, colors) when width > 0 do
    fraction = Scale.fraction(state.value, state.min, state.max)
    thumb_at = round(fraction * (width - 1))

    [
      Segment.new(String.duplicate(CharacterSet.slider(:fill), thumb_at), %{
        fg: colors.fill,
        bg: colors.bg
      }),
      Segment.new(thumb_glyph(state), %{fg: colors.thumb, bg: colors.bg}),
      Segment.new(String.duplicate(CharacterSet.slider(:track), width - thumb_at - 1), %{
        fg: colors.track,
        bg: colors.bg
      })
    ]
    |> Enum.reject(&(&1.text == ""))
  end

  defp horizontal_track_segments(_state, _width, _colors), do: []

  defp thumb_glyph(%{focused: true}), do: CharacterSet.slider(:thumb_focused)
  defp thumb_glyph(_state), do: CharacterSet.slider(:thumb)

  defp layout(state, rect) do
    label = label_text(state)
    value = value_text(state)
    label_width = text_width(label)
    value_width = text_width(value)

    cond do
      rect.width - label_width - value_width >= @min_track ->
        %{
          label: label,
          value: value,
          track: rect.width - label_width - value_width,
          track_x: label_width
        }

      rect.width - value_width >= @min_track ->
        %{label: nil, value: value, track: rect.width - value_width, track_x: 0}

      rect.width >= @min_track ->
        %{label: nil, value: nil, track: rect.width, track_x: 0}

      true ->
        %{label: label, value: nil, track: 0, track_x: 0}
    end
  end

  defp label_text(%{label: label}) when is_binary(label) and label != "", do: label <> " "
  defp label_text(_state), do: nil

  defp value_text(%{show_value: true} = state) do
    field =
      max(
        String.length(format_value(state, state.min)),
        String.length(format_value(state, state.max))
      )

    " " <> String.pad_leading(format_value(state, state.value), field)
  end

  defp value_text(_state), do: nil

  defp format_value(%{format: format}, value) when is_function(format, 1) do
    to_string(format.(value))
  end

  defp format_value(state, value) do
    decimals =
      state.precision || Scale.decimals(Scale.step_size(state.min, state.max, state.step))

    format_number(value, decimals)
  end

  defp format_number(value, 0) when is_integer(value), do: Integer.to_string(value)

  defp format_number(value, decimals),
    do: :erlang.float_to_binary(value * 1.0, decimals: decimals)

  defp text_width(nil), do: 0
  defp text_width(text), do: String.length(text)

  defp text_segments(nil, _color, _bg), do: []
  defp text_segments(text, color, bg), do: [Segment.new(text, %{fg: color, bg: bg})]

  defp blank_segments(width, _bg) when width <= 0, do: []
  defp blank_segments(width, bg), do: [Segment.new(String.duplicate(" ", width), %{bg: bg})]

  defp centered_segments(text, width, color, bg) do
    padding = max(0, width - String.length(text))
    left = div(padding, 2)

    blank_segments(left, bg) ++
      text_segments(text, color, bg) ++ blank_segments(padding - left, bg)
  end

  defp row(segments, width, bg) do
    drawn = Enum.reduce(segments, 0, &(&1.width + &2))

    segments
    |> Kernel.++(blank_segments(width - drawn, bg))
    |> Strip.new()
    |> Strip.fit_to_width(width)
  end

  defp center_row(strip, rect, bg) do
    blank = Strip.new([Segment.new(String.duplicate(" ", rect.width), %{bg: bg})])
    above = div(rect.height - 1, 2)

    List.duplicate(blank, above) ++
      [strip] ++ List.duplicate(blank, rect.height - above - 1)
  end

  defp colors(state) do
    opts = [classes: state.classes || [], style: state.style || %{}, app_module: state.app_module]
    base = Computed.for_widget(:slider, state, opts)

    %{
      bg: base[:background],
      text: shade(state, base[:color] || @default_text),
      value: shade(state, part_color(state, :value, opts) || @default_text),
      track: shade(state, state.track_color || part_color(state, :track, opts) || @default_track),
      fill: shade(state, state.fill_color || part_color(state, :fill, opts) || @default_fill),
      thumb: thumb_shade(state, opts)
    }
  end

  defp part_color(state, part, opts), do: Computed.for_part(:slider, state, part, opts)[:color]

  defp thumb_shade(state, opts) do
    base = state.thumb_color || part_color(state, :thumb, opts) || @default_thumb

    cond do
      state.disabled -> Theme.mute_color(base)
      state.dragging or state.hovered -> Style.lighten(base, 25)
      state.focused -> Style.lighten(base, 12)
      true -> base
    end
  end

  defp shade(%{disabled: true}, color), do: Theme.mute_color(color)
  defp shade(_state, color), do: color
end
