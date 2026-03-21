defmodule Drafter.Widget.Header do
  @moduledoc """
  Renders a single-row application header bar with a centred title and optional live clock.

  When `:show_clock` is `true` (default), a recurring 1-second timer is started
  during `mount/1` and the current local time is rendered at the right edge. The
  title is centred in the remaining space. Clock format can be either `:time`
  (`HH:MM:SS`, default) or `:datetime` (`YYYY-MM-DD HH:MM:SS`).

  ## Options

    * `:title` - string displayed in the centre of the header (default `""`)
    * `:show_clock` - show a live clock at the right edge: `true` (default) / `false`
    * `:clock_format` - clock display format: `:time` (default) or `:datetime`
    * `:app_module` - app module used for theme resolution

  ## Usage

      header(title: "My App")
      header(title: "Dashboard", show_clock: true, clock_format: :datetime)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :title,
    :show_clock,
    :clock_format,
    :timer_ref,
    :app_module
  ]

  def mount(props) do
    show_clock = Map.get(props, :show_clock, true)
    timer_ref = if show_clock, do: start_clock_timer(), else: nil

    %__MODULE__{
      title: Map.get(props, :title, ""),
      show_clock: show_clock,
      clock_format: Map.get(props, :clock_format, :time),
      timer_ref: timer_ref,
      app_module: Map.get(props, :app_module)
    }
  end

  def render(state, rect) do
    computed_opts = if state.app_module, do: [app_module: state.app_module], else: []
    computed = Computed.for_widget(:header, state, computed_opts)
    title_computed = Computed.for_part(:header, state, :title, computed_opts)
    clock_computed = Computed.for_part(:header, state, :clock, computed_opts)

    bg_style = Computed.to_segment_style(computed)
    title_style = Computed.to_segment_style(title_computed)
    clock_style = Computed.to_segment_style(clock_computed)

    clock_text = if state.show_clock, do: format_clock(state.clock_format), else: ""
    clock_width = String.length(clock_text)

    title = state.title || ""
    available_width = rect.width - clock_width - 2

    centered_title = center_text(title, available_width)

    padding_after_title = available_width - String.length(centered_title)
    padding = String.duplicate(" ", max(0, padding_after_title))

    strip =
      Strip.new([
        Segment.new(" ", bg_style),
        Segment.new(centered_title, title_style),
        Segment.new(padding, bg_style),
        Segment.new(clock_text, clock_style),
        Segment.new(" ", bg_style)
      ])

    if rect.height > 1 do
      empty_line = Segment.new(String.duplicate(" ", rect.width), bg_style)
      empty_strip = Strip.new([empty_line])
      padding_strips = List.duplicate(empty_strip, rect.height - 1)
      [strip | padding_strips]
    else
      [strip]
    end
  end

  def update(props, state) do
    new_show_clock = Map.get(props, :show_clock, state.show_clock)

    new_timer_ref =
      cond do
        new_show_clock and not state.show_clock and is_nil(state.timer_ref) ->
          start_clock_timer()

        not new_show_clock and not is_nil(state.timer_ref) ->
          stop_clock_timer(state.timer_ref)
          nil

        true ->
          state.timer_ref
      end

    %{
      state
      | title: Map.get(props, :title, state.title),
        show_clock: new_show_clock,
        clock_format: Map.get(props, :clock_format, state.clock_format),
        timer_ref: new_timer_ref,
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  def handle_event(:clock_tick, state) do
    new_timer_ref = if state.show_clock, do: start_clock_timer(), else: nil
    {:ok, %{state | timer_ref: new_timer_ref}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :header

  def from_component_opts(title, opts) do
    %{
      title: title || Keyword.get(opts, :title, ""),
      show_clock: Keyword.get(opts, :show_clock, true),
      clock_format: Keyword.get(opts, :clock_format, :time),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      title: mount_props.title,
      app_module: mount_props.app_module
    }
  end

  defp start_clock_timer do
    if Drafter.AppRegistry.whereis() do
      Process.send_after(self(), :clock_tick, 1000)
    else
      nil
    end
  end

  defp stop_clock_timer(timer_ref) when is_reference(timer_ref) do
    Process.cancel_timer(timer_ref)
  end

  defp stop_clock_timer(_), do: :ok

  defp format_clock(:time) do
    {{_y, _m, _d}, {h, m, s}} = :calendar.local_time()
    h_str = String.pad_leading(Integer.to_string(h), 2, "0")
    m_str = String.pad_leading(Integer.to_string(m), 2, "0")
    s_str = String.pad_leading(Integer.to_string(s), 2, "0")
    "#{h_str}:#{m_str}:#{s_str}"
  end

  defp format_clock(:datetime) do
    {{y, m, d}, {h, mi, s}} = :calendar.local_time()
    date = "#{y}-#{pad(m)}-#{pad(d)}"
    time = "#{pad(h)}:#{pad(mi)}:#{pad(s)}"
    "#{date} #{time}"
  end

  defp format_clock(_), do: format_clock(:time)

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp center_text(text, width) do
    text_len = String.length(text)

    if text_len >= width do
      String.slice(text, 0, width)
    else
      total_padding = width - text_len
      left_padding = div(total_padding, 2)
      String.duplicate(" ", left_padding) <> text
    end
  end
end
