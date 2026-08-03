defmodule Drafter.CellSession do
  @moduledoc """
  Drives a Drafter app to an in-memory cell grid instead of a terminal.

  A `CellSession` runs the ordinary app loop against a terminal driver that
  discards its output, and exposes the composited screen as rows of cells —
  `Drafter.Draw.Strip` structs, one per screen row — together with row-level
  diffs. A host renders those rows however it likes and feeds input back in with
  `feed_input/2`.

      session = Drafter.CellSession.start(MyApp, size: {80, 24})
      rows = Drafter.CellSession.take_cells(session)            # full grid
      Drafter.CellSession.feed_input(session, {:key, :enter})   # drive input
      {changed, session} = Drafter.CellSession.take_cells_diff(session)  # only changed rows
      Drafter.CellSession.resize(session, 100, 30)
      Drafter.CellSession.close(session)

  Each session owns its own unnamed services, so many sessions run concurrently in one
  BEAM node without colliding.
  """

  alias Drafter.AppRegistry
  alias Drafter.CellSession.Driver
  alias Drafter.{Compositor, Event, EventHandler, ScreenManager, ThemeManager}
  alias Drafter.Draw.Strip
  alias Drafter.Runtime
  alias Drafter.Runtime.{AppLoop, Renderer, Shared}
  alias Drafter.Session.SharedState

  @enforce_keys [:app_pid, :compositor, :event_manager, :services, :driver, :snapshot]
  defstruct [:app_pid, :compositor, :event_manager, :services, :driver, :snapshot]

  @type t :: %__MODULE__{}
  @type cell_row :: {non_neg_integer(), Strip.t()}

  @doc """
  Start a cell-backed session for `app_module`.

  Options:

    * `:size` — `{columns, rows}` of the virtual surface, default `{80, 24}`
    * `:shared` — a shared-state server pid to join an existing
      multi-user session; omit for a session with private state

  Every other option is passed to the app's `mount/1` as a mount prop.

  Returns the session struct, which the other functions in this module take. The
  caller must call `close/1` to release the processes the session owns.
  """
  @spec start(module(), keyword()) :: t()
  def start(app_module, opts \\ []) do
    {width, height} = Keyword.get(opts, :size, {80, 24})
    shared = Keyword.get(opts, :shared)
    props = opts |> Keyword.drop([:size, :shared]) |> Map.new()

    {:ok, driver} = Driver.start_link({width, height})
    {:ok, em} = Event.Manager.start_link(name: nil)

    {:ok, comp} =
      Compositor.start_link(name: nil, terminal_driver: {Driver, driver}, event_manager: em)

    {:ok, tm} = ThemeManager.start_link(name: nil)
    {:ok, eh} = EventHandler.start_link(name: nil)
    {:ok, sm} = ScreenManager.start_link(name: nil, event_handler: eh)

    services = %{
      drafter_event_manager: em,
      drafter_compositor: comp,
      drafter_theme_manager: tm,
      drafter_screen_manager: sm,
      drafter_event_handler: eh
    }

    {:ok, snapshot} = Agent.start_link(fn -> [] end)
    app_pid = spawn_link(fn -> run(app_module, props, services, shared) end)
    Event.Manager.subscribe_to(em, app_pid)

    %__MODULE__{
      app_pid: app_pid,
      compositor: comp,
      event_manager: em,
      services: services,
      driver: driver,
      snapshot: snapshot
    }
  end

  @doc "Return the full current cell grid: one `Strip` per row."
  @spec take_cells(t()) :: [Strip.t()]
  def take_cells(%__MODULE__{compositor: comp}), do: Compositor.get_buffer(comp)

  @doc """
  Return the current screen as plain text, one string per row.

  Styling is dropped and trailing blanks are trimmed, so a row is its content and
  an empty row is `""`. The list is always as long as the surface is tall.

      ["hello world", "second line", "", "", "", ""]

  This is the same view `Drafter.Test.screen_lines/1` gives of a headless app, for
  asserting on what is displayed rather than rendering it.
  """
  @spec take_lines(t()) :: [String.t()]
  def take_lines(%__MODULE__{} = session) do
    session
    |> take_cells()
    |> Enum.map(&String.trim_trailing(Strip.to_plain_text(&1)))
  end

  @doc """
  Return the current screen as one string, rows joined by newlines.

  As `take_lines/1`, which documents the per-row form.
  """
  @spec take_text(t()) :: String.t()
  def take_text(%__MODULE__{} = session) do
    session |> take_lines() |> Enum.join("\n")
  end

  @doc """
  Return the rows that changed since the previous diff (or first call) as
  `{row_index, strip}` tuples, and an updated session tracking the new snapshot.
  """
  @spec take_cells_diff(t()) :: {[cell_row()], t()}
  def take_cells_diff(%__MODULE__{compositor: comp, snapshot: snapshot} = session) do
    current = Compositor.get_buffer(comp)
    previous = Agent.get(snapshot, & &1)
    Agent.update(snapshot, fn _ -> current end)
    {diff_rows(current, previous), session}
  end

  @doc "Inject an input event (e.g. `{:key, :enter}`, `{:mouse, %{...}}`) into the session."
  @spec feed_input(t(), term()) :: :ok
  def feed_input(%__MODULE__{event_manager: em}, event) do
    GenServer.cast(em, {:event, event})
    :ok
  end

  @doc "Resize the virtual surface; the app re-renders to the new dimensions."
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok
  def resize(%__MODULE__{driver: driver, event_manager: em}, width, height) do
    Driver.set_size(driver, {width, height})
    GenServer.cast(em, {:event, {:resize, {width, height}}})
    :ok
  end

  @doc "Shut down the session and all of its services."
  @spec close(t()) :: :ok
  def close(%__MODULE__{app_pid: app_pid, services: services, driver: driver, snapshot: snapshot}) do
    if Process.alive?(app_pid), do: send(app_pid, :shutdown)
    Enum.each(services, fn {_k, pid} -> stop(pid) end)
    stop(driver)
    stop(snapshot)
    :ok
  end

  defp run(app_module, props, services, shared) do
    Enum.each(services, fn {key, pid} -> Process.put(key, pid) end)
    AppRegistry.register()
    ThemeManager.register_app(self())
    ScreenManager.register_app(self())
    if shared, do: join_shared(shared, props)

    backend = Runtime.for_app(app_module)
    app_state = backend.mount(app_module, props)
    {width, height} = Compositor.get_screen_size()
    screen_rect = %{x: 0, y: 0, width: width, height: height}

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)
    ready_state = backend.ready(app_module, app_state)
    {_, hierarchy} = Renderer.render_app(app_module, ready_state, screen_rect, hierarchy)

    AppLoop.enter_loop(app_module, ready_state, screen_rect, %{}, hierarchy, [])
  end

  defp join_shared(shared_state_pid, props) do
    SharedState.subscribe(shared_state_pid)
    Process.put(:drafter_shared_state, shared_state_pid)
    Process.put(:drafter_mount_props, props)
    Process.put(:drafter_runtime_override, Shared)
  end

  defp diff_rows(current, previous) do
    current
    |> Enum.with_index()
    |> Enum.filter(fn {strip, index} ->
      case Enum.at(previous, index) do
        %Strip{cache_key: key} -> key != strip.cache_key
        _ -> true
      end
    end)
    |> Enum.map(fn {strip, index} -> {index, strip} end)
  end

  defp stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
  catch
    :exit, _ -> :ok
  end
end
