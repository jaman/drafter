defmodule Drafter.SkinManager do
  @moduledoc """
  GenServer that holds the active rendering skin and notifies the running
  application on change.

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

  @persistent_term_key {__MODULE__, :current_skin}
  @default_skin :graphical

  defstruct current_skin: @default_skin, app_pid: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Returns the currently active skin atom."
  @spec get_current_skin() :: atom()
  def get_current_skin do
    :persistent_term.get(@persistent_term_key, @default_skin)
  end

  @doc "Switches the active skin. Triggers a re-render on the registered app."
  @spec set_skin(atom()) :: :ok
  def set_skin(skin) when is_atom(skin) do
    GenServer.cast(resolve(), {:set_skin, skin})
  end

  @doc "Returns the list of registered skin names."
  @spec available_skins() :: [atom()]
  def available_skins, do: CharacterSet.skins()

  @doc "Registers the app loop PID to receive `{:skin_updated, skin}` messages."
  @spec register_app(pid()) :: :ok
  def register_app(app_pid) do
    GenServer.cast(resolve(), {:register_app, app_pid})
  end

  @impl GenServer
  def init(_opts) do
    :persistent_term.put(@persistent_term_key, @default_skin)
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:get_current_skin, _from, state) do
    {:reply, state.current_skin, state}
  end

  @impl GenServer
  def handle_cast({:set_skin, skin}, state) do
    if skin in CharacterSet.skins() do
      :persistent_term.put(@persistent_term_key, skin)
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

  defp resolve, do: Process.get(:drafter_skin_manager, __MODULE__)
end
