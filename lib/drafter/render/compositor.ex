defmodule Drafter.Compositor do
  @moduledoc """
  Holds one session's screen as rows of styled cells and writes changed rows to its terminal.

  The screen buffer is a list of `Drafter.Draw.Strip`, one per row, each padded to the
  screen width. `render_strips/3` blits strips into it at a cell position; the frame is
  written on the next `:render_frame` message, and only rows whose cache key changed are
  sent, wrapped in synchronized-update markers unless `DRAFTER_NO_SYNC` is set. Every
  byte for the terminal goes through the session's `Drafter.Render.Writer`. While text
  handed to it is still unwritten no new frame is written, so a link that cannot keep up
  sees fewer, complete frames, the rows changed meanwhile merged into one diff; a frame's
  image bytes follow its text and are written only while no newer image has arrived.

      Drafter.Compositor.render_strips([Drafter.Draw.Strip.from_text("hello")], 2, 0)

  One compositor exists per session and is resolved through `Drafter.Session.Context`
  under the `:compositor` key, so the module-level functions address the caller's own
  session. The writer's sink is the session's terminal driver, or, for the local
  terminal, `/dev/tty` unless `DRAFTER_NO_PACED_WRITE` is set.

  A resize arrives as `{:tui_event, {:resize, {cols, rows}}}` from the event manager;
  the buffer is rebuilt empty at the new size and the whole screen is marked dirty.

  ## Images

  Terminal-graphics bytes live outside the cell grid. A widget registers them with
  `put_image/4`, positions them with `place_image/3` and withdraws them with
  `clear_image/1`. Images are drawn after the text of a frame, and are redrawn when
  their bytes or position changed. A text row an image lies on is written around the
  image, the cells it covers left alone, so text changing beside an image never touches
  it. When the text under an image changes, it is written and the image placed again over
  it in the same frame (by its placement bytes where it has them, else in full), so what
  lies beneath an image on the terminal is always the text of the screen.

  An image is shown inside the window `place_image/4` gives it and inside the screen. A
  region carrying `:crop` is a stored kitty image: the compositor draws whatever part
  of it is inside those bounds with a placement, and moves it with a placement, never
  sending its pixels again. Any other region is drawn only when its whole rectangle is
  inside them. An image that stops being drawable while on the terminal is taken off
  with its `clear` sequence.

  Stamps order concurrent generations: a `put_image/4` whose `stamp` is not greater
  than the highest stamp already accepted for that id is discarded. `clear_image/1`
  forgets the id's stamp, so the next `put_image/4` for it is accepted whatever its
  stamp.
  """

  use GenServer

  require Logger

  alias Drafter.Draw.Strip
  alias Drafter.Render.{Picture, RowDamage, Writer}
  alias FrenchCurve.Backend.Kitty

  @behind_poll_ms 4
  @stall_report_ms 5_000
  alias Drafter.{Event, Terminal}
  alias Drafter.Session.Context

  defstruct [
    :terminal_driver,
    :event_manager,
    :writer,
    screen_buffer: [],
    rendered_buffer: [],
    dirty_regions: [],
    screen_size: {80, 24},
    rendering: false,
    image_regions: %{},
    painted_images: %{},
    image_stamps: %{},
    pending_image_clears: [],
    stalled_since: nil,
    stall_reported: false
  ]

  @typedoc "The screen as one padded `Drafter.Draw.Strip` per row, top row first."
  @type screen_buffer :: [Strip.t()]

  @typedoc """
  A rectangle of cells recorded as changed since the last frame.

  Whether any region is recorded is what decides that a frame is due; which rows
  are actually written is decided by comparing strip cache keys. `width` and
  `height` are therefore not clipped to the screen and can be zero or negative for
  a rectangle that starts past an edge.
  """
  @type dirty_region :: %{
          x: integer(),
          y: integer(),
          width: integer(),
          height: integer()
        }

  @typedoc """
  Where an image sits and how big it is, as a widget's `image/3` returns it.

  `:stamp`, `:place` and `:crop` are optional, defaulting to `0`, `nil` and `nil`.
  """
  @type image_region :: %{
          required(:dx) => integer(),
          required(:dy) => integer(),
          required(:cols) => non_neg_integer(),
          required(:rows) => non_neg_integer(),
          optional(:stamp) => integer(),
          optional(:place) => iodata() | nil,
          optional(:crop) => Picture.crop() | nil
        }

  @typedoc "A rectangle of screen cells an image may be drawn inside."
  @type window :: %{
          x: integer(),
          y: integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @doc """
  Start a compositor.

  Options:

    * `:name` — registered name, default `Drafter.Compositor`. Pass `nil` to start
      it unregistered, which is what a session that is not the local terminal does.
    * `:terminal_driver` — `Drafter.Terminal.Driver` (the default) or a
      `{module, pid}` pair whose module exports `write/2` and `get_size/1`.
    * `:event_manager` — manager to subscribe to for resize events, default
      `Drafter.Event.Manager`.

  The initial screen size is read from the terminal driver. When the driver is
  `Drafter.Terminal.Driver` and `DRAFTER_NO_PACED_WRITE` is unset, `/dev/tty` is
  opened once here and every frame is written to it instead of through the driver;
  it is closed on termination.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Blit `strips` into the screen buffer with their top-left corner at cell `x`, `y`.

  One strip per row, applied downwards from `y`. `x` and `y` are zero-based and
  both default to `0`. Rows that fall outside the screen are dropped. A row is
  padded with spaces out to the screen width, and an `x` of `0` or less replaces
  the whole row. Callers are responsible for supplying strips that fit: a strip
  reaching past the right edge leaves that row longer than the screen.

  The affected rectangle is marked dirty and a frame is scheduled. Asynchronous.

      Drafter.Compositor.render_strips([Drafter.Draw.Strip.from_text("hello")], 2, 0)
  """
  @spec render_strips([Strip.t()], non_neg_integer(), non_neg_integer()) :: :ok
  def render_strips(strips, x \\ 0, y \\ 0) do
    GenServer.cast(resolve(), {:render_strips, strips, x, y})
  end

  @doc """
  Blank the whole screen buffer and withdraw every image region.

  Each image's `clear` sequence is queued so the terminal releases it. The regions
  themselves are forgotten, bytes, positions and stamps alike, so a later
  `place_image/3` for the same id shows nothing until `put_image/4` supplies bytes
  again. Asynchronous.
  """
  @spec clear_screen() :: :ok
  def clear_screen do
    GenServer.cast(resolve(), :clear_screen)
  end

  @doc """
  Redraw every row on the next frame, keeping the buffer contents.

  Use after something outside the compositor has written to the terminal, which
  makes the record of what is on screen untrustworthy. Asynchronous.
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(resolve(), :refresh)
  end

  @doc """
  Store the terminal-graphics bytes (kitty, iTerm2, sixel) for an image region.

  Arguments:

    * `id` — any term identifying the region; a later call with the same `id`
      replaces its bytes, keeping the position `place_image/3` gave it
    * `paint` — the sequence that draws the image
    * `clear` — the sequence that removes it, for protocols that hold an image
      outside the cell grid; `""` for protocols where re-blanking the cells is enough
    * `region` — where and how big the image is, as the placement map a widget's
      `image/3` returns:

      * `:dx`, `:dy` — cell offset of the image from the position given to
        `place_image/3`, so the image is drawn at `x + dx`, `y + dy`
      * `:cols`, `:rows` — size of the image in cells, used to decide whether it fits
        on screen and which text rows it covers
      * `:stamp` — generation counter for this `id`, default `0`
      * `:place` — sequence that redraws the image the terminal is already holding,
        default `nil`
      * `:crop` — `t:Drafter.Render.Picture.crop/0` naming the stored kitty image, default
        `nil`. With it, `paint` must store the image under that id without drawing it;
        the compositor draws it with placements it builds, of the whole image or of
        the part inside the window, and `:place` is not used

  A call is discarded outright, changing nothing, when `:stamp` is less than or equal
  to the stamp of the last accepted call for the same `id`. The first call for an
  `id` is always accepted, as is the first call after a `clear_image/1`, which
  forgets the id's stamp. Callers that generate images concurrently must pass a
  counter that only ever increases for a given `id`; passing the default `0` every
  time means every call after the first is dropped.

  `place` is sent instead of `paint` when the image is unchanged and is only being
  drawn again because text was written across it. `nil` sends `paint` in that case
  too.

  Registering bytes does not make the image visible; `place_image/3` does.
  Asynchronous.
  """
  @spec put_image(term(), iodata(), iodata(), image_region()) :: :ok
  def put_image(id, paint, clear, region) do
    GenServer.cast(resolve(), {:put_image, id, paint, clear, normalize_region(region)})
  end

  defp normalize_region(region) do
    %{
      dx: Map.fetch!(region, :dx),
      dy: Map.fetch!(region, :dy),
      cols: Map.fetch!(region, :cols),
      rows: Map.fetch!(region, :rows),
      stamp: Map.get(region, :stamp, 0),
      place: Map.get(region, :place),
      crop: Map.get(region, :crop)
    }
  end

  @doc """
  Position the image region `id` with its anchor at cell `x`, `y` and mark it visible.

  `window` is the rectangle of screen cells the image may be drawn inside, such as the
  visible part of a scrolled widget; `nil` (the default) is the whole screen. The
  anchor may lie outside the window, as it does for a widget scrolled partly out of
  view.

  Carries no image bytes. Calling it for an `id` that has no bytes yet records the
  position; nothing is drawn until `put_image/4` supplies them. The image is drawn
  after the text of a frame, and only when its bytes, its position or its window
  changed or a text row under it was redrawn. Asynchronous.
  """
  @spec place_image(term(), integer(), integer(), window() | nil) :: :ok
  def place_image(id, x, y, window \\ nil) do
    GenServer.cast(resolve(), {:place_image, id, x, y, window})
  end

  @doc """
  Hide the image region `id` and re-blank the cells it occupied.

  Queues the region's `clear` sequence and marks the rows it covered dirty, so the
  text beneath is written again. Its bytes and position are kept, so a later
  `place_image/3` shows it again.

  The id's stamp is forgotten either way, so the next `put_image/4` for it is
  accepted whatever its stamp. A region that is already hidden or has no bytes yet
  is only marked hidden, and an unknown id is ignored; neither schedules a frame.
  Asynchronous.
  """
  @spec clear_image(term()) :: :ok
  def clear_image(id) do
    GenServer.cast(resolve(), {:clear_image, id})
  end

  @doc """
  Write bytes straight to this session's terminal, outside the screen buffer.

  For control sequences addressed to the terminal itself rather than to the screen,
  such as an OSC 52 clipboard write. The bytes go to the terminal this session is
  attached to, which for a remote session is the ssh or telnet client rather than
  the tty the server was started from. Nothing is written to the cell grid and no
  row is marked dirty.
  """
  @spec write_raw(iodata()) :: :ok
  def write_raw(data) do
    GenServer.cast(resolve(), {:write_raw, data})
  end

  @doc """
  The size of the screen buffer as `{cols, rows}`.

  This is the size the buffer was built at, not a fresh measurement of the
  terminal. Synchronous.
  """
  @spec get_screen_size() :: {pos_integer(), pos_integer()}
  def get_screen_size do
    GenServer.call(resolve(), :get_screen_size)
  end

  @doc """
  Set the screen buffer to `width` by `height` cells.

  The buffer is rebuilt blank at the new size, every image region is withdrawn as
  by `clear_screen/0` and the whole screen is redrawn on the next frame. Returns
  before any of that has happened.

  This is the same path a `{:resize, {cols, rows}}` event from the event manager
  takes, so calling it does not stop the terminal's own size from winning later.
  """
  @spec resize(pos_integer(), pos_integer()) :: :ok
  def resize(width, height) do
    send(resolve(), {:tui_event, {:resize, {width, height}}})
    :ok
  end

  @doc """
  The composited screen buffer of the compositor at `pid`, one `Strip` per row.

  Takes an explicit pid rather than resolving the session, so a caller outside the
  session can read it. The rows returned are what the next frame will write from,
  which is not necessarily what is on the terminal yet. Synchronous.
  """
  @spec get_buffer(pid()) :: screen_buffer()
  def get_buffer(pid) do
    GenServer.call(pid, :get_buffer)
  end

  @doc """
  Returns once everything handed to the compositor before this call is on the
  terminal: a frame still waiting for its `:render_frame` is written now, and the
  writer has passed every byte to the driver. Takes an explicit pid, like
  `get_buffer/1`. Synchronous.
  """
  @spec sync(pid()) :: :ok
  def sync(pid) do
    GenServer.call(pid, :sync, :infinity)
  end

  @impl GenServer
  def init(opts) do
    Drafter.Trace.ensure_started()
    terminal_driver = Keyword.get(opts, :terminal_driver, Terminal.Driver)
    event_manager = Keyword.get(opts, :event_manager, Event.Manager)

    Event.Manager.subscribe_to(event_manager, self(), &resize_event?/1)

    {width, height} = driver_get_size(terminal_driver)

    empty_buffer = create_empty_buffer(width, height)

    {:ok, writer} = Writer.start_link(sink_for(terminal_driver))

    state = %__MODULE__{
      terminal_driver: terminal_driver,
      event_manager: event_manager,
      writer: writer,
      screen_buffer: empty_buffer,
      dirty_regions: [],
      screen_size: {width, height},
      rendering: false
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_screen_size, _from, state) do
    {:reply, state.screen_size, state}
  end

  def handle_call(:get_buffer, _from, state) do
    {:reply, state.screen_buffer, state}
  end

  def handle_call(:sync, _from, state) do
    Writer.flush(state.writer)
    new_state = if frame_pending?(state), do: write_frame(state), else: state
    Writer.flush(new_state.writer)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_cast({:render_strips, strips, x, y}, state) do
    new_state = render_strips_to_buffer(state, strips, x, y)
    schedule_render(new_state)
  end

  def handle_cast(:clear_screen, state) do
    {width, height} = state.screen_size
    empty_buffer = create_empty_buffer(width, height)
    new_state = discard_image_state(%{state | screen_buffer: empty_buffer, rendered_buffer: []})
    schedule_render(new_state)
  end

  def handle_cast(:refresh, state) do
    {width, height} = state.screen_size
    dirty_region = %{x: 0, y: 0, width: width, height: height}
    new_state = %{state | rendered_buffer: [], dirty_regions: [dirty_region]}
    schedule_render(new_state)
  end

  def handle_cast({:put_image, id, paint, clear, placement}, state) do
    if stale_stamp?(state.image_stamps, id, placement.stamp) do
      trace_paint(id, "stale")
      {:noreply, state}
    else
      trace_paint(id, "stored")

      base = Map.get(state.image_regions, id, unplaced_region(0, 0, nil, false))
      digest = digest(paint)

      region =
        Map.merge(base, %{
          bytes: paint,
          clear: clear,
          place: placement.place,
          crop: placement.crop,
          dx: placement.dx,
          dy: placement.dy,
          cols: placement.cols,
          rows: placement.rows,
          digest: digest,
          version: base.version + if(repeat?(base, digest, placement), do: 0, else: 1)
        })

      state = invalidate_uncovered(state, id, shown_rect(region, state.screen_size))

      schedule_render(%{
        state
        | image_regions: Map.put(state.image_regions, id, region),
          image_stamps: Map.put(state.image_stamps, id, placement.stamp)
      })
    end
  end

  def handle_cast({:place_image, id, x, y, window}, state) do
    case Map.get(state.image_regions, id) do
      %{x: ^x, y: ^y, window: ^window, visible: true} ->
        {:noreply, state}

      nil ->
        region = unplaced_region(x, y, window, true)
        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, region)})

      region ->
        moved = %{region | x: x, y: y, window: window, visible: true}
        state = invalidate_uncovered(state, id, shown_rect(moved, state.screen_size))
        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, moved)})
    end
  end

  def handle_cast({:write_raw, data}, state) do
    Writer.write(state.writer, data)
    {:noreply, state}
  end

  def handle_cast({:clear_image, id}, state) do
    case Map.get(state.image_regions, id) do
      %{visible: true, bytes: bytes} = region when not is_nil(bytes) ->
        hidden = %{region | visible: false}

        state
        |> take_off(id, region)
        |> Map.update!(:image_regions, &Map.put(&1, id, hidden))
        |> Map.update!(:image_stamps, &Map.delete(&1, id))
        |> schedule_render()

      %{} = region ->
        {:noreply,
         %{
           state
           | image_regions: Map.put(state.image_regions, id, %{region | visible: false}),
             image_stamps: Map.delete(state.image_stamps, id)
         }}

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:tui_event, {:resize, {width, height}}}, state) do
    new_buffer = create_empty_buffer(width, height)

    new_state =
      discard_image_state(%{
        state
        | screen_size: {width, height},
          screen_buffer: new_buffer,
          rendered_buffer: [],
          dirty_regions: [%{x: 0, y: 0, width: width, height: height}]
      })

    schedule_render(new_state)
  end

  def handle_info(:render_frame, state) do
    cond do
      not frame_pending?(state) ->
        {:noreply, %{state | rendering: false}}

      Writer.behind?(state.writer) ->
        Process.send_after(self(), :render_frame, @behind_poll_ms)
        {:noreply, stalled(state, System.monotonic_time(:millisecond))}

      true ->
        {:noreply, state |> drained(System.monotonic_time(:millisecond)) |> write_frame()}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %__MODULE__{writer: writer}) do
    Writer.flush(writer)
    :ok
  end

  defp stalled(%__MODULE__{stalled_since: nil} = state, now), do: %{state | stalled_since: now}

  defp stalled(%__MODULE__{stall_reported: false, stalled_since: since} = state, now)
       when now - since >= @stall_report_ms do
    Logger.warning(
      "terminal #{inspect(state.terminal_driver)} has taken no output for #{now - since} ms; frames are skipped until it does"
    )

    %{state | stall_reported: true}
  end

  defp stalled(state, _now), do: state

  defp drained(%__MODULE__{stall_reported: true, stalled_since: since} = state, now) do
    Logger.warning(
      "terminal #{inspect(state.terminal_driver)} takes output again after #{now - since} ms"
    )

    %{state | stalled_since: nil, stall_reported: false}
  end

  defp drained(state, _now), do: %{state | stalled_since: nil}

  defp resize_event?({:resize, _}), do: true
  defp resize_event?(_), do: false

  defp resolve, do: Context.fetch!(:compositor)

  defp driver_write(driver, data) when is_atom(driver), do: driver.write(data)
  defp driver_write({mod, pid}, data), do: mod.write(pid, data)

  defp driver_get_size(driver) when is_atom(driver), do: driver.get_size()
  defp driver_get_size({mod, pid}), do: mod.get_size(pid)

  defp create_empty_buffer(width, height) do
    empty_strip = Strip.from_text(String.duplicate(" ", width))
    List.duplicate(empty_strip, height)
  end

  defp render_strips_to_buffer(state, strips, x, y) do
    {buffer_width, buffer_height} = state.screen_size

    updated_buffer = update_buffer(state.screen_buffer, strips, x, y, buffer_width, buffer_height)

    strips_height = length(strips)
    strips_width = if strips_height > 0, do: Strip.width(List.first(strips)), else: 0

    dirty_region = %{
      x: x,
      y: y,
      width: min(strips_width, buffer_width - x),
      height: min(strips_height, buffer_height - y)
    }

    %{state | screen_buffer: updated_buffer, dirty_regions: [dirty_region | state.dirty_regions]}
  end

  defp update_buffer(_buffer, strips, 0, 0, buffer_width, buffer_height)
       when length(strips) == buffer_height do
    Enum.map(strips, &Strip.pad(&1, buffer_width))
  end

  defp update_buffer(buffer, strips, x, y, buffer_width, buffer_height) do
    strips
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {strip, strip_index}, acc_buffer ->
      update_buffer_row(acc_buffer, strip, x, y + strip_index, buffer_width, buffer_height)
    end)
  end

  defp update_buffer_row(buffer, _strip, _x, line_y, _buffer_width, buffer_height)
       when line_y < 0 or line_y >= buffer_height,
       do: buffer

  defp update_buffer_row(buffer, strip, x, line_y, buffer_width, _buffer_height) do
    List.update_at(buffer, line_y, fn existing_strip ->
      merge_strips(existing_strip, strip, x, buffer_width)
    end)
  end

  defp merge_strips(existing_strip, new_strip, x, buffer_width) do
    new_strip_width = Strip.width(new_strip)

    if x <= 0 do
      Strip.pad(new_strip, buffer_width)
    else
      {left_part, _} = Strip.divide(existing_strip, x)

      right_start = x + new_strip_width

      if right_start < buffer_width do
        {_, right_part} = Strip.divide(existing_strip, right_start)
        combined = Strip.combine(Strip.combine(left_part, new_strip), right_part)
        Strip.pad(combined, buffer_width)
      else
        combined = Strip.combine(left_part, new_strip)
        Strip.pad(combined, buffer_width)
      end
    end
  end

  defp frame_pending?(state) do
    state.dirty_regions != [] or state.pending_image_clears != [] or images_pending?(state)
  end

  defp write_frame(state) do
    state = withdraw_undrawable(state)
    {new_rendered, new_painted} = render_to_terminal(state)

    %{
      state
      | rendered_buffer: new_rendered,
        painted_images: new_painted,
        dirty_regions: [],
        pending_image_clears: [],
        rendering: false
    }
  end

  defp schedule_render(state) do
    if state.rendering do
      {:noreply, state}
    else
      send(self(), :render_frame)
      {:noreply, %{state | rendering: true}}
    end
  end

  defp render_to_terminal(state) do
    replace = under_changed_text(state)

    covers =
      covers(Map.drop(state.image_regions, replace), state.painted_images, state.screen_size)

    text_rows = build_terminal_output(state.screen_buffer, state.rendered_buffer, covers)

    {image_rows, new_painted} =
      build_image_output(
        state.image_regions,
        state.painted_images,
        state.screen_size,
        replace
      )

    image_block = Enum.reverse(state.pending_image_clears) ++ image_rows
    output = compose_output(text_rows)

    if output != [] do
      trace_frame(text_rows, image_rows)
      Writer.write(state.writer, output)
    end

    if image_block != [] do
      images = [image_block, Terminal.ANSI.cursor_to(1, 1), Terminal.ANSI.hide_cursor()]
      Writer.write_image(state.writer, if(swapping?(state), do: synced(images), else: images))
    end

    {state.screen_buffer, new_painted}
  end

  defp sink_for(Terminal.Driver) do
    driver = fn bytes -> driver_write(Terminal.Driver, bytes) end
    if paced_write?(), do: {:tty, driver}, else: driver
  end

  defp sink_for(driver), do: fn bytes -> driver_write(driver, bytes) end

  defp paced_write?, do: System.get_env("DRAFTER_NO_PACED_WRITE") in [nil, ""]

  defp trace_frame(text_rows, image_rows) do
    if Drafter.Trace.enabled?(), do: log_frame(text_rows, image_rows)
  end

  defp log_frame(text_rows, image_rows) do
    Drafter.Trace.log([
      "F ",
      Drafter.Trace.ts(),
      " t",
      Integer.to_string(length(text_rows)),
      " i",
      Integer.to_string(length(image_rows)),
      "\n"
    ])
  end

  defp trace_paint(id, reason) do
    if Drafter.Trace.enabled?() do
      Drafter.Trace.log(["P ", Drafter.Trace.ts(), " ", inspect(id), " ", reason, "\n"])
    end
  end

  defp build_terminal_output(screen_buffer, rendered_buffer, covers) do
    prev_tuple = List.to_tuple(rendered_buffer)
    prev_count = tuple_size(prev_tuple)

    screen_buffer
    |> Enum.with_index()
    |> Enum.reduce([], fn {strip, line_index}, rows ->
      prev_strip = if line_index < prev_count, do: elem(prev_tuple, line_index), else: nil

      if prev_strip && prev_strip.cache_key == strip.cache_key do
        rows
      else
        Enum.reverse(changed_output(prev_strip, strip, line_index, covers)) ++ rows
      end
    end)
    |> Enum.reverse()
  end

  defp changed_output(nil, strip, line_index, covers), do: row_output(strip, line_index, covers)

  defp changed_output(previous, strip, line_index, covers) do
    if covered?(covers, line_index),
      do: row_output(strip, line_index, covers),
      else: damaged_output(RowDamage.runs(previous, strip), strip, line_index, covers)
  end

  defp covered?(covers, line_index),
    do:
      Enum.any?(covers, fn {top, bottom, _left, _cols} ->
        line_index >= top and line_index <= bottom
      end)

  defp damaged_output(:whole, strip, line_index, covers),
    do: row_output(strip, line_index, covers)

  defp damaged_output(runs, strip, line_index, _covers),
    do:
      Enum.flat_map(runs, fn {from, width} -> segment(strip, line_index, from, from + width) end)

  defp row_output(strip, line_index, covers) do
    spans =
      covers
      |> Enum.filter(fn {top, bottom, _left, _cols} ->
        line_index >= top and line_index <= bottom
      end)
      |> Enum.map(fn {_top, _bottom, left, cols} -> {left, left + cols} end)
      |> Enum.sort()

    {segments, from} =
      Enum.reduce(spans, {[], 0}, fn {left, right}, {segments, from} ->
        {segment(strip, line_index, from, left) ++ segments, max(from, right)}
      end)

    Enum.reverse(segment(strip, line_index, from, Strip.width(strip)) ++ segments)
  end

  defp swapping?(state),
    do: Enum.any?(state.image_regions, fn {_id, region} -> match?(%{spare: _}, region.crop) end)

  defp segment(_strip, _line_index, from, to) when to <= from, do: []

  defp segment(strip, line_index, 0, to) when to >= strip.width,
    do: [[Terminal.ANSI.cursor_to(1, line_index + 1), Strip.to_ansi(strip)]]

  defp segment(strip, line_index, from, to),
    do: [
      [
        Terminal.ANSI.cursor_to(from + 1, line_index + 1),
        Strip.to_ansi(Strip.slice(strip, from, to - from))
      ]
    ]

  defp under_changed_text(state) do
    previous = List.to_tuple(state.rendered_buffer)
    current = List.to_tuple(state.screen_buffer)

    for {id, {_version, shown, _image}} <- state.painted_images,
        Map.has_key?(state.image_regions, id),
        text_changed_under?(shown, previous, current),
        do: id
  end

  defp text_changed_under?(shown, previous, current) do
    Enum.any?(shown.y..(shown.y + shown.height - 1)//1, fn row ->
      row < tuple_size(previous) and row < tuple_size(current) and
        span_changed?(elem(previous, row), elem(current, row), shown.x, shown.width)
    end)
  end

  defp span_changed?(nil, _current, _left, _cols), do: true
  defp span_changed?(_previous, nil, _left, _cols), do: false

  defp span_changed?(previous, current, _left, _cols)
       when previous.cache_key == current.cache_key,
       do: false

  defp span_changed?(previous, current, left, cols),
    do:
      Strip.to_ansi(Strip.slice(previous, left, cols)) !=
        Strip.to_ansi(Strip.slice(current, left, cols))

  defp covers(image_regions, painted, screen_size) do
    for {id, region} <- image_regions,
        paintable?(region, screen_size),
        not needs_paint?(region, Map.get(painted, id), screen_size) do
      shown = shown_rect(region, screen_size)
      {shown.y, shown.y + shown.height - 1, shown.x, shown.width}
    end
  end

  defp build_image_output(image_regions, painted, screen_size, replace) do
    Enum.reduce(image_regions, {[], painted}, fn {id, region}, {rows, painted_acc} ->
      cond do
        should_paint?(region, Map.get(painted_acc, id), screen_size) ->
          paint_region(id, region, {rows, painted_acc}, screen_size)

        id in replace and paintable?(region, screen_size) ->
          paint_region(id, region, {rows, painted_acc}, screen_size)

        true ->
          {rows, painted_acc}
      end
    end)
  end

  defp should_paint?(region, painted, screen_size) do
    paintable = paintable?(region, screen_size)

    if not paintable and region.bytes != nil and Drafter.Trace.enabled?() do
      Drafter.Trace.log([
        "P ",
        Drafter.Trace.ts(),
        " unpaintable visible=",
        inspect(region.visible),
        " at=",
        inspect({region.x + region.dx, region.y + region.dy, region.cols, region.rows}),
        " screen=",
        inspect(screen_size),
        "\n"
      ])
    end

    paintable and needs_paint?(region, painted, screen_size)
  end

  defp paint_region(id, region, {rows, painted_acc}, screen_size) do
    painted = Map.get(painted_acc, id)
    shown = shown_rect(region, screen_size)
    changed? = needs_paint?(region, painted, screen_size)
    trace_paint(id, if(changed?, do: "v", else: "o"))

    {cmd, image} = paint_command(region, shown, changed?, painted)
    {[cmd | rows], Map.put(painted_acc, id, {region.version, shown, image})}
  end

  defp paint_command(%{crop: %{spare: spare} = crop} = region, shown, _changed?, painted) do
    showing = showing(painted)

    if new_content?(region, painted) do
      image = if showing == crop.image, do: spare, else: crop.image
      retire = if showing in [nil, image], do: [], else: Kitty.delete(id: showing)

      {[
         region.bytes,
         Kitty.transmit_encoded(crop.encoded, image),
         placed(region, shown, image),
         retire
       ], image}
    else
      image = showing || crop.image
      {placed(region, shown, image), image}
    end
  end

  defp paint_command(%{crop: crop} = region, shown, _changed?, painted) when is_map(crop) do
    bytes = if new_content?(region, painted), do: region.bytes, else: []
    {[bytes, placed(region, shown, crop.image)], crop.image}
  end

  defp paint_command(region, shown, changed?, _painted) do
    bytes = if changed?, do: region.bytes, else: Map.get(region, :place) || region.bytes
    {[Terminal.ANSI.cursor_to(shown.x + 1, shown.y + 1), bytes], nil}
  end

  defp placed(region, shown, image) do
    full = image_rect(region)
    cells = {shown.x - full.x, shown.y - full.y, shown.width, shown.height}
    crop = region.crop

    [
      Terminal.ANSI.cursor_to(shown.x + 1, shown.y + 1),
      Kitty.place(image,
        placement: 1,
        fit: {shown.width, shown.height},
        source: Picture.source({crop.width, crop.height}, {region.cols, region.rows}, cells)
      )
    ]
  end

  defp showing(nil), do: nil
  defp showing({_version, _shown, image}), do: image

  defp new_content?(_region, nil), do: true
  defp new_content?(region, {version, _shown, _image}), do: region.version != version

  defp paintable?(region, screen_size) do
    region.visible and not is_nil(region.bytes) and shown_rect(region, screen_size) != nil
  end

  defp shown_rect(region, {width, height}) do
    full = image_rect(region)
    screen = %{x: 0, y: 0, width: width, height: height}
    bounds = if region.window, do: intersect(region.window, screen), else: screen

    case bounds && intersect(full, bounds) do
      nil -> nil
      ^full -> full
      partial -> if croppable?(region), do: partial, else: nil
    end
  end

  defp croppable?(region), do: is_map(Map.get(region, :crop))

  defp intersect(a, b) do
    left = max(a.x, b.x)
    top = max(a.y, b.y)
    right = min(a.x + a.width, b.x + b.width)
    bottom = min(a.y + a.height, b.y + b.height)

    if right > left and bottom > top,
      do: %{x: left, y: top, width: right - left, height: bottom - top},
      else: nil
  end

  defp repeat?(%{bytes: bytes, digest: digest} = base, digest, placement)
       when not is_nil(bytes) and not is_nil(digest) do
    Map.get(base, :dx) == placement.dx and Map.get(base, :dy) == placement.dy and
      Map.get(base, :cols) == placement.cols and Map.get(base, :rows) == placement.rows and
      Map.get(base, :place) == placement.place and Map.get(base, :crop) == placement.crop
  end

  defp repeat?(_base, _digest, _placement), do: false

  defp digest(paint), do: :erlang.phash2(:erlang.iolist_to_binary(paint))

  defp needs_paint?(_region, nil, _screen_size), do: true

  defp needs_paint?(region, {version, shown, _image}, screen_size),
    do: region.version != version or shown_rect(region, screen_size) != shown

  defp image_rect(region) do
    %{x: region.x + region.dx, y: region.y + region.dy, width: region.cols, height: region.rows}
  end

  defp unplaced_region(x, y, window, visible) do
    %{
      bytes: nil,
      clear: "",
      place: nil,
      crop: nil,
      digest: nil,
      dx: 0,
      dy: 0,
      cols: 0,
      rows: 0,
      x: x,
      y: y,
      window: window,
      visible: visible,
      version: 0
    }
  end

  defp withdraw_undrawable(state) do
    Enum.reduce(state.painted_images, state, fn {id, _painted}, acc ->
      region = Map.get(acc.image_regions, id)

      if region && paintable?(region, acc.screen_size),
        do: acc,
        else: take_off(acc, id, region)
    end)
  end

  defp take_off(state, id, region) do
    clears =
      if region, do: [region.clear | state.pending_image_clears], else: state.pending_image_clears

    state
    |> invalidate_painted(id)
    |> Map.put(:pending_image_clears, clears)
    |> Map.update!(:painted_images, &Map.delete(&1, id))
  end

  defp invalidate_uncovered(state, id, shown) do
    case Map.get(state.painted_images, id) do
      {_version, painted, _image} when shown != nil and painted != nil ->
        if intersect(painted, shown) == painted, do: state, else: invalidate_painted(state, id)

      {_version, _painted, _image} ->
        invalidate_painted(state, id)

      nil ->
        state
    end
  end

  defp invalidate_painted(state, id) do
    case Map.get(state.painted_images, id) do
      {_version, %{} = painted, _image} ->
        %{
          state
          | dirty_regions: [painted | state.dirty_regions],
            rendered_buffer: invalidate_rows(state.rendered_buffer, painted.y, painted.height)
        }

      _ ->
        state
    end
  end

  defp compose_output([]), do: []

  defp compose_output(text_rows) do
    synced(text_rows ++ [Terminal.ANSI.cursor_to(1, 1), Terminal.ANSI.hide_cursor()])
  end

  defp synced(output) do
    if System.get_env("DRAFTER_NO_SYNC") in [nil, ""] do
      [Terminal.ANSI.sync_start()] ++ output ++ [Terminal.ANSI.sync_end()]
    else
      output
    end
  end

  defp images_pending?(state) do
    Enum.any?(state.image_regions, fn {id, region} ->
      paintable?(region, state.screen_size) and
        needs_paint?(region, Map.get(state.painted_images, id), state.screen_size)
    end) or
      Enum.any?(state.painted_images, fn {id, _painted} ->
        region = Map.get(state.image_regions, id)
        region == nil or not paintable?(region, state.screen_size)
      end)
  end

  defp stale_stamp?(stamps, id, stamp) do
    case Map.get(stamps, id) do
      nil -> false
      last -> stamp <= last
    end
  end

  defp discard_image_state(state) do
    clears =
      state.image_regions
      |> Map.values()
      |> Enum.map(&Map.get(&1, :clear, ""))
      |> Enum.reject(&(&1 == ""))

    %{
      state
      | image_regions: %{},
        painted_images: %{},
        image_stamps: %{},
        pending_image_clears: clears ++ state.pending_image_clears
    }
  end

  defp invalidate_rows([], _y, _rows), do: []

  defp invalidate_rows(buffer, y, rows) do
    buffer
    |> Enum.with_index()
    |> Enum.map(fn {strip, index} ->
      if index >= y and index < y + rows, do: nil, else: strip
    end)
  end
end
