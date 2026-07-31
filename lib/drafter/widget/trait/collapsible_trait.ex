defmodule Drafter.Widget.Trait.Collapsible do
  @moduledoc """
  Trait that adds expand/collapse capability.

  Manages expanded state and handles toggle events.
  Modifies the widget rect in pre_render to show only the header when collapsed.
  """

  @behaviour Drafter.Widget.Trait

  defstruct initially_expanded: false, __spark_metadata__: nil

  @impl true
  def name, do: :collapsible

  @impl true
  def default_state do
    %{
      _expanded: false,
      _on_toggle: nil
    }
  end

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:keyboard, :click]

  @impl true
  def render_affecting_fields, do: [:_expanded]

  @impl true
  def layout_static?, do: false

  @impl true
  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:enter, :" "] do
    {:ok, %{trait_state | _expanded: !trait_state._expanded}}
  end

  def handle_event({:mouse, %{type: :mouse_up, y: 0}}, trait_state, _widget_state) do
    {:ok, %{trait_state | _expanded: !trait_state._expanded}}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end

  @impl true
  def pre_render(trait_state, _widget_state, rect) do
    adjusted_rect =
      if trait_state._expanded do
        rect
      else
        %{rect | height: 1}
      end

    {trait_state, adjusted_rect}
  end
end
