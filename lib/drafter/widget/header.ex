defmodule Drafter.Widget.Header do
  @moduledoc """
  Renders a single-row application header bar with a centred title and optional live clock.

  With `:show_clock` set, a recurring 1-second timer is started during `mount/1`
  and the current local time is rendered at the right edge. The title is centred
  in the remaining space. Clock format can be either `:time` (`HH:MM:SS`, default)
  or `:datetime` (`YYYY-MM-DD HH:MM:SS`). The clock is off unless asked for, so a
  header starts no timer of its own.

  ## Component tag

  Tag `:header`, built by `Drafter.App` as `{:header, title, opts}`:

      header(title, opts)

  The positional argument becomes `:title`, falling back to `opts[:title]` when
  `nil`. `:app_module` is supplied by the renderer.

  ## Options

    * `:title` - `t:String.t/0` displayed in the centre of the header. Default `""`.
      Supplied positionally through the `header/2` element, falling back to
      `opts[:title]` when the positional value is `nil`
    * `:show_clock` - `t:boolean/0`. Default `false`. When true, `mount/1` schedules a
      `:clock_tick` message one second out, which `handle_event/2` reschedules on
      every tick. No timer is started when no app is registered
    * `:clock_format` - `:time` (default, `HH:MM:SS`) or `:datetime`
      (`YYYY-MM-DD HH:MM:SS`). Any other value falls back to `:time`
    * `:app_module` - module used for theme resolution, passed by the renderer as
      `:__app_module__`. Default `nil`

  `update/2` re-reads all four options and starts or cancels the clock timer as
  `:show_clock` changes. Through the component tree, however, only `:title` and
  `:app_module` are re-applied on a re-render, making `:show_clock` and
  `:clock_format` effectively mount-only there.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`.

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

  @type t :: %__MODULE__{
          title: String.t(),
          show_clock: boolean(),
          clock_format: :time | :datetime,
          timer_ref: reference() | nil,
          app_module: module() | nil
        }

  @doc """
  Builds the header state from `props` and starts the clock timer when
  `:show_clock` is true and an app is registered.

      iex> h = Drafter.Widget.Header.mount(%{title: "My App", show_clock: false})
      iex> {h.title, h.show_clock, h.clock_format, h.timer_ref}
      {"My App", false, :time, nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    show_clock = Map.get(props, :show_clock, false)
    timer_ref = if show_clock, do: start_clock_timer(), else: nil

    %__MODULE__{
      title: Map.get(props, :title, ""),
      show_clock: show_clock,
      clock_format: Map.get(props, :clock_format, :time),
      timer_ref: timer_ref,
      app_module: Map.get(props, :app_module)
    }
  end

  @doc """
  Draws the header bar into `rect`, returning exactly `rect.height` strips of which
  only the first carries content.

  The clock sits at the right edge and the title is centred in the columns left over
  after one space of margin on each side. A title longer than that space is cut.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
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

  @doc """
  Folds fresh props into `state`, re-reading `:title`, `:show_clock`,
  `:clock_format` and `:app_module`.

  Turning `:show_clock` on with no timer running starts one; turning it off cancels
  the running timer.

      iex> h = Drafter.Widget.Header.mount(%{title: "One", show_clock: false})
      iex> Drafter.Widget.Header.update(%{title: "Two"}, h).title
      "Two"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc """
  Reschedules the clock on `:clock_tick`, returning `{:ok, state}` with the new
  timer reference, or with `nil` when `:show_clock` is off. Every other event
  returns `{:noreply, state}`.

      iex> h = Drafter.Widget.Header.mount(%{show_clock: false})
      iex> Drafter.Widget.Header.handle_event(:anything_else, h) |> elem(0)
      :noreply
  """
  @spec handle_event(Drafter.Event.t() | :clock_tick, t()) :: {:ok, t()} | {:noreply, t()}
  def handle_event(:clock_tick, state) do
    new_timer_ref = if state.show_clock, do: start_clock_timer(), else: nil
    {:ok, %{state | timer_ref: new_timer_ref}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  @doc "Always `1`: the header occupies a single row."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Header.component_tag()
      :header
  """
  @spec component_tag() :: :header
  def component_tag, do: :header

  @doc """
  Turns the `{:header, title, opts}` element into a props map for `mount/1`.

  A `nil` positional `title` falls back to `opts[:title]` and then to `""`.
  `:__app_module__` becomes `:app_module`.

      iex> Drafter.Widget.Header.from_component_opts(nil, title: "Dashboard")
      %{title: "Dashboard", show_clock: false, clock_format: :time, app_module: nil}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(title, opts) do
    %{
      title: title || Keyword.get(opts, :title, ""),
      show_clock: Keyword.get(opts, :show_clock, false),
      clock_format: Keyword.get(opts, :clock_format, :time),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Narrows the props a re-render feeds to `update/2` to `:title` and `:app_module`,
  so a re-render never restarts or stops the clock.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
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
