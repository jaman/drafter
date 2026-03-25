defmodule Drafter.Widget.DirtyTracker do
  @moduledoc """
  Tracks widget state changes to skip unnecessary re-renders.

  Uses render-affecting fields declared by traits to determine
  whether a widget's visual output has changed since the last render.
  """

  @spec render_needed?(term(), map(), module()) :: boolean()
  def render_needed?(widget_id, current_state, module) do
    affecting_fields = get_affecting_fields(module)
    current_hash = state_hash(current_state, affecting_fields)

    case Process.get({:render_hash, widget_id}) do
      ^current_hash ->
        false

      _ ->
        Process.put({:render_hash, widget_id}, current_hash)
        true
    end
  end

  @spec state_hash(map(), [atom()]) :: non_neg_integer()
  def state_hash(state, fields) do
    fields
    |> Enum.map(&Map.get(state, &1))
    |> :erlang.phash2()
  end

  @spec invalidate(term()) :: :ok
  def invalidate(widget_id) do
    Process.delete({:render_hash, widget_id})
    :ok
  end

  defp get_affecting_fields(module) do
    if function_exported?(module, :__render_affecting_fields__, 0) do
      module.__render_affecting_fields__()
    else
      :all
    end
  end
end
