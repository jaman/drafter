defmodule Drafter.Widget.Button do
  @moduledoc """
  A clickable button widget that triggers a callback when pressed or activated via keyboard.

  The button renders with a 3-line layout: a top border highlight, a centred label, and a
  bottom shadow. Visual state changes (hover, active, focused, disabled) are reflected
  through colour adjustments.

  ## Options

    * `:text` - button label string (default: `""`)
    * `:on_click` - zero-arity function called when the button is activated
    * `:variant` - visual style atom: `:default`, `:primary`, `:success`, `:warning`, `:error`
    * `:disabled` - when `true`, the button ignores all interaction (default: `false`)
    * `:style` - map of style overrides applied on top of theme defaults
    * `:classes` - list of theme class atoms for additional styling

  ## Usage

      button("Submit", on_click: fn -> :submit end, variant: :primary)
  """

  use Drafter.Widget,
    handles: [:click, :keyboard],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style
  alias Drafter.Style.Computed

  @active_effect_duration 200

  defstruct text: "",
            style: %{},
            active: false,
            hovered: false,
            on_click: nil,
            button_type: :default,
            classes: [],
            app_module: nil,
            disabled: false,
            focused: false

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
      disabled: disabled
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

    computed = Computed.for_widget(:button, state, computed_opts)

    base_bg = computed[:background] || {60, 60, 60}
    fg_color = computed[:color] || {255, 255, 255}

    bg_color =
      cond do
        state.hovered -> Style.darken(base_bg, 15)
        true -> base_bg
      end

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

    content_strips = [top_strip, mid_strip, bot_strip]

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

  @impl Drafter.Widget
  def handle_click(_x, _y, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    if state.disabled do
      {:ok, state}
    else
      activate(state)
    end
  end

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
        disabled: disabled
    }
  end

  defp trigger_click(state) do
    if state.on_click do
      state.on_click.()
    end
  end
end
