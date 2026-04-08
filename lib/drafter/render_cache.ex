defmodule Drafter.RenderCache do
  @moduledoc """
  Process-dictionary cache for incremental rendering.

  Tracks per-widget strip fingerprints and the last composited output
  so the renderer can skip recompositing rows where nothing changed.
  """

  @composited_key :render_cache_composited
  @widget_fingerprints_key :render_cache_widget_fps
  @widget_bounds_key :render_cache_widget_bounds
  @app_state_hash_key :render_cache_app_state_hash
  @layer_count_key :render_cache_layer_count

  @spec get_composited() :: [Drafter.Draw.Strip.t()] | nil
  def get_composited, do: Process.get(@composited_key)

  @spec put_composited([Drafter.Draw.Strip.t()]) :: :ok
  def put_composited(strips) do
    Process.put(@composited_key, strips)
    :ok
  end

  @spec get_widget_fingerprint(term()) :: non_neg_integer() | nil
  def get_widget_fingerprint(widget_id) do
    case Process.get(@widget_fingerprints_key) do
      nil -> nil
      map -> Map.get(map, widget_id)
    end
  end

  @spec put_widget_fingerprint(term(), non_neg_integer()) :: :ok
  def put_widget_fingerprint(widget_id, fingerprint) do
    fps = Process.get(@widget_fingerprints_key, %{})
    Process.put(@widget_fingerprints_key, Map.put(fps, widget_id, fingerprint))
    :ok
  end

  @spec get_widget_bounds(term()) :: map() | nil
  def get_widget_bounds(widget_id) do
    case Process.get(@widget_bounds_key) do
      nil -> nil
      map -> Map.get(map, widget_id)
    end
  end

  @spec put_widget_bounds(term(), map()) :: :ok
  def put_widget_bounds(widget_id, bounds) do
    bmap = Process.get(@widget_bounds_key, %{})
    Process.put(@widget_bounds_key, Map.put(bmap, widget_id, bounds))
    :ok
  end

  @spec get_all_widget_bounds() :: %{term() => map()}
  def get_all_widget_bounds, do: Process.get(@widget_bounds_key, %{})

  @spec get_app_state_hash() :: non_neg_integer() | nil
  def get_app_state_hash, do: Process.get(@app_state_hash_key)

  @spec put_app_state_hash(non_neg_integer()) :: :ok
  def put_app_state_hash(hash) do
    Process.put(@app_state_hash_key, hash)
    :ok
  end

  @spec get_layer_count() :: non_neg_integer() | nil
  def get_layer_count, do: Process.get(@layer_count_key)

  @spec put_layer_count(non_neg_integer()) :: :ok
  def put_layer_count(count) do
    Process.put(@layer_count_key, count)
    :ok
  end

  @spec invalidate() :: :ok
  def invalidate do
    Process.delete(@composited_key)
    Process.delete(@widget_fingerprints_key)
    Process.delete(@widget_bounds_key)
    Process.delete(@app_state_hash_key)
    Process.delete(@layer_count_key)
    :ok
  end

  @spec compute_dirty_rows([term()]) :: MapSet.t(non_neg_integer())
  def compute_dirty_rows(dirty_widget_ids) do
    all_bounds = get_all_widget_bounds()

    Enum.reduce(dirty_widget_ids, MapSet.new(), fn widget_id, acc ->
      case Map.get(all_bounds, widget_id) do
        nil ->
          acc

        bounds ->
          y_start = bounds.y
          y_end = bounds.y + bounds.height - 1

          Enum.reduce(y_start..y_end//1, acc, &MapSet.put(&2, &1))
      end
    end)
  end

  @spec strips_fingerprint([Drafter.Draw.Strip.t()]) :: non_neg_integer()
  def strips_fingerprint(strips) do
    strips
    |> Enum.map(& &1.cache_key)
    |> :erlang.phash2()
  end

  @spec extract_layout_impact(list()) :: {boolean(), atom()}
  def extract_layout_impact(actions) do
    Enum.reduce(actions, {false, nil}, fn
      {:widget_layout_needed, direction}, {_, _} -> {true, direction}
      :widget_layout_needed, {_, _} -> {true, :all}
      _, acc -> acc
    end)
  end

  @spec compute_directional_dirty_rows(atom(), map(), map()) :: MapSet.t(non_neg_integer())
  def compute_directional_dirty_rows(direction, widget_bounds, screen_rect) do
    case direction do
      :self ->
        rows_from_bounds(widget_bounds)

      :below ->
        y_start = widget_bounds.y
        y_end = screen_rect.height - 1
        range_to_set(y_start, y_end)

      :above ->
        y_end = widget_bounds.y + widget_bounds.height - 1
        range_to_set(0, y_end)

      :left ->
        range_to_set(0, screen_rect.height - 1)

      :right ->
        range_to_set(0, screen_rect.height - 1)

      :parent ->
        range_to_set(0, screen_rect.height - 1)

      _ ->
        range_to_set(0, screen_rect.height - 1)
    end
  end

  defp rows_from_bounds(bounds) do
    y_end = bounds.y + bounds.height - 1
    range_to_set(bounds.y, y_end)
  end

  defp range_to_set(y_start, y_end) when y_start <= y_end do
    Enum.reduce(y_start..y_end//1, MapSet.new(), &MapSet.put(&2, &1))
  end

  defp range_to_set(_, _), do: MapSet.new()
end
