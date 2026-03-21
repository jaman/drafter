defmodule Drafter.Widget.Registry do
  @moduledoc false

  @on_load :init

  def init do
    scan_and_register()
    :ok
  end

  @doc """
  Registers a single widget module or an entire widget library.

  Accepts either a widget module (one that defines `component_tag/0`)
  or a library module (one that implements `Drafter.WidgetLibrary`).
  """
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

  def lookup(tag) when is_atom(tag) do
    :persistent_term.get({__MODULE__, tag}, nil)
  end

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
