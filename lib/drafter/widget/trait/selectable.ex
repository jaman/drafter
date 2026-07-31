defmodule Drafter.Widget.Trait.Selectable do
  @moduledoc """
  Trait that adds item selection capability.

  Manages cursor position and selected indices. Supports single
  and multiple selection modes.
  """

  @behaviour Drafter.Widget.Trait

  defstruct mode: :single, __spark_metadata__: nil

  @impl true
  def name, do: :selectable

  @impl true
  def default_state do
    %{
      _selection_mode: :single,
      _selected_indices: MapSet.new(),
      _cursor_index: 0,
      _item_count: 0
    }
  end

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:keyboard]

  @impl true
  def render_affecting_fields, do: [:_selected_indices, :_cursor_index]

  @impl true
  def layout_static?, do: true

  @impl true
  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:up, :ArrowUp] do
    new_index = max(0, trait_state._cursor_index - 1)
    {:ok, %{trait_state | _cursor_index: new_index}}
  end

  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:down, :ArrowDown] do
    max_index = max(0, trait_state._item_count - 1)
    new_index = min(max_index, trait_state._cursor_index + 1)
    {:ok, %{trait_state | _cursor_index: new_index}}
  end

  def handle_event({:key, :" "}, trait_state, _widget_state) do
    idx = trait_state._cursor_index

    new_selected =
      case trait_state._selection_mode do
        :none ->
          trait_state._selected_indices

        :single ->
          if MapSet.member?(trait_state._selected_indices, idx) do
            MapSet.new()
          else
            MapSet.new([idx])
          end

        :multiple ->
          if MapSet.member?(trait_state._selected_indices, idx) do
            MapSet.delete(trait_state._selected_indices, idx)
          else
            MapSet.put(trait_state._selected_indices, idx)
          end
      end

    {:ok, %{trait_state | _selected_indices: new_selected}}
  end

  def handle_event({:key, :enter}, trait_state, _widget_state) do
    {:pass, trait_state}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
