defmodule Drafter.Widget.Switch do
  @moduledoc """
  An animated toggle switch widget with on/off states.

  The slider thumb animates between positions when the state changes. The `:on_change`
  callback is fired after the animation completes, receiving the final boolean state.
  The right arrow key turns the switch on, the left arrow key turns it off, and Space
  or Enter toggles the current state.

  ## Options

    * `:enabled` - initial state; `true` for on, `false` for off (default: `false`)
    * `:label` - text displayed to the right of the switch track
    * `:on_change` - atom event name or `(boolean() -> term())` called when state settles
    * `:size` - track size: `:normal` (default), `:small`, or `:compact`
    * `:width` - total widget width in columns (default: `12`)
    * `:height` - widget height in rows (default: `1`)

  ## Usage

      switch(enabled: true, label: "Dark mode", on_change: :toggle_theme)
  """

  use Drafter.Widget,
    handles: [:keyboard, :click, :hover],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
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
    :size
  ]

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
      size: size
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

  @impl Drafter.Widget
  def handle_event(event, widget_state) do
    case event do
      :activate ->
        handle_toggle(widget_state)

      {:key, :enter} ->
        handle_toggle(widget_state)

      {:key, :" "} ->
        handle_toggle(widget_state)

      {:key, :left} -> handle_turn_off(widget_state)
      {:key, :right} -> handle_turn_on(widget_state)

      {:mouse, %{type: :mouse_up}} ->
        handle_toggle(%{widget_state | focused: true})

      {:mouse, %{type: :hover}} -> {:ok, %{widget_state | hovered: true}}
      {:mouse, %{type: :leave}} -> {:ok, %{widget_state | hovered: false}}
      {:focus} -> {:ok, %{widget_state | focused: true}}
      {:blur} -> {:ok, %{widget_state | focused: false}}
      :tick -> handle_tick(widget_state)
      _ -> {:noreply, widget_state}
    end
  end

  @impl Drafter.Widget
  def update(props, widget_state) do
    case widget_state.state do
      :animating_on ->
        new_enabled = Map.get(props, :enabled, true)
        if not new_enabled do
          %{widget_state | state: :off, slider_position: 0.0,
            label: Map.get(props, :label, widget_state.label),
            on_change: Map.get(props, :on_change, widget_state.on_change),
            width: Map.get(props, :width, widget_state.width),
            height: Map.get(props, :height, widget_state.height),
            size: Map.get(props, :size, widget_state.size)}
        else
          %{widget_state | label: Map.get(props, :label, widget_state.label),
            on_change: Map.get(props, :on_change, widget_state.on_change),
            width: Map.get(props, :width, widget_state.width),
            height: Map.get(props, :height, widget_state.height),
            size: Map.get(props, :size, widget_state.size)}
        end

      :animating_off ->
        new_enabled = Map.get(props, :enabled, false)
        if new_enabled do
          %{widget_state | state: :on, slider_position: 1.0,
            label: Map.get(props, :label, widget_state.label),
            on_change: Map.get(props, :on_change, widget_state.on_change),
            width: Map.get(props, :width, widget_state.width),
            height: Map.get(props, :height, widget_state.height),
            size: Map.get(props, :size, widget_state.size)}
        else
          %{widget_state | label: Map.get(props, :label, widget_state.label),
            on_change: Map.get(props, :on_change, widget_state.on_change),
            width: Map.get(props, :width, widget_state.width),
            height: Map.get(props, :height, widget_state.height),
            size: Map.get(props, :size, widget_state.size)}
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
          %{widget_state | label: Map.get(props, :label, widget_state.label),
            on_change: Map.get(props, :on_change, widget_state.on_change),
            width: Map.get(props, :width, widget_state.width),
            height: Map.get(props, :height, widget_state.height),
            size: Map.get(props, :size, widget_state.size)}
        end
    end
  end

  def preferred_height(_args, _opts), do: 3

  def component_tag, do: :switch

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
    {track_width, slider_width} =
      case widget_state.size do
        :small -> {6, 2}
        :compact -> {4, 2}
        _ -> {8, 4}
      end

    max_offset = track_width - slider_width

    pos = widget_state.slider_position || 0.0
    slider_offset = round(pos * max_offset)

    is_on = widget_state.state == :on or widget_state.state == :animating_on

    track_bg = {50, 55, 65}
    thumb_color = if is_on, do: {100, 200, 100}, else: {150, 150, 150}
    label_color = {200, 200, 200}

    track_style = %{fg: {80, 85, 95}, bg: track_bg}
    thumb_style = %{fg: thumb_color, bg: thumb_color}
    label_style = %{fg: label_color}

    left_width = slider_offset
    right_width = max_offset - slider_offset

    segments = []

    segments =
      if left_width > 0 do
        left_part = String.duplicate(" ", left_width)
        [Segment.new(left_part, track_style) | segments]
      else
        segments
      end

    slider_part = String.duplicate("█", slider_width)
    segments = [Segment.new(slider_part, thumb_style) | segments]

    segments =
      if right_width > 0 do
        right_part = String.duplicate(" ", right_width)
        [Segment.new(right_part, track_style) | segments]
      else
        segments
      end

    segments =
      if widget_state.label do
        label_text = " " <> widget_state.label
        [Segment.new(label_text, label_style) | segments]
      else
        segments
      end

    Strip.new(Enum.reverse(segments))
  end

  defp trigger_change(widget_state, enabled) do
    if widget_state.on_change do

      case Drafter.ScreenManager.get_active_screen() do
        nil ->
          Drafter.AppRegistry.send_to_loop( {:app_event, widget_state.on_change, enabled})

        _screen ->
          send(self(), {:tui_event, {:app_callback, widget_state.on_change, enabled}})
      end
    end
  end
end
