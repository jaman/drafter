defmodule Drafter.Widget.Button do
  @moduledoc """
  A clickable button widget that triggers a callback when pressed or activated via keyboard.

  The button renders with a 3-line layout: a top border highlight, a centred label, and a
  bottom shadow. Visual state changes (hover, active, focused, disabled) are reflected
  through colour adjustments.

  ## Component tag

  Tag `:button`, built by `Drafter.App` as `{:button, text, opts}`:

      button(text, opts)

  The positional argument becomes `:text`. `from_component_opts/2` wraps
  `:on_click` with `Drafter.Widget.Callback`, so it may be given as an atom event
  name, and drops it entirely when `disabled: true`.

  ## Options

    * `:text` - `t:String.t/0` button label. Default `""`. Supplied positionally
      through the `button/2` element
    * `:on_click` - atom event name or zero-arity function called when the button
      is activated. Default `nil`
    * `:variant` - visual style atom: `:default` (default), `:primary`, `:success`,
      `:warning`, `:error`. Any value other than `:default` is also prepended to the
      theme classes. `:type` is accepted as an alias by the element, and
      `:button_type` is accepted directly by `mount/1`
    * `:disabled` - `t:boolean/0`. Default `false`. A disabled button consumes
      interaction without firing `:on_click` and gains the `:disabled` theme class;
      the element also drops `:on_click` entirely
    * `:compact` - `t:boolean/0`. Default `false`. Renders the label row only,
      without the highlight and shadow rows
    * `:style` - `t:map/0` of style overrides applied on top of theme defaults.
      Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:focused` - `t:boolean/0` initial focus flag. Default `false`
    * `:app_module` - module supplying a per-app theme, passed by the renderer as
      `:__app_module__`. Default `nil`

  `:active` and `:hovered` are state the widget owns; `mount/1` always starts them
  at `false` and ignores props of those names. Every other option, `:focused`
  included, is live-updatable through `update/2`.

  ## Widget value

  `Drafter.get_widget_value/1` returns the button's `:text` as a `t:String.t/0`,
  because the value extractor reads the `:text` field. Activation itself is
  reported through `:on_click`.

  ## Key bindings and events

  `:enter` and `:" "` activate the button; every other key bubbles. A mouse release
  anywhere in the rect activates it. Activation sets `:active`, fires `:on_click`,
  and schedules a `:deactivate` message to the owning process 200 ms later, which
  clears `:active` again. `handle_custom_event/2` also accepts `:activate`,
  `{:mouse, %{type: :press}}`, `:hover` and `:unhover`.

  ## Usage

      button("Submit", on_click: fn -> :submit end, variant: :primary)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:mouse_up, :keyboard]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  @active_effect_duration 200

  @type variant :: :default | :primary | :success | :warning | :error

  @type t :: %__MODULE__{
          text: String.t(),
          style: map(),
          active: boolean(),
          hovered: boolean(),
          on_click: (-> any()) | nil,
          button_type: variant(),
          classes: [atom()],
          app_module: module() | nil,
          disabled: boolean(),
          focused: boolean(),
          compact: boolean()
        }

  @type action ::
          {:pop, term()}
          | {:push, module(), map()}
          | {:replace, module(), map()}
          | {:app_callback, atom(), term()}

  defstruct text: "",
            style: %{},
            active: false,
            hovered: false,
            on_click: nil,
            button_type: :default,
            classes: [],
            app_module: nil,
            disabled: false,
            focused: false,
            compact: false

  @doc """
  Builds the button state from `props`.

  A `:variant` other than `:default` is prepended to `:classes`, and `:disabled`
  prepends `:disabled` on top of that. `:active` and `:hovered` always start at
  `false`.

      iex> b = Drafter.Widget.Button.mount(%{text: "Save", variant: :primary})
      iex> {b.text, b.button_type, b.classes, b.disabled, b.compact}
      {"Save", :primary, [:primary], false, false}

      iex> b = Drafter.Widget.Button.mount(%{})
      iex> {b.text, b.button_type, b.classes, b.active, b.hovered, b.focused}
      {"", :default, [], false, false, false}

      iex> Drafter.Widget.Button.mount(%{variant: :error, disabled: true}).classes
      [:disabled, :error]
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    button_type = Map.get(props, :variant) || Map.get(props, :button_type, :default)
    classes = Map.get(props, :classes, [])
    classes = if button_type != :default, do: [button_type | classes], else: classes
    disabled = Map.get(props, :disabled, false)
    classes = if disabled, do: [:disabled | classes], else: classes

    %__MODULE__{
      text: Map.get(props, :text, ""),
      style: Map.get(props, :style, %{}),
      focused: Map.get(props, :focused, false),
      active: false,
      hovered: false,
      on_click: Map.get(props, :on_click),
      button_type: button_type,
      classes: classes,
      app_module: Map.get(props, :app_module),
      disabled: disabled,
      compact: Map.get(props, :compact, false)
    }
  end

  @doc """
  Draws the button into `rect`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. Produces one
  strip when `:compact` is set and three otherwise, then centres those rows
  vertically in `rect.height`, truncating from the bottom when the rect is shorter.
  A label wider than `rect.width` is cut, not wrapped.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    render_button(state, rect)
  end

  defp render_button(state, rect) do
    computed_opts = [classes: state.classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:button, state, computed_opts)

    base_bg = computed[:background] || {60, 60, 60}
    fg_color = computed[:color] || {255, 255, 255}
    bg_color = if state.hovered, do: Style.darken(base_bg, 15), else: base_bg

    {top_border_color, bottom_border_color} =
      if state.active do
        {Style.darken(base_bg, 40), Style.lighten(base_bg, 40)}
      else
        {Style.lighten(base_bg, 40), Style.darken(base_bg, 40)}
      end

    button_style =
      if state.focused do
        %{fg: bg_color, bg: fg_color, bold: true}
      else
        %{fg: fg_color, bg: bg_color, bold: true}
      end

    top_border_style = %{fg: top_border_color, bg: bg_color}
    bottom_border_style = %{fg: bottom_border_color, bg: bg_color}
    button_bg_style = %{fg: fg_color, bg: bg_color}

    content_width = rect.width

    top_border_char = "▔"
    bottom_border_char = "▁"

    top_strip =
      Strip.new([
        Segment.new(String.duplicate(top_border_char, content_width), top_border_style)
      ])

    label_with_padding = " #{state.text} "
    label_len = String.length(label_with_padding)

    mid_strip =
      if label_len >= content_width do
        Strip.new([
          Segment.new(String.slice(label_with_padding, 0, content_width), button_style)
        ])
      else
        pad = content_width - label_len
        left_pad = div(pad, 2)
        right_pad = pad - left_pad

        Strip.new([
          Segment.new(String.duplicate(" ", left_pad), button_bg_style),
          Segment.new(label_with_padding, button_style),
          Segment.new(String.duplicate(" ", right_pad), button_bg_style)
        ])
      end

    bot_strip =
      Strip.new([
        Segment.new(String.duplicate(bottom_border_char, content_width), bottom_border_style)
      ])

    content_strips =
      if state.compact do
        [mid_strip]
      else
        [top_strip, mid_strip, bot_strip]
      end

    pad_to_height(content_strips, rect.height, rect.width, button_bg_style)
  end

  defp pad_to_height(strips, target_height, width, bg_style) do
    current = length(strips)

    if current >= target_height do
      Enum.take(strips, target_height)
    else
      top_pad = div(target_height - current, 2)
      bottom_pad = target_height - current - top_pad
      blank = Strip.new([Segment.new(String.duplicate(" ", width), bg_style)])
      List.duplicate(blank, top_pad) ++ strips ++ List.duplicate(blank, bottom_pad)
    end
  end

  @doc """
  Activates the button on mouse release, wherever in the rect it lands.

  Returns `{:ok, state}` unchanged when `:disabled`, otherwise
  `{:ok, active_state, actions}`. Accepts a raw props map as `state`.
  """
  @spec handle_mouse_up(integer(), integer(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [action()]}
  @impl Drafter.Widget
  def handle_mouse_up(_x, _y, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if state.disabled do
      {:ok, state}
    else
      activate(state)
    end
  end

  @doc """
  Activates the button on `:enter` or `:" "`; bubbles every other key.

  A disabled button still consumes `:enter` and `:" "`, returning `{:ok, state}`
  without firing `:on_click`.

      iex> b = Drafter.Widget.Button.mount(%{text: "Go"})
      iex> {tag, ^b} = Drafter.Widget.Button.handle_key(:tab, b)
      iex> tag
      :bubble

      iex> b = Drafter.Widget.Button.mount(%{text: "Go", disabled: true})
      iex> {tag, unchanged} = Drafter.Widget.Button.handle_key(:enter, b)
      iex> {tag, unchanged.active}
      {:ok, false}
  """
  @spec handle_key(Drafter.Widget.key(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [action()]} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_key(key, state) when key in [:enter, :" "] do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if state.disabled do
      {:ok, state}
    else
      activate(state)
    end
  end

  def handle_key(_key, state) do
    {:bubble, state}
  end

  @doc """
  Handles the button's out-of-band messages.

  `:activate` and `{:mouse, %{type: :press}}` activate the button unless it is
  disabled. `:deactivate` clears `:active`, `:hover` sets `:hovered` and `:unhover`
  clears it, all returning `{:ok, state}`. Anything else returns `{:bubble, state}`,
  including `:activate` on a disabled button.

      iex> b = Drafter.Widget.Button.mount(%{text: "Go"})
      iex> {:ok, hovered} = Drafter.Widget.Button.handle_custom_event(:hover, b)
      iex> hovered.hovered
      true

      iex> b = Drafter.Widget.Button.mount(%{text: "Go", disabled: true})
      iex> Drafter.Widget.Button.handle_custom_event(:activate, b) |> elem(0)
      :bubble
  """
  @spec handle_custom_event(term(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:ok, t(), [action()]} | {:bubble, t()}
  @impl Drafter.Widget
  def handle_custom_event(event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case event do
      :activate when not state.disabled ->
        activate(state)

      {:mouse, %{type: :press}} when not state.disabled ->
        activate(state)

      :deactivate ->
        {:ok, %{state | active: false}}

      :hover ->
        {:ok, %{state | hovered: true}}

      :unhover ->
        {:ok, %{state | hovered: false}}

      _ ->
        {:bubble, state}
    end
  end

  defp activate(state) do
    new_state = %{state | active: true}
    click_result = trigger_click(new_state)
    Process.send_after(self(), :deactivate, @active_effect_duration)

    actions =
      case click_result do
        nil -> []
        {:pop, _} = pop -> [pop]
        {:push, _, _} = push -> [push]
        {:replace, _, _} = replace -> [replace]
        {:app_callback, _, _} = app_callback -> [app_callback]
        _ -> []
      end

    {:ok, new_state, actions}
  end

  @doc """
  Folds fresh props into `state`.

  Re-reads `:text`, `:style`, `:focused`, `:on_click`, `:variant` (or
  `:button_type`), `:classes`, `:app_module`, `:disabled` and `:compact`, then
  rebuilds the theme class list from the variant and disabled flag. `:active` and
  `:hovered` are left as they are.

      iex> b = Drafter.Widget.Button.mount(%{text: "Save"})
      iex> updated = Drafter.Widget.Button.update(%{text: "Saved", disabled: true}, b)
      iex> {updated.text, updated.disabled, updated.classes}
      {"Saved", true, [:disabled]}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    button_type = Map.get(props, :variant) || Map.get(props, :button_type, state.button_type)
    classes_from_props = Map.get(props, :classes)
    disabled = Map.get(props, :disabled, state.disabled)

    base_classes = if classes_from_props != nil, do: classes_from_props, else: state.classes

    classes =
      if button_type != :default do
        [button_type | base_classes]
      else
        base_classes
      end

    classes = if disabled, do: [:disabled | classes], else: classes

    %{
      state
      | text: Map.get(props, :text, state.text),
        style: Map.get(props, :style, state.style),
        focused: Map.get(props, :focused, state.focused),
        on_click: Map.get(props, :on_click, state.on_click),
        button_type: button_type,
        classes: classes,
        app_module: Map.get(props, :app_module, state.app_module),
        disabled: disabled,
        compact: Map.get(props, :compact, state.compact)
    }
  end

  @doc """
  `1` when `opts[:compact]` is true, otherwise `3`.

      iex> Drafter.Widget.Button.preferred_height("Go", [])
      3

      iex> Drafter.Widget.Button.preferred_height("Go", compact: true)
      1
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts) do
    if Keyword.get(opts, :compact, false), do: 1, else: 3
  end

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Button.component_tag()
      :button
  """
  @spec component_tag() :: :button
  def component_tag, do: :button

  @doc """
  Turns the `{:button, text, opts}` element into a props map for `mount/1`.

  `text` is the positional argument. The variant is read from `:variant`, falling
  back to `:type` and then `:default`, and is emitted as `:button_type`. `:class` is
  normalised into `:classes`. `:on_click` is wrapped by
  `Drafter.Widget.Callback.wrap_0/1`, and is forced to `nil` when `disabled: true`.

      iex> props = Drafter.Widget.Button.from_component_opts("Go", type: :success, on_click: :go)
      iex> {props.text, props.button_type, props.disabled, props.compact, props.classes}
      {"Go", :success, false, false, []}

      iex> Drafter.Widget.Button.from_component_opts("Go", disabled: true, on_click: :go).on_click
      nil
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(text, opts) do
    app_module = Keyword.get(opts, :__app_module__)
    disabled = Keyword.get(opts, :disabled, false)
    compact = Keyword.get(opts, :compact, false)
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    on_click = if disabled, do: nil, else: Callback.wrap_0(Keyword.get(opts, :on_click))

    %{
      text: text,
      button_type: Keyword.get(opts, :variant, Keyword.get(opts, :type, :default)),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      disabled: disabled,
      compact: compact,
      on_click: on_click,
      app_module: app_module
    }
  end

  @doc """
  Returns `mount_props` unchanged, so a re-render passes every option through to
  `update/2`.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp trigger_click(state) do
    if state.on_click do
      state.on_click.()
    end
  end
end
