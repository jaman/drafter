defmodule Drafter.Compositor do
  @moduledoc false

  use GenServer

  alias Drafter.Draw.Strip
  alias Drafter.{Event, Terminal}

  defstruct [
    :terminal_driver,
    :event_manager,
    screen_buffer: [],
    rendered_buffer: [],
    dirty_regions: [],
    screen_size: {80, 24},
    rendering: false,
    image_regions: %{},
    painted_images: %{},
    pending_image_clears: []
  ]

  @type screen_buffer :: [Strip.t()]
  @type dirty_region :: %{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec render_strips([Strip.t()], non_neg_integer(), non_neg_integer()) :: :ok
  def render_strips(strips, x \\ 0, y \\ 0) do
    GenServer.cast(resolve(), {:render_strips, strips, x, y})
  end

  @spec clear_screen() :: :ok
  def clear_screen do
    GenServer.cast(resolve(), :clear_screen)
  end

  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(resolve(), :refresh)
  end

  @doc """
  Store the terminal-graphics bytes (kitty/iTerm2/sixel) for an image region.

  Called once per generation (from the widget's async render task) — the bytes never
  travel through the render loop. `paint` draws the image, `clear` removes it (a kitty
  delete for the persistent-layer protocol; empty for cell-grid protocols that re-blank).
  `dx`/`dy` offset the image within the placed cell, and `cols`/`rows` are its cell size.
  Paint happens via `place_image/3`.
  """
  @spec put_image(term(), iodata(), iodata(), integer(), integer(), pos_integer(), pos_integer()) ::
          :ok
  def put_image(id, paint, clear, dx, dy, cols, rows) do
    GenServer.cast(resolve(), {:put_image, id, paint, clear, dx, dy, cols, rows})
  end

  @doc """
  Position an image region at a cell and mark it visible — a cheap, byte-free per-frame
  update from the render loop. The image is (re)painted after the text frame only when
  its bytes or position changed, or a text row under it was redrawn.
  """
  @spec place_image(term(), non_neg_integer(), non_neg_integer()) :: :ok
  def place_image(id, x, y) do
    GenServer.cast(resolve(), {:place_image, id, x, y})
  end

  @doc "Hide an image region and re-blank the cells it occupied."
  @spec clear_image(term()) :: :ok
  def clear_image(id) do
    GenServer.cast(resolve(), {:clear_image, id})
  end

  @spec get_screen_size() :: {pos_integer(), pos_integer()}
  def get_screen_size do
    GenServer.call(resolve(), :get_screen_size)
  end

  @doc "Returns the current composited screen buffer (one `Strip` per row) for the given compositor."
  @spec get_buffer(pid()) :: [Drafter.Draw.Strip.t()]
  def get_buffer(pid) do
    GenServer.call(pid, :get_buffer)
  end

  @impl GenServer
  def init(opts) do
    terminal_driver = Keyword.get(opts, :terminal_driver, Terminal.Driver)
    event_manager = Keyword.get(opts, :event_manager, Event.Manager)

    Event.Manager.subscribe_to(event_manager, self(), &resize_event?/1)

    {width, height} = driver_get_size(terminal_driver)

    empty_buffer = create_empty_buffer(width, height)

    state = %__MODULE__{
      terminal_driver: terminal_driver,
      event_manager: event_manager,
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
    new_state = %{state | screen_buffer: empty_buffer, rendered_buffer: []}
    schedule_render(new_state)
  end

  def handle_cast(:refresh, state) do
    {width, height} = state.screen_size
    dirty_region = %{x: 0, y: 0, width: width, height: height}
    new_state = %{state | rendered_buffer: [], dirty_regions: [dirty_region]}
    schedule_render(new_state)
  end

  def handle_cast({:put_image, id, paint, clear, dx, dy, cols, rows}, state) do
    base = Map.get(state.image_regions, id, %{x: 0, y: 0, visible: false, version: 0, clear: ""})

    region =
      Map.merge(base, %{
        bytes: paint,
        clear: clear,
        dx: dx,
        dy: dy,
        cols: cols,
        rows: rows,
        version: base.version + 1
      })

    schedule_render(%{state | image_regions: Map.put(state.image_regions, id, region)})
  end

  def handle_cast({:place_image, id, x, y}, state) do
    case Map.get(state.image_regions, id) do
      %{x: ^x, y: ^y, visible: true} ->
        {:noreply, state}

      nil ->
        region = %{bytes: nil, clear: "", dx: 0, dy: 0, cols: 0, rows: 0, x: x, y: y, visible: true, version: 0}
        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, region)})

      region ->
        schedule_render(%{state | image_regions: Map.put(state.image_regions, id, %{region | x: x, y: y, visible: true})})
    end
  end

  def handle_cast({:clear_image, id}, state) do
    case Map.get(state.image_regions, id) do
      %{visible: true, bytes: bytes} = region when not is_nil(bytes) ->
        hidden = %{region | visible: false}

        schedule_render(%{
          state
          | image_regions: Map.put(state.image_regions, id, hidden),
            painted_images: Map.delete(state.painted_images, id),
            pending_image_clears: [region.clear | state.pending_image_clears],
            dirty_regions: [image_rect(region) | state.dirty_regions],
            rendered_buffer: invalidate_rows(state.rendered_buffer, region.y + region.dy, region.rows)
        })

      %{} = region ->
        {:noreply, %{state | image_regions: Map.put(state.image_regions, id, %{region | visible: false})}}

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:tui_event, {:resize, {width, height}}}, state) do
    new_buffer = create_empty_buffer(width, height)

    new_state = %{
      state
      | screen_size: {width, height},
        screen_buffer: new_buffer,
        rendered_buffer: [],
        dirty_regions: [%{x: 0, y: 0, width: width, height: height}]
    }

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

  defp resize_event?({:resize, _}), do: true
  defp resize_event?(_), do: false

  defp resolve do
    Process.get(:drafter_compositor) ||
      raise "No Compositor in process dictionary. Ensure a Drafter session is running."
  end

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
      build_image_output(state.image_regions, state.painted_images, changed_lines, state.screen_size)

    output = wrap_output(Enum.reverse(state.pending_image_clears) ++ text_rows ++ image_rows)
    if output != [], do: driver_write(state.terminal_driver, output)
    {state.screen_buffer, new_painted}
  end

  defp build_terminal_output(screen_buffer, rendered_buffer) do
    {rows, changed} =
      screen_buffer
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {strip, line_index}, {rows, changed} ->
        prev_strip = Enum.at(rendered_buffer, line_index)

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
      if paintable?(region, screen_size) and
           (needs_paint?(region, Map.get(painted_acc, id)) or image_overlaps?(region, changed_set)) do
        cmd = [Terminal.ANSI.cursor_to(region.x + region.dx + 1, region.y + region.dy + 1), region.bytes]
        {[cmd | rows], Map.put(painted_acc, id, {region.version, {region.x, region.y}})}
      else
        {rows, painted_acc}
      end
    end)
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
  defp needs_paint?(region, {version, pos}), do: region.version != version or {region.x, region.y} != pos

  defp image_overlaps?(region, changed_set) do
    top = region.y + region.dy
    Enum.any?(top..(top + region.rows - 1)//1, &MapSet.member?(changed_set, &1))
  end

  defp image_rect(region) do
    %{x: region.x + region.dx, y: region.y + region.dy, width: region.cols, height: region.rows}
  end

  defp wrap_output([]), do: []

  defp wrap_output(body) do
    [Terminal.ANSI.sync_start()] ++
      body ++
      [
        Terminal.ANSI.cursor_to(1, 1),
        Terminal.ANSI.hide_cursor(),
        Terminal.ANSI.sync_end()
      ]
  end

  defp images_pending?(state) do
    Enum.any?(state.image_regions, fn {id, region} ->
      paintable?(region, state.screen_size) and
        needs_paint?(region, Map.get(state.painted_images, id))
    end)
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
