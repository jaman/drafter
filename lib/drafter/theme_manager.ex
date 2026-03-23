defmodule Drafter.ThemeManager do
  @moduledoc """
  GenServer that holds the active theme and notifies the running application on change.

  The active theme defaults to `Drafter.Theme.dark_theme/0` on startup. Call
  `set_theme/1` with a theme name string (e.g. `"nord"`) to switch themes at runtime;
  the registered app process receives a `{:theme_updated, theme}` message which
  triggers a re-render. Use `register_app/1` to associate the app loop PID.
  """

  use GenServer

  alias Drafter.Theme

  defstruct [
    current_theme: nil,
    available_themes: [],
    app_pid: nil
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec get_current_theme() :: Drafter.Theme.t()
  def get_current_theme do
    GenServer.call(resolve(), :get_current_theme)
  end

  @spec set_theme(String.t()) :: :ok
  def set_theme(theme_name) do
    GenServer.cast(resolve(), {:set_theme, theme_name})
  end

  @spec register_app(pid()) :: :ok
  def register_app(app_pid) do
    GenServer.cast(resolve(), {:register_app, app_pid})
  end

  @impl GenServer
  def init(_opts) do
    available_themes = Theme.available_themes()
    current_theme = Theme.dark_theme()

    state = %__MODULE__{
      current_theme: current_theme,
      available_themes: available_themes,
      app_pid: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_current_theme, _from, state) do
    {:reply, state.current_theme, state}
  end

  @impl GenServer
  def handle_cast({:set_theme, theme_name}, state) do
    case Theme.get_theme(theme_name) do
      nil ->
        {:noreply, state}

      new_theme ->
        new_state = %{state | current_theme: new_theme}

        if state.app_pid do
          send(state.app_pid, {:theme_updated, new_theme})
        end

        {:noreply, new_state}
    end
  end

  def handle_cast({:register_app, app_pid}, state) do
    {:noreply, %{state | app_pid: app_pid}}
  end

  defp resolve do
    Process.get(:drafter_theme_manager) ||
      raise "No ThemeManager in process dictionary. Ensure a Drafter session is running."
  end
end
