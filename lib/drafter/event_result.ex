defmodule Drafter.EventResult do
  @moduledoc """
  Normalises the tagged-tuple return values from widget event handlers into a
  consistent three-element result used by the event routing pipeline.

  Return value: `{new_state, actions, mode}` where mode is:
  - `:stop`    — event was handled; do not propagate further
  - `:bubble`  — event was handled but should continue bubbling to parent
  - `:not_handled` — widget did not handle the event
  """

  @type mode :: :stop | :bubble | :not_handled
  @type t :: {term(), list(), mode()} | :not_handled

  @spec parse(term(), term()) :: t()
  def parse({:ok, new_state, actions}, _fallback), do: {new_state, actions, :stop}
  def parse({:ok, new_state}, _fallback), do: {new_state, [], :stop}
  def parse({:noreply, _}, _fallback), do: :not_handled
  def parse({:bubble, new_state, actions}, _fallback), do: {new_state, actions, :bubble}
  def parse({:bubble, new_state}, _fallback), do: {new_state, [], :bubble}
  def parse({:pop, _} = action, fallback), do: {fallback, [action], :stop}
  def parse({:push, _, _} = action, fallback), do: {fallback, [action], :stop}
  def parse({:replace, _, _} = action, fallback), do: {fallback, [action], :stop}
  def parse({:app_callback, _, _} = action, fallback), do: {fallback, [action], :stop}
  def parse(_, _fallback), do: :not_handled
end
