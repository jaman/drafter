defmodule Drafter.Widget.Trait.Resizable do
  @moduledoc """
  Trait that adds resize capability via drag handles.

  Manages resize state and handles drag events on widget edges.
  """

  @behaviour Drafter.Widget.Trait

  defstruct edges: [:right, :bottom], min_width: 1, min_height: 1, __spark_metadata__: nil

  @impl true
  def name, do: :resizable

  @impl true
  def default_state do
    %{
      _resizable: true,
      _min_width: 1,
      _min_height: 1,
      _max_width: nil,
      _max_height: nil,
      _resize_dragging: false,
      _resize_edge: nil
    }
  end

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:drag, :press, :mouse_up, :hover]

  @impl true
  def render_affecting_fields, do: [:_resize_dragging, :_resize_edge]

  @impl true
  def layout_static?, do: false

  @impl true
  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
