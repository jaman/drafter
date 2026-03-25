defmodule Drafter.Widget.Trait.Focusable do
  @moduledoc """
  Trait that makes a widget focusable.

  Manages the `focused` state field and handles focus/blur events.
  Widgets with this trait participate in tab cycling and arrow-key navigation.
  """

  @behaviour Drafter.Widget.Trait

  defstruct tab_index: nil, __spark_metadata__: nil

  @impl true
  def name, do: :focusable

  @impl true
  def default_state, do: %{focused: false}

  @impl true
  def dependencies, do: []

  @impl true
  def handles, do: [:focus, :blur]

  @impl true
  def render_affecting_fields, do: [:focused]

  @impl true
  def layout_static?, do: true

  @impl true
  def handle_event({:focus}, _trait_state, _widget_state) do
    {:ok, %{focused: true}}
  end

  def handle_event({:blur}, _trait_state, _widget_state) do
    {:ok, %{focused: false}}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
