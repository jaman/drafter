defmodule Drafter.Widget.Checkbox do
  @moduledoc """
  A boolean toggle widget that renders an `X` mark inside a box next to an optional label.

  The checked state is toggled by pressing Space, Enter, or clicking the widget. The
  `:on_change` callback receives the new boolean value after each toggle.

  ## Component tag

  Tag `:checkbox`, built by `Drafter.App` as `{:checkbox, label, opts}`:

      checkbox(label, opts)

  The positional argument becomes `:label`. The checked state goes through
  the binding layer: passing `bind: :some_key` reads it from that app-state key
  and writes the new value back on every toggle, and `:on_change` is built from
  the same binding.

  ## Options

    * `:label` - `t:String.t/0` displayed to the right of the box. Default `""`.
      Supplied positionally through the `checkbox/2` element
    * `:checked` - `t:boolean/0` initial checked state. Default `false`
    * `:bind` - app-state key atom for two-way binding of the checked state.
      Default `nil`
    * `:on_change` - `(boolean() -> term())` called with the new value after each
      toggle. Default `nil`. An exception raised inside it is caught and ignored
    * `:style` - `t:map/0` of style overrides. Default `%{}`. An `:app_module` key
      inside this map selects the theme used for the box and label colours
    * `:focused` - `t:boolean/0` initial focus flag, read by `mount/1`. Default
      `false`
    * `:class` - accepted by the element and normalised into a `:classes` prop, but
      `mount/1` and `update/2` both ignore it, so it has no effect

  `update/2` accepts `:label`, `:checked`, `:focused`, `:style` and `:on_change` and
  silently drops every other key. Through the component tree only `:on_change` and,
  when `:bind` is set, `:checked` are re-applied on a re-render — `:label` and
  `:style` are effectively mount-only there.

  ## Widget value

  `Drafter.get_widget_value/1` returns the checked `t:boolean/0`.

  ## Key bindings

  `Enter` and `Space` with no modifiers toggle the checkbox, as does a mouse
  release. The same keys with modifiers are ignored.

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

  @doc """
  Builds the checkbox state from `props`.

  `:hovered` always starts at `false`.

      iex> cb = Drafter.Widget.Checkbox.mount(%{label: "Remember me", checked: true})
      iex> {cb.label, cb.checked, cb.focused, cb.hovered}
      {"Remember me", true, false, false}

      iex> cb = Drafter.Widget.Checkbox.mount(%{})
      iex> {cb.label, cb.checked, cb.style, cb.on_change}
      {"", false, %{}, nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the indicator and the label into `rect`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. The indicator
  takes the first three columns and the label the rest; a rect narrower than four
  columns leaves no room for the label. Returns one strip per row of `rect.height`,
  with only the first carrying content.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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

    pad_strips(
      [strip],
      rect.height,
      rect.width,
      fg || Map.get(theme, :text_primary, {200, 200, 200}),
      bg
    )
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

  @doc """
  Handles events directly instead of going through `Drafter.Widget.EventRouter`.

  `:activate`, `{:key, :enter}`, `{:key, :" "}` and `{:mouse, %{type: :mouse_up}}`
  flip `:checked` and call `:on_change` with the new value. `:hover` and `:unhover`
  set and clear `:hovered`; `{:focus}` sets both `:focused` and `:hovered`, and
  `{:blur}` clears both. Everything else, including a key event carrying modifiers,
  returns `{:noreply, state}`.

      iex> cb = Drafter.Widget.Checkbox.mount(%{label: "Agree"})
      iex> {:ok, toggled} = Drafter.Widget.Checkbox.handle_event({:key, :" "}, cb)
      iex> toggled.checked
      true

      iex> cb = Drafter.Widget.Checkbox.mount(%{label: "Agree"})
      iex> {:ok, focused} = Drafter.Widget.Checkbox.handle_event({:focus}, cb)
      iex> {focused.focused, focused.hovered}
      {true, true}

      iex> cb = Drafter.Widget.Checkbox.mount(%{label: "Agree"})
      iex> Drafter.Widget.Checkbox.handle_event({:key, :enter, [:shift]}, cb) |> elem(0)
      :noreply
  """
  @spec handle_event(Drafter.Event.t() | atom(), t()) :: {:ok, t()} | {:noreply, t()}
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

  @doc """
  Folds fresh props into `state`.

  Only `:label`, `:checked`, `:focused`, `:style` and `:on_change` are applied; any
  other key in `props` is dropped without error.

      iex> cb = Drafter.Widget.Checkbox.mount(%{label: "Agree"})
      iex> updated = Drafter.Widget.Checkbox.update(%{checked: true, nonsense: 1}, cb)
      iex> {updated.checked, updated.label}
      {true, "Agree"}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc "Always `1`: the checkbox occupies a single row."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Checkbox.component_tag()
      :checkbox
  """
  @spec component_tag() :: :checkbox
  def component_tag, do: :checkbox

  @doc """
  Turns the `{:checkbox, label, opts}` element into a props map for `mount/1`.

  `label` is the positional argument. The checked state comes from `:bind` read
  against `opts[:__app_state__]`, falling back to `opts[:checked]` and then `false`,
  and `:on_change` is the binding's writer. The emitted `:classes` key is not read
  by `mount/1`.

      iex> props = Drafter.Widget.Checkbox.from_component_opts("Agree", checked: true)
      iex> {props.label, props.checked, props.style, props.classes}
      {"Agree", true, %{}, []}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(label, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    checked = Drafter.Binding.get_bound_value(opts, app_state, Keyword.get(opts, :checked, false))
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    %{
      label: label,
      checked: checked,
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      on_change: Drafter.Binding.create_bound_callback(opts, :checked)
    }
  end

  @doc """
  Narrows the props a re-render feeds to `update/2`.

  Always passes `:on_change` and `:classes`, and adds `:checked` only when `opts`
  carries a `:bind`. `:label` and `:style` are deliberately left out, so a re-render
  does not overwrite them.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
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
