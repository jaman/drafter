defmodule Drafter.Compositor do
  @moduledoc """
  Holds one session's screen as rows of styled cells and writes changed rows to its terminal.

  The screen buffer is a list of `Drafter.Draw.Strip`, one per row, each padded to the
  screen width. `render_strips/3` blits strips into it at a cell position; the frame is
  written on the next `:render_frame` message, and only rows whose cache key changed are
  sent. Frames are wrapped in synchronized-update markers unless `DRAFTER_NO_SYNC` is set.

      Drafter.Compositor.render_strips([Drafter.Draw.Strip.from_text("hello")], 2, 0)

  One compositor exists per session and is resolved through `Drafter.Session.Context`
  under the `:compositor` key, so the module-level functions address the caller's own
  session. Output goes to the session's terminal driver, or, for the local terminal,
  straight to `/dev/tty` unless `DRAFTER_NO_PACED_WRITE` is set.

  A resize arrives as `{:tui_event, {:resize, {cols, rows}}}` from the event manager;
  the buffer is rebuilt empty at the new size and the whole screen is marked dirty.

  ## Images

  Terminal-graphics bytes live outside the cell grid. A widget registers them with
  `put_image/4`, positions them with `place_image/3` and withdraws them with
  `clear_image/1`. Images are drawn after the text of a frame, and are redrawn when
  their bytes or position changed or when a text row beneath them was rewritten. An
  image whose rectangle does not fit entirely on screen is not drawn at all.

  Stamps order concurrent generations: a `put_image/4` whose `stamp` is not greater
  than the highest stamp already accepted for that id is discarded. `clear_image/1`
  forgets the id's stamp, so the next `put_image/4` for it is accepted whatever its
  stamp.
  """

  use GenServer

  alias Drafter.Draw.Strip
  alias Drafter.{Event, Terminal}
  alias Drafter.Session.Context

  defstruct [
    :terminal_driver,
    :event_manager,
    :paced_tty,
    screen_buffer: [],
    rendered_buffer: [],
    dirty_regions: [],
    screen_size: {80, 24},
    rendering: false,
    image_regions: %{},
    painted_images: %{},
    image_stamps: %{},
    pending_image_clears: []
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

  `:stamp` and `:place` are optional, defaulting to `0` and `nil`.
  """
  @type image_region :: %{
          required(:dx) => integer(),
          required(:dy) => integer(),
          required(:cols) => non_neg_integer(),
          required(:rows) => non_neg_integer(),
          optional(:stamp) => integer(),
          optional(:place) => iodata() | nil
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
      place: Map.get(region, :place)
    }
  end

  @doc """
  Position the image region `id` with its anchor at cell `x`, `y` and mark it visible.

  Carries no image bytes. Calling it for an `id` that has no bytes yet records the
  position; nothing is drawn until `put_image/4` supplies them. The image is drawn
  after the text of a frame, and only when its bytes or position changed or a text
  row under it was redrawn. Asynchronous.
  """
  @spec place_image(term(), non_neg_integer(), non_neg_integer()) :: :ok
  def place_image(id, x, y) do
    GenServer.cast(resolve(), {:place_image, id, x, y})
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

  @impl GenServer
  def init(opts) do
    Drafter.Trace.ensure_started()
    terminal_driver = Keyword.get(opts, :terminal_driver, Terminal.Driver)
    event_manager = Keyword.get(opts, :event_manager, Event.Manager)

    Event.Manager.subscribe_to(event_manager, self(), &resize_event?/1)

    {width, height} = driver_get_size(terminal_driver)

    empty_buffer = create_empty_buffer(width, height)

    state = %__MODULE__{
      terminal_driver: terminal_driver,
      event_manager: event_manager,
      paced_tty: open_paced_tty(terminal_driver),
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
      {:noreply, state}
    else
      base =
        Map.get(state.image_regions, id, %{
          x: 0,
          y: 0,
          visible: false,
          version: 0,
          clear: "",
          place: nil
        })

      region =
        Map.merge(base, %{
          bytes: paint,
          clear: clear,
          place: placement.place,
          dx: placement.dx,
          dy: placement.dy,
          cols: placement.cols,
          rows: placement.rows,
          version: base.version + 1
        })

      state = if covers?(base, region), do: state, else: invalidate_region(state, base)

      schedule_render(%{
        state
        | image_regions: Map.put(state.image_regions, id, region),
          image_stamps: Map.put(state.image_stamps, id, placement.stamp)
      })
    end
  end

  def handle_cast({:place_image, id, x, y}, state) do
    case Map.get(state.image_regions, id) do
      %{x: ^x, y: ^y, visible: true} ->
        {:noreply, state}

      nil ->
        region = %{
          bytes: nil,
          clear: "",
          dx: 0,
          dy: 0,
          cols: 0,
          rows: 0,
          x: x,
          y: y,
          visible: true,
          version: 0
        }

        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, region)})

      region ->
        moved = %{region | x: x, y: y, visible: true}

        state =
          if (region.x != x or region.y != y) and not is_nil(region.bytes),
            do: invalidate_region(state, region),
            else: state

        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, moved)})
    end
  end

  def handle_cast({:write_raw, data}, state) do
    write_output(state, data)
    {:noreply, state}
  end

  def handle_cast({:clear_image, id}, state) do
    case Map.get(state.image_regions, id) do
      %{visible: true, bytes: bytes} = region when not is_nil(bytes) ->
        hidden = %{region | visible: false}

        schedule_render(%{
          state
          | image_regions: Map.put(state.image_regions, id, hidden),
            painted_images: Map.delete(state.painted_images, id),
            image_stamps: Map.delete(state.image_stamps, id),
            pending_image_clears: [region.clear | state.pending_image_clears],
            dirty_regions: [image_rect(region) | state.dirty_regions],
            rendered_buffer:
              invalidate_rows(state.rendered_buffer, region.y + region.dy, region.rows)
        })

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
    if Enum.empty?(state.dirty_regions) and state.pending_image_clears == [] and
         not images_pending?(state) do
      {:noreply, %{state | rendering: false}}
    else
      {new_rendered, new_painted} = render_to_terminal(state)

      {:noreply,
       %{
         state
         | rendered_buffer: new_rendered,
           painted_images: new_painted,
           dirty_regions: [],
           pending_image_clears: [],
           rendering: false
       }}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %__MODULE__{paced_tty: tty}) when tty != nil do
    :file.close(tty)
    :ok
  end

  def terminate(_reason, _state), do: :ok

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

  defp schedule_render(state) do
    if state.rendering do
      {:noreply, state}
    else
      send(self(), :render_frame)
      {:noreply, %{state | rendering: true}}
    end
  end

  defp render_to_terminal(state) do
    {text_rows, changed_lines} = build_terminal_output(state.screen_buffer, state.rendered_buffer)

    {image_rows, new_painted} =
      build_image_output(
        state.image_regions,
        state.painted_images,
        changed_lines,
        state.screen_size
      )

    image_block = Enum.reverse(state.pending_image_clears) ++ image_rows
    output = compose_output(text_rows, image_block)

    if output != [] do
      trace_frame(text_rows, image_rows)
      traced_write(state, output, changed_lines)
    end

    {state.screen_buffer, new_painted}
  end

  defp traced_write(state, output, changed_lines) do
    if Drafter.Trace.enabled?() do
      bytes = IO.iodata_length(output)
      t0 = System.monotonic_time(:microsecond)
      write_output(state, output)
      t1 = System.monotonic_time(:microsecond)

      Drafter.Trace.log([
        "W ",
        Drafter.Trace.ts(),
        " lines=",
        Integer.to_string(length(changed_lines)),
        " bytes=",
        Integer.to_string(bytes),
        " write_us=",
        Integer.to_string(t1 - t0),
        "\n"
      ])
    else
      write_output(state, output)
    end
  end

  defp write_output(%__MODULE__{paced_tty: tty}, output) when tty != nil do
    :file.write(tty, output)
  end

  defp write_output(%__MODULE__{terminal_driver: driver}, output) do
    driver_write(driver, output)
  end

  defp open_paced_tty(Terminal.Driver) do
    if paced_write?() do
      case :file.open(~c"/dev/tty", [:write, :raw, :binary]) do
        {:ok, tty} -> tty
        {:error, _} -> nil
      end
    end
  end

  defp open_paced_tty(_driver), do: nil

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

  defp build_terminal_output(screen_buffer, rendered_buffer) do
    prev_tuple = List.to_tuple(rendered_buffer)
    prev_count = tuple_size(prev_tuple)

    {rows, changed} =
      screen_buffer
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {strip, line_index}, {rows, changed} ->
        prev_strip = if line_index < prev_count, do: elem(prev_tuple, line_index), else: nil

        if prev_strip && prev_strip.cache_key == strip.cache_key do
          {rows, changed}
        else
          {[[Terminal.ANSI.cursor_to(1, line_index + 1), Strip.to_ansi(strip)] | rows],
           [line_index | changed]}
        end
      end)

    {Enum.reverse(rows), changed}
  end

  defp build_image_output(image_regions, painted, changed_lines, screen_size) do
    changed_set = MapSet.new(changed_lines)

    Enum.reduce(image_regions, {[], painted}, fn {id, region}, {rows, painted_acc} ->
      if should_paint?(region, Map.get(painted_acc, id), changed_set, screen_size) do
        paint_region(id, region, rows, painted_acc)
      else
        {rows, painted_acc}
      end
    end)
  end

  defp should_paint?(region, painted, changed_set, screen_size) do
    paintable?(region, screen_size) and
      (needs_paint?(region, painted) or image_overlaps?(region, changed_set))
  end

  defp paint_region(id, region, rows, painted_acc) do
    changed? = needs_paint?(region, Map.get(painted_acc, id))
    trace_paint(id, if(changed?, do: "v", else: "o"))

    bytes = if changed?, do: region.bytes, else: Map.get(region, :place) || region.bytes

    cmd = [Terminal.ANSI.cursor_to(region.x + region.dx + 1, region.y + region.dy + 1), bytes]

    {[cmd | rows], Map.put(painted_acc, id, {region.version, {region.x, region.y}})}
  end

  defp paintable?(region, screen_size) do
    region.visible and not is_nil(region.bytes) and on_screen?(region, screen_size)
  end

  defp on_screen?(region, {width, height}) do
    left = region.x + region.dx
    top = region.y + region.dy
    left >= 0 and top >= 0 and left + region.cols <= width and top + region.rows <= height
  end

  defp needs_paint?(_region, nil), do: true

  defp needs_paint?(region, {version, pos}),
    do: region.version != version or {region.x, region.y} != pos

  defp image_overlaps?(region, changed_set) do
    top = region.y + region.dy
    Enum.any?(top..(top + region.rows - 1)//1, &MapSet.member?(changed_set, &1))
  end

  defp image_rect(region) do
    %{x: region.x + region.dx, y: region.y + region.dy, width: region.cols, height: region.rows}
  end

  defp compose_output([], []), do: []

  defp compose_output(text_rows, image_block) do
    synced_text(text_rows) ++
      image_block ++ [Terminal.ANSI.cursor_to(1, 1), Terminal.ANSI.hide_cursor()]
  end

  defp synced_text([]), do: []

  defp synced_text(text_rows) do
    if System.get_env("DRAFTER_NO_SYNC") in [nil, ""] do
      [Terminal.ANSI.sync_start()] ++ text_rows ++ [Terminal.ANSI.sync_end()]
    else
      text_rows
    end
  end

  defp images_pending?(state) do
    Enum.any?(state.image_regions, fn {id, region} ->
      paintable?(region, state.screen_size) and
        needs_paint?(region, Map.get(state.painted_images, id))
    end)
  end

  defp stale_stamp?(stamps, id, stamp) do
    case Map.get(stamps, id) do
      nil -> false
      last -> stamp <= last
    end
  end

  defp covers?(old, new) do
    is_nil(Map.get(old, :bytes)) or
      (Map.get(old, :x) == new.x and Map.get(old, :y) == new.y and
         Map.get(old, :dx) == new.dx and Map.get(old, :dy) == new.dy and
         Map.get(old, :cols, 0) <= new.cols and Map.get(old, :rows, 0) <= new.rows)
  end

  defp invalidate_region(state, %{bytes: bytes} = region) when not is_nil(bytes) do
    %{
      state
      | dirty_regions: [image_rect(region) | state.dirty_regions],
        rendered_buffer: invalidate_rows(state.rendered_buffer, region.y + region.dy, region.rows)
    }
  end

  defp invalidate_region(state, _region), do: state

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
