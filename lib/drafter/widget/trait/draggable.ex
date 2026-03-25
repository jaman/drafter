defmodule Drafter.Widget.Trait.Draggable do
  @moduledoc """
  Trait that adds drag-and-drop capability.

  Manages drag state and position offsets.
  """

  @behaviour Drafter.Widget.Trait

  defstruct __spark_metadata__: nil

  @impl true
  def name, do: :draggable

  @impl true
  def default_state do
    %{
      _drag_active: false,
      _drag_offset_x: 0,
      _drag_offset_y: 0,
      _drag_start_x: 0,
      _drag_start_y: 0
    }
  end

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:press, :drag, :mouse_up]

  @impl true
  def render_affecting_fields, do: [:_drag_active]

  @impl true
  def layout_static?, do: false

  @impl true
  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
