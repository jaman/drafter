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
    handles: [:keyboard, :click, :hover],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Theme

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
    normalized_state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    computed = Computed.for_widget(:checkbox, normalized_state, style: normalized_state.style)

    fg = computed[:color]
    bg = computed[:background]

    app_module = normalized_state.style[:app_module]
    theme = if app_module, do: app_module.__theme__(:get), else: Drafter.Theme.dark_theme()

    checkbox_bg = Map.get(theme, :panel, {60, 60, 70})
    checkbox_bg_dimmed = Theme.mute_color(checkbox_bg)

    checkbox_fg = if normalized_state.checked, do: fg || Map.get(theme, :primary, {100, 200, 100}), else: checkbox_bg_dimmed

    checkbox_colored = if normalized_state.checked do
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

    segments = if normalized_state.label && normalized_state.label != "" do
      label_text = " " <> normalized_state.label
      remaining_width = max(0, rect.width - 4)
      label_padded = String.pad_trailing(label_text, remaining_width)
      label_fg = fg || Map.get(theme, :text_primary, {200, 200, 200})
      checkbox_colored ++ [Segment.new(label_padded, %{fg: label_fg, bg: bg})]
    else
      padding_width = max(0, rect.width - 4)
      padding = String.duplicate(" ", padding_width)
      text_fg = fg || Map.get(theme, :text_primary, {200, 200, 200})
      checkbox_colored ++ [Segment.new(padding, %{fg: text_fg, bg: bg})]
    end

    strip = Strip.new(segments)

    target_height = rect.height

    if target_height > 1 do
      text_fg = fg || Map.get(theme, :text_primary, {200, 200, 200})
      empty_segment = Segment.new(String.duplicate(" ", rect.width), %{fg: text_fg, bg: bg})
      empty_strip = Strip.new([empty_segment])
      padding_lines = List.duplicate(empty_strip, target_height - 1)
      [strip] ++ padding_lines
    else
      [strip]
    end
  end

  @impl Drafter.Widget
  def handle_event(event, state) do
    case event do
      :activate ->
        toggle_checkbox(state)

      {:key, :enter} ->
        toggle_checkbox(state)

      {:key, :" "} ->
        toggle_checkbox(state)

      {:mouse, %{type: :mouse_up}} ->
        toggle_checkbox(state)

      :hover ->
        {:ok, %{state | hovered: true}}

      :unhover ->
        {:ok, %{state | hovered: false}}

      {:focus} ->
        {:ok, %{state | focused: true, hovered: true}}

      {:blur} ->
        {:ok, %{state | focused: false, hovered: false}}

      _ ->
        {:noreply, state}
    end
  end

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
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
      c when is_binary(c) -> String.to_atom(c)
      c when is_atom(c) -> c
    end)
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
