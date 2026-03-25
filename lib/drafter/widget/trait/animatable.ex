defmodule Drafter.Widget.Trait.Animatable do
  @moduledoc """
  Trait that provides render timestamp for animation frames.

  A passive trait that injects `_render_timestamp` into widget state.
  The framework updates this value on each render cycle.
  """

  @behaviour Drafter.Widget.Trait

  defstruct __spark_metadata__: nil

  @impl true
  def name, do: :animatable

  @impl true
  def default_state do
    %{_render_timestamp: 0}
  end

  @impl true
  def dependencies, do: []

  @impl true
  def handles, do: []

  @impl true
  def render_affecting_fields, do: [:_render_timestamp]

  @impl true
  def layout_static?, do: true
end
