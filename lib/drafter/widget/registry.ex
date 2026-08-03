defmodule Drafter.Widget.Registry do
  @moduledoc false

  @on_load :init

  @doc "Runs `scan_and_register/0` when this module loads. Returns `:ok`."
  @spec init() :: :ok
  def init do
    scan_and_register()
    :ok
  end

  @doc """
  Registers a widget module or a whole widget library under its component tag.

  `module` is either a library module exporting `__widget_library__/0` — every widget
  it lists is registered — or a widget module exporting `component_tag/0`. Any other
  atom is ignored. Returns `:ok`.

  This is what `Drafter.run/2` calls for each entry in its `:widget_libraries`
  option.
  """
  @spec register(module()) :: :ok
  def register(module) when is_atom(module) do
    cond do
      function_exported?(module, :__widget_library__, 0) ->
        Enum.each(module.__widget_library__(), &register_widget/1)

      function_exported?(module, :component_tag, 0) ->
        register_widget(module)

      true ->
        :ok
    end
  end

  defp register_widget(module) do
    tag = module.component_tag()
    :persistent_term.put({__MODULE__, tag}, module)
  end

  @doc """
  The widget module registered for the component tag `tag`, or `nil`.

  `tag` is the atom a widget returns from `component_tag/0` — the first element of a
  tag element tuple such as `{:label, "hi", []}`.

      iex> Drafter.Widget.Registry.lookup(:progress_bar)
      Drafter.Widget.ProgressBar

      iex> Drafter.Widget.Registry.lookup(:no_such_widget)
      nil
  """
  @spec lookup(atom()) :: module() | nil
  def lookup(tag) when is_atom(tag) do
    :persistent_term.get({__MODULE__, tag}, nil)
  end

  @doc """
  Registers every module in `:drafter` and its dependent applications that exports
  `component_tag/0`. Returns `:ok`.

  Runs on module load and again from `Drafter.run/2`. Modules from an application not
  listed in `:drafter`'s `:applications` are not found this way and need an explicit
  `register/1`.
  """
  @spec scan_and_register() :: :ok
  def scan_and_register do
    for app <- [:drafter | Application.spec(:drafter, :applications) || []] do
      Application.spec(app, :modules) || []
    end
    |> List.flatten()
    |> Enum.each(fn mod ->
      Code.ensure_loaded(mod)

      if function_exported?(mod, :component_tag, 0) do
        register_widget(mod)
      end
    end)
  end
end
