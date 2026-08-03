defmodule Drafter.SkinManager do
  @moduledoc """
  Per-session GenServer that holds the active rendering skin and notifies the
  running application on change.

  The skin controls which character set `Drafter.CharacterSet` returns for every
  widget lookup. Three built-in skins are available:

  | Skin | Description |
  |------|-------------|
  | `:graphical` | Unicode block + braille characters (default) |
  | `:wireframe` | Unicode box-drawing, block fill, minimal decoration |
  | `:ascii` | 7-bit ASCII only — maximum compatibility |

  Switching skins at runtime causes all widgets to re-render using the new
  character set on the next frame.

  ## Usage

      Drafter.set_skin(:wireframe)
      Drafter.set_skin(:ascii)
      Drafter.set_skin(:graphical)

      Drafter.SkinManager.get_current_skin()
      Drafter.SkinManager.available_skins()
  """

  use GenServer

  alias Drafter.CharacterSet

  @default_skin :graphical

  defstruct current_skin: @default_skin, app_pid: nil

  @doc """
  Start a skin manager.

  ## Options

    * `:name` - registered name. Default: `nil`, which starts it unnamed. Note this
      differs from `Drafter.ThemeManager.start_link/1`, which defaults to its own
      module name.

  Any other options are accepted and ignored; the starting skin is always
  `:graphical`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, nil)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  The active skin atom.

  Reads the calling process's own `:drafter_skin` first, then asks its session's skin
  manager, and finally falls back to `:graphical` when neither is set. Never raises,
  unlike `set_skin/1` and `register_app/1`.
  """
  @spec get_current_skin() :: atom()
  def get_current_skin do
    case Process.get(:drafter_skin) do
      nil ->
        case Process.get(:drafter_skin_manager) do
          nil -> @default_skin
          pid -> GenServer.call(pid, :get_current_skin)
        end

      skin ->
        skin
    end
  end

  @doc """
  Switch the active skin, sending `{:skin_updated, skin}` to the registered app.

  Asynchronous. Any atom is accepted, including one `available_skins/0` does not
  list; character lookups then fall back to the built-in defaults. Resolved through
  `Drafter.Session.Context`, so it raises when no skin manager is reachable.
  """
  @spec set_skin(atom()) :: :ok
  def set_skin(skin) when is_atom(skin) do
    GenServer.cast(resolve(), {:set_skin, skin})
  end

  @doc "Returns the list of registered skin names."
  @spec available_skins() :: [atom()]
  def available_skins, do: CharacterSet.skins()

  @doc """
  Register the app loop process to receive `{:skin_updated, skin}` messages.

  Only one process is registered at a time; registering again replaces the previous
  one. Asynchronous.
  """
  @spec register_app(pid()) :: :ok
  def register_app(app_pid) do
    GenServer.cast(resolve(), {:register_app, app_pid})
  end

  @impl GenServer
  def init(_opts) do
    Process.put(:drafter_skin, @default_skin)
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:get_current_skin, _from, state) do
    {:reply, state.current_skin, state}
  end

  @impl GenServer
  def handle_cast({:set_skin, skin}, state) do
    if skin in CharacterSet.skins() do
      new_state = %{state | current_skin: skin}

      if state.app_pid do
        send(state.app_pid, {:skin_updated, skin})
      end

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:register_app, app_pid}, state) do
    {:noreply, %{state | app_pid: app_pid}}
  end

  defp resolve, do: Process.get(:drafter_skin_manager, self())
end
