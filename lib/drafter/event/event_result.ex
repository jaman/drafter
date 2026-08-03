defmodule Drafter.EventResult do
  @moduledoc """
  Normalises what a widget's `handle_event/2` returned into the triple the router uses.

  `parse/2` maps every accepted return shape onto `{new_state, actions, mode}`, or
  the bare atom `:not_handled`. The modes are:

    * `:stop` — handled; the event does not travel to the parent
    * `:bubble` — handled, and the event still travels to the parent
    * `:not_handled` — the widget did not act on the event

  ## Examples

      iex> Drafter.EventResult.parse({:ok, %{count: 1}}, %{count: 0})
      {%{count: 1}, [], :stop}

  """

  @type mode :: :stop | :bubble | :not_handled
  @type t :: {term(), list(), mode()} | :not_handled

  @doc """
  Normalise a widget handler's return value.

  Accepted shapes, where `state` is the widget's new state and `actions` a list:

    * `{:ok, state, actions}` and `{:ok, state}` → `:stop`
    * `{:bubble, state, actions}` and `{:bubble, state}` → `:bubble`
    * `{:noreply, _}` → `:not_handled`
    * a bare action `{:pop, _}`, `{:push, _, _}`, `{:replace, _, _}` or
      `{:app_callback, _, _}` → `{fallback, [action], :stop}`

  `fallback` is the state to keep when the handler returned an action instead of a
  state — normally the state the widget had before the call. Anything else returns
  `:not_handled` and `fallback` is unused.

  ## Examples

      iex> Drafter.EventResult.parse({:ok, :new, [:act]}, :old)
      {:new, [:act], :stop}

      iex> Drafter.EventResult.parse({:ok, :new}, :old)
      {:new, [], :stop}

      iex> Drafter.EventResult.parse({:bubble, :new}, :old)
      {:new, [], :bubble}

      iex> Drafter.EventResult.parse({:noreply, :new}, :old)
      :not_handled

      iex> Drafter.EventResult.parse({:pop, :result}, :old)
      {:old, [{:pop, :result}], :stop}

      iex> Drafter.EventResult.parse({:app_callback, :saved, 1}, :old)
      {:old, [{:app_callback, :saved, 1}], :stop}

      iex> Drafter.EventResult.parse(:something_else, :old)
      :not_handled

  """
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
