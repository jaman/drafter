defmodule Drafter.Widget.Switch do
  @moduledoc """
  An animated toggle switch widget with on/off states.

  The slider thumb animates between positions when the state changes: a toggle puts
  the widget into `:animating_on` or `:animating_off` and schedules a `:tick`
  message every 30 ms, each moving `:slider_position` by `0.25` until it reaches
  `1.0` or `0.0` and the state settles at `:on` or `:off`. `:on_change` fires only
  once the animation has finished.

  ## Component tag

  Tag `:switch`, built by `Drafter.App` as `{:switch, opts}`:

      switch(opts)
      switch(value, opts)

  The two-argument form puts `value` into `opts` under `:value`; there is no
  positional prop. `:enabled` and `:on_change` go through `Drafter.Binding`, so
  passing `bind: :some_key` reads the current state from that app-state key and
  writes the new one back when the switch settles. `:width` and `:height`
  default to the rect the parent allocated.

  ## Options

    * `:enabled` - `t:boolean/0` initial state, `true` for on. Default `false`.
    * `:bind` - app-state key atom for two-way binding of the on/off state.
      Default: none. With it set, `:enabled` is read from that key of the app state
      instead of from `opts`.
    * `:label` - `t:String.t/0` drawn to the left of the switch track, or `nil`.
      Default `nil`.
    * `:on_change` - the app callback name fired once the animation settles, with
      the new boolean as its data. Default `nil`. Through the element this is set
      to the one-argument function `Drafter.Binding.create_bound_callback/2`
      returns, which the switch passes on as a callback name rather than calling.
    * `:size` - `:normal | :small | :compact`. Default `:normal`, an 8-column track
      with a 4-column thumb; `:small` is 6 and 2, `:compact` is 4 and 2. Any other
      value is treated as `:normal`.
    * `:width` - `t:pos_integer/0`. Default `12` when mounting directly, and the
      width of `opts[:__rect__]` through the element. Held on the state and never
      read by `render/2`, which uses the rect it is given.
    * `:height` - `t:pos_integer/0`. Default `1` when mounting directly, and the
      height of `opts[:__rect__]` through the element. Held on the state and never
      read by `render/2`.
    * `:on_color` - `{r, g, b}` for the thumb when on. Default `nil`, which uses
      `{100, 200, 100}`. Read by `mount/1` only — the `switch/1` element does not
      forward it.
    * `:off_color` - `{r, g, b}` for the thumb when off. Default `nil`, which uses
      `{150, 150, 150}`. Read by `mount/1` only — the `switch/1` element does not
      forward it.
    * `:focused` - `t:boolean/0` read by `mount/1`. Default `false`.
    * `:hovered` - `t:boolean/0` read by `mount/1`. Default `false`.

  `update/2` applies `:label`, `:on_change`, `:width`, `:height`, `:size` and
  `:enabled`, and silently drops every other key, so `:focused`, `:hovered`,
  `:on_color` and `:off_color` are mount-only. Through the component tree
  `update_props_from_mount/3` narrows that further to `:on_change`, `:label` and
  `:size`, plus `:enabled` only when `:bind` is set and the bound value differs
  from the current one.

  ## Key bindings

    * `enter`, `space` - toggle
    * `right` - turn on
    * `left` - turn off

  A mouse up toggles and also focuses the switch.

  ## Widget value

  `Drafter.get_widget_value/1` returns `true` while the state is `:on` and `false`
  while it is `:off`. Mid-animation the state is `:animating_on` or
  `:animating_off`, which reads as `nil`.

  ## Usage

      switch(enabled: true, label: "Dark mode", on_change: :toggle_theme)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :click, :hover]

  alias Drafter.CharacterSet
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style
  alias Drafter.Style.Computed

  @animation_step_ms 30
  @animation_step_size 0.25

  defstruct [
    :state,
    :slider_position,
    :label,
    :focused,
    :hovered,
    :on_change,
    :width,
    :height,
    :size,
    :on_color,
    :off_color
  ]

  @type rgb :: {0..255, 0..255, 0..255}

  @type t :: %__MODULE__{
          state: :on | :off | :animating_on | :animating_off,
          slider_position: float(),
          label: String.t() | nil,
          focused: boolean(),
          hovered: boolean(),
          on_change: term(),
          width: pos_integer(),
          height: pos_integer(),
          size: :normal | :small | :compact,
          on_color: rgb() | nil,
          off_color: rgb() | nil
        }

  @doc """
  Builds the widget state from `props`.

  `:enabled` decides both `:state` (`:on` or `:off`) and `:slider_position`
  (`1.0` or `0.0`); there is no way to mount mid-animation.

      iex> state = Drafter.Widget.Switch.mount(%{})
      iex> {state.state, state.slider_position, state.size, state.width, state.height}
      {:off, 0.0, :normal, 12, 1}

      iex> state = Drafter.Widget.Switch.mount(%{enabled: true, label: "Dark mode"})
      iex> {state.state, state.slider_position, state.label}
      {:on, 1.0, "Dark mode"}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    enabled = Map.get(props, :enabled, false)
    size = Map.get(props, :size, :normal)

    %__MODULE__{
      state: if(enabled, do: :on, else: :off),
      slider_position: if(enabled, do: 1.0, else: 0.0),
      label: Map.get(props, :label),
      focused: Map.get(props, :focused, false),
      hovered: Map.get(props, :hovered, false),
      on_change: Map.get(props, :on_change),
      width: Map.get(props, :width, 12),
      height: Map.get(props, :height, 1),
      size: size,
      on_color: Map.get(props, :on_color),
      off_color: Map.get(props, :off_color)
    }
  end

  @doc """
  Draws the switch into `rect`, returning exactly `rect.height` strips.

  `state` may be a plain props map, in which case it is passed through `mount/1`
  first. The first strip holds the label followed by the track, padded with spaces
  to `rect.width`; the rest are blank. The thumb is lightened while hovered, and by
  half as much while focused.
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

    computed = Computed.for_widget(:switch, normalized_state)
    bg_style = Computed.to_segment_style(computed)

    switch_strip = render_switch(normalized_state)

    content_width = rect.width
    strip_width = Strip.width(switch_strip)

    padded_strip =
      if strip_width < content_width do
        padding = Segment.new(String.duplicate(" ", content_width - strip_width), bg_style)
        Strip.new(switch_strip.segments ++ [padding])
      else
        switch_strip
      end

    if rect.height > 1 do
      empty_line = Segment.new(String.duplicate(" ", content_width), bg_style)
      empty_strip = Strip.new([empty_line])
      padding_strips = List.duplicate(empty_strip, rect.height - 1)
      [padded_strip | padding_strips]
    else
      [padded_strip]
    end
  end

  @doc """
  Handles the switch's own events, replacing the dispatch `use Drafter.Widget`
  would otherwise generate.

  Recognised events:

    * `:activate`, `{:key, :enter}`, `{:key, :" "}` - toggle
    * `{:key, :right}` - turn on; `{:key, :left}` - turn off
    * `{:mouse, %{type: :mouse_up}}` - focus and toggle
    * `:hover` / `:unhover` - set or clear `:hovered`
    * `{:focus}` / `{:blur}` - set or clear `:focused`
    * `:tick` - advance the animation

  Starting an animation returns `{:ok, state}` and schedules the next `:tick` on
  the calling process. A toggle that has nothing to do — turning on a switch that
  is already on, or any event during an animation other than `:tick` — returns
  `{:noreply, state}`, and so does every unrecognised event.

      iex> state = Drafter.Widget.Switch.mount(%{})
      iex> {:ok, toggled} = Drafter.Widget.Switch.handle_event({:key, :enter}, state)
      iex> {toggled.state, toggled.slider_position}
      {:animating_on, 0.0}

      iex> state = Drafter.Widget.Switch.mount(%{})
      iex> Drafter.Widget.Switch.handle_event({:key, :left}, state)
      ...> |> elem(0)
      :noreply

      iex> state = Drafter.Widget.Switch.mount(%{})
      iex> {:ok, hovered} = Drafter.Widget.Switch.handle_event(:hover, state)
      iex> hovered.hovered
      true
  """
  @spec handle_event(term(), t()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(:activate, ws), do: handle_toggle(ws)
  def handle_event({:key, :enter}, ws), do: handle_toggle(ws)
  def handle_event({:key, :" "}, ws), do: handle_toggle(ws)
  def handle_event({:key, :left}, ws), do: handle_turn_off(ws)
  def handle_event({:key, :right}, ws), do: handle_turn_on(ws)
  def handle_event({:mouse, %{type: :mouse_up}}, ws), do: handle_toggle(%{ws | focused: true})
  def handle_event(:hover, ws), do: {:ok, %{ws | hovered: true}}
  def handle_event(:unhover, ws), do: {:ok, %{ws | hovered: false}}
  def handle_event({:focus}, ws), do: {:ok, %{ws | focused: true}}
  def handle_event({:blur}, ws), do: {:ok, %{ws | focused: false}}
  def handle_event(:tick, ws), do: handle_tick(ws)
  def handle_event(_, ws), do: {:noreply, ws}

  @doc """
  Folds `props` into `widget_state`, applying `:label`, `:on_change`, `:width`,
  `:height` and `:size` in every case and dropping every other key.

  `:enabled` is compared with the current state rather than assigned:

    * settled at `:on` or `:off` — an `:enabled` that differs jumps straight to the
      other state with no animation; one that matches changes nothing. Absent, it
      defaults to the current state, so the switch stays put.
    * mid-animation — an `:enabled` that agrees with where the animation is heading
      lets it finish; one that disagrees cancels it and snaps to that state. Absent,
      it defaults to the animation's destination, so the animation continues.

      iex> state = Drafter.Widget.Switch.mount(%{})
      iex> updated = Drafter.Widget.Switch.update(%{enabled: true, label: "On"}, state)
      iex> {updated.state, updated.slider_position, updated.label}
      {:on, 1.0, "On"}

      iex> state = Drafter.Widget.Switch.mount(%{enabled: true})
      iex> updated = Drafter.Widget.Switch.update(%{label: "Kept"}, state)
      iex> {updated.state, updated.label}
      {:on, "Kept"}

      iex> state = %{Drafter.Widget.Switch.mount(%{}) | state: :animating_on, slider_position: 0.5}
      iex> updated = Drafter.Widget.Switch.update(%{enabled: false}, state)
      iex> {updated.state, updated.slider_position}
      {:off, 0.0}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, widget_state) do
    case widget_state.state do
      :animating_on ->
        new_enabled = Map.get(props, :enabled, true)

        if new_enabled do
          %{
            widget_state
            | label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        else
          %{
            widget_state
            | state: :off,
              slider_position: 0.0,
              label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        end

      :animating_off ->
        new_enabled = Map.get(props, :enabled, false)

        if new_enabled do
          %{
            widget_state
            | state: :on,
              slider_position: 1.0,
              label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        else
          %{
            widget_state
            | label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        end

      _ ->
        new_enabled = Map.get(props, :enabled, widget_state.state == :on)
        current_enabled = widget_state.state == :on

        if new_enabled != current_enabled do
          %{
            widget_state
            | state: if(new_enabled, do: :on, else: :off),
              slider_position: if(new_enabled, do: 1.0, else: 0.0),
              label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        else
          %{
            widget_state
            | label: Map.get(props, :label, widget_state.label),
              on_change: Map.get(props, :on_change, widget_state.on_change),
              width: Map.get(props, :width, widget_state.width),
              height: Map.get(props, :height, widget_state.height),
              size: Map.get(props, :size, widget_state.size)
          }
        end
    end
  end

  @doc """
  The number of rows the element asks for: always `3`. There is no `:height`
  override.

      iex> Drafter.Widget.Switch.preferred_height(nil, height: 1)
      3
  """
  @spec preferred_height(term(), keyword()) :: 3
  def preferred_height(_args, _opts), do: 3

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Switch.component_tag()
      :switch
  """
  @spec component_tag() :: :switch
  def component_tag, do: :switch

  @doc """
  Builds the props map for a `{:switch, opts}` element.

  The positional argument is ignored. `:enabled` comes from
  `Drafter.Binding.get_bound_value/3`, so `bind: :key` reads it from
  `opts[:__app_state__]` and plain `enabled:` is used otherwise, defaulting to
  `false`. `:on_change` is the binding's writer, a one-argument function or `nil`.
  `:width` and `:height` fall back to `opts[:__rect__]`, itself defaulting to
  `%{width: 12, height: 1}`. `:on_color` and `:off_color` are not forwarded.

      iex> props = Drafter.Widget.Switch.from_component_opts(nil, label: "Dark")
      iex> {props.enabled, props.label, props.size, props.width, props.height, props.on_change}
      {false, "Dark", :normal, 12, 1, nil}

      iex> opts = [bind: :dark_mode, __app_state__: %{dark_mode: true}]
      iex> Drafter.Widget.Switch.from_component_opts(nil, opts).enabled
      true
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    app_state = Keyword.get(opts, :__app_state__, %{})
    rect = Keyword.get(opts, :__rect__, %{width: 12, height: 1})
    enabled = Drafter.Binding.get_bound_value(opts, app_state, Keyword.get(opts, :enabled, false))

    %{
      enabled: enabled,
      label: Keyword.get(opts, :label),
      on_change: Drafter.Binding.create_bound_callback(opts, :enabled),
      size: Keyword.get(opts, :size, :normal),
      width: Keyword.get(opts, :width, rect.width),
      height: Keyword.get(opts, :height, rect.height)
    }
  end

  @doc """
  Narrows a re-render to `:on_change`, `:label` and `:size`.

  `:enabled` is added only when `opts` carries `:bind` and the bound value differs
  from the widget's current state, so an unbound switch keeps whatever the user
  toggled it to and `:width` and `:height` are mount-only.

      iex> props = Drafter.Widget.Switch.from_component_opts(nil, label: "Dark")
      iex> state = Drafter.Widget.Switch.mount(props)
      iex> Drafter.Widget.Switch.update_props_from_mount(props, state, []) |> Map.keys() |> Enum.sort()
      [:label, :on_change, :size]

      iex> opts = [bind: :dark_mode, __app_state__: %{dark_mode: true}]
      iex> props = Drafter.Widget.Switch.from_component_opts(nil, opts)
      iex> state = Drafter.Widget.Switch.mount(%{enabled: false})
      iex> Drafter.Widget.Switch.update_props_from_mount(props, state, opts).enabled
      true
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, existing_state, opts) do
    base = %{
      on_change: mount_props.on_change,
      label: mount_props.label,
      size: mount_props.size
    }

    if Drafter.Binding.has_binding?(opts) do
      current_enabled = existing_state.state == :on
      new_enabled = mount_props.enabled

      if new_enabled != current_enabled do
        Map.put(base, :enabled, new_enabled)
      else
        base
      end
    else
      base
    end
  end

  defp handle_toggle(widget_state) do
    case widget_state.state do
      :off -> start_animation(widget_state, :animating_on)
      :on -> start_animation(widget_state, :animating_off)
      _ -> {:noreply, widget_state}
    end
  end

  defp handle_turn_on(widget_state) do
    case widget_state.state do
      :off -> start_animation(widget_state, :animating_on)
      _ -> {:noreply, widget_state}
    end
  end

  defp handle_turn_off(widget_state) do
    case widget_state.state do
      :on -> start_animation(widget_state, :animating_off)
      _ -> {:noreply, widget_state}
    end
  end

  defp start_animation(widget_state, new_state) do
    schedule_tick()
    {:ok, %{widget_state | state: new_state}}
  end

  defp handle_tick(widget_state) do
    case widget_state.state do
      :animating_on ->
        new_pos = min(1.0, widget_state.slider_position + @animation_step_size)

        if new_pos >= 1.0 do
          final_state = %{widget_state | state: :on, slider_position: 1.0}
          trigger_change(final_state, true)
          {:ok, final_state}
        else
          schedule_tick()
          {:ok, %{widget_state | slider_position: new_pos}}
        end

      :animating_off ->
        new_pos = max(0.0, widget_state.slider_position - @animation_step_size)

        if new_pos <= 0.0 do
          final_state = %{widget_state | state: :off, slider_position: 0.0}
          trigger_change(final_state, false)
          {:ok, final_state}
        else
          schedule_tick()
          {:ok, %{widget_state | slider_position: new_pos}}
        end

      _ ->
        {:noreply, widget_state}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @animation_step_ms)
  end

  defp render_switch(widget_state) do
    {track_width, slider_width} = track_dimensions(widget_state.size)
    max_offset = track_width - slider_width
    slider_offset = round((widget_state.slider_position || 0.0) * max_offset)
    is_on = widget_state.state in [:on, :animating_on]

    default_on = {100, 200, 100}
    default_off = {150, 150, 150}

    base_thumb =
      if is_on,
        do: widget_state.on_color || default_on,
        else: widget_state.off_color || default_off

    track_bg = accent({50, 55, 65}, widget_state, 18)
    track_fg = accent({80, 85, 95}, widget_state, 40)
    thumb_color = accent(base_thumb, widget_state, 25)

    track_style = %{fg: track_fg, bg: track_bg}
    thumb_style = %{fg: thumb_color, bg: thumb_color}

    segments =
      []
      |> prepend_if(slider_offset > 0, fn ->
        Segment.new(String.duplicate(" ", slider_offset), track_style)
      end)
      |> then(
        &[Segment.new(String.duplicate(CharacterSet.fill(:full), slider_width), thumb_style) | &1]
      )
      |> prepend_if(max_offset - slider_offset > 0, fn ->
        Segment.new(String.duplicate(" ", max_offset - slider_offset), track_style)
      end)
      |> prepend_if(widget_state.label != nil, fn ->
        Segment.new(" " <> widget_state.label, %{fg: {200, 200, 200}})
      end)

    Strip.new(Enum.reverse(segments))
  end

  defp accent(color, %{hovered: true}, amount), do: Style.lighten(color, amount)
  defp accent(color, %{focused: true}, amount), do: Style.lighten(color, div(amount, 2))
  defp accent(color, _widget_state, _amount), do: color

  defp track_dimensions(:small), do: {6, 2}
  defp track_dimensions(:compact), do: {4, 2}
  defp track_dimensions(_), do: {8, 4}

  defp prepend_if(list, true, segment_fn), do: [segment_fn.() | list]
  defp prepend_if(list, false, _segment_fn), do: list

  defp trigger_change(widget_state, enabled) do
    if widget_state.on_change do
      case Drafter.ScreenManager.get_active_screen() do
        nil ->
          Drafter.AppRegistry.send_to_loop({:app_event, widget_state.on_change, enabled})

        _screen ->
          send(self(), {:tui_event, {:app_callback, widget_state.on_change, enabled}})
      end
    end
  end
end
