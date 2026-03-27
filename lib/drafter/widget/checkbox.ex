defmodule Drafter.Widget.Checkbox do
  @moduledoc """
  A boolean toggle widget that renders an `X` mark inside a box next to an optional label.

  The checked state is toggled by pressing Space, Enter, or clicking the widget. The
  `:on_change` callback receives the new boolean value after each toggle.

  ## Options

    * `:label` - text displayed to the right of the checkbox (default: `""`)
    * `:checked` - initial checked state (default: `false`)
    * `:on_change` - `(boolean() -> term())` called when the checked state changes
    * `:style` - map of style overrides

  ## Usage

      checkbox("Remember me", checked: false, on_change: fn checked -> IO.inspect(checked) end)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :click, :hover]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  defstruct [
    :label,
    :checked,
    :focused,
    :hovered,
    :style,
    :on_change
  ]

  @type t :: %__MODULE__{
          label: String.t(),
          checked: boolean(),
          focused: boolean(),
          hovered: boolean(),
          style: map(),
          on_change: (boolean() -> term()) | nil
        }

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      label: Map.get(props, :label, ""),
      checked: Map.get(props, :checked, false),
      focused: Map.get(props, :focused, false),
      hovered: false,
      style: Map.get(props, :style, %{}),
      on_change: Map.get(props, :on_change)
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    ns = if is_struct(state, __MODULE__), do: state, else: mount(state)
    computed = Computed.for_widget(:checkbox, ns, style: ns.style)
    fg = computed[:color]
    bg = computed[:background]

    app_module = ns.style[:app_module]
    theme = if app_module, do: app_module.__theme__(:get), else: Drafter.Theme.dark_theme()

    checkbox_segments = render_checkbox_indicator(ns, fg, bg, theme)
    label_segment = render_checkbox_label(ns, fg, bg, rect.width, theme)
    strip = Strip.new(checkbox_segments ++ [label_segment])

    pad_strips([strip], rect.height, rect.width, fg || Map.get(theme, :text_primary, {200, 200, 200}), bg)
  end

  defp render_checkbox_indicator(ns, fg, bg, theme) do
    checkbox_bg = Map.get(theme, :panel, {60, 60, 70})

    if ns.checked do
      checkbox_fg = fg || Map.get(theme, :primary, {100, 200, 100})
      [
        Segment.new(" ", %{fg: checkbox_bg, bg: bg}),
        Segment.new("X", %{fg: checkbox_fg, bg: checkbox_bg, bold: true}),
        Segment.new(" ", %{fg: checkbox_bg, bg: bg})
      ]
    else
      [
        Segment.new(" ", %{fg: checkbox_bg, bg: bg}),
        Segment.new("X", %{fg: checkbox_bg, bg: bg, bold: true}),
        Segment.new(" ", %{fg: checkbox_bg, bg: bg})
      ]
    end
  end

  defp render_checkbox_label(ns, fg, bg, width, theme) do
    text_fg = fg || Map.get(theme, :text_primary, {200, 200, 200})
    remaining_width = max(0, width - 4)

    if ns.label && ns.label != "" do
      Segment.new(String.pad_trailing(" " <> ns.label, remaining_width), %{fg: text_fg, bg: bg})
    else
      Segment.new(String.duplicate(" ", remaining_width), %{fg: text_fg, bg: bg})
    end
  end

  defp pad_strips(strips, target_height, width, fg, bg) do
    if target_height > 1 do
      empty_strip = Strip.new([Segment.new(String.duplicate(" ", width), %{fg: fg, bg: bg})])
      strips ++ List.duplicate(empty_strip, target_height - 1)
    else
      strips
    end
  end

  @impl Drafter.Widget
  def handle_event(:activate, state), do: toggle_checkbox(state)
  def handle_event({:key, :enter}, state), do: toggle_checkbox(state)
  def handle_event({:key, :" "}, state), do: toggle_checkbox(state)
  def handle_event({:mouse, %{type: :mouse_up}}, state), do: toggle_checkbox(state)
  def handle_event(:hover, state), do: {:ok, %{state | hovered: true}}
  def handle_event(:unhover, state), do: {:ok, %{state | hovered: false}}
  def handle_event({:focus}, state), do: {:ok, %{state | focused: true, hovered: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false, hovered: false}}
  def handle_event(_, state), do: {:noreply, state}

  @impl Drafter.Widget
  def update(props, state) do
    Enum.reduce(props, state, fn {key, value}, acc ->
      case key do
        :label -> %{acc | label: value}
        :checked -> %{acc | checked: value}
        :focused -> %{acc | focused: value}
        :style -> %{acc | style: value}
        :on_change -> %{acc | on_change: value}
        _ -> acc
      end
    end)
  end

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :checkbox

  def from_component_opts(label, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    checked = Drafter.Binding.get_bound_value(opts, app_state, Keyword.get(opts, :checked, false))
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))
    %{
      label: label,
      checked: checked,
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      on_change: Drafter.Binding.create_bound_callback(opts, :checked)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, opts) do
    base = %{
      on_change: mount_props.on_change,
      classes: mount_props.classes
    }
    if Drafter.Binding.has_binding?(opts) do
      Map.put(base, :checked, mount_props.checked)
    else
      base
    end
  end

  defp toggle_checkbox(state) do
    new_checked = !state.checked
    new_state = %{state | checked: new_checked}
    trigger_change(new_state, new_checked)
    {:ok, new_state}
  end

  defp trigger_change(state, new_value) do
    if state.on_change do
      try do
        state.on_change.(new_value)
      rescue
        _ -> :ok
      end
    end
  end
end
