defmodule Drafter.Widget.Registry do
  @moduledoc false

  @on_load :init

  def init do
    scan_and_register()
    :ok
  end

  def register(module) when is_atom(module) do
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
        register(mod)
      end
    end)
  end
end
