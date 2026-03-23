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
    rendering: false
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

  @spec get_screen_size() :: {pos_integer(), pos_integer()}
  def get_screen_size do
    GenServer.call(resolve(), :get_screen_size)
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
    if Enum.empty?(state.dirty_regions) do
      {:noreply, %{state | rendering: false}}
    else
      new_rendered = render_to_terminal(state)
      {:noreply, %{state | rendered_buffer: new_rendered, dirty_regions: [], rendering: false}}
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
    output = build_terminal_output(state.screen_buffer, state.rendered_buffer)
    driver_write(state.terminal_driver, output)
    state.screen_buffer
  end

  defp build_terminal_output(screen_buffer, rendered_buffer) do
    rows =
      screen_buffer
      |> Enum.with_index()
      |> Enum.flat_map(fn {strip, line_index} ->
        prev_strip = Enum.at(rendered_buffer, line_index)

        if prev_strip && prev_strip.cache_key == strip.cache_key do
          []
        else
          [Terminal.ANSI.cursor_to(1, line_index + 1), Strip.to_ansi(strip)]
        end
      end)

    case rows do
      [] -> []
      _ -> [Terminal.ANSI.sync_start()] ++ rows ++ [Terminal.ANSI.sync_end()]
    end
  end
end
