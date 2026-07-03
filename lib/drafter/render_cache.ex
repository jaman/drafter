defmodule Drafter.RenderCache do
  @moduledoc """
  Process-dictionary cache for incremental rendering.

  Tracks per-widget strip fingerprints and the last composited output
  so the renderer can skip recompositing rows where nothing changed.
  """

  @composited_key :render_cache_composited
  @widget_rowkeys_key :render_cache_widget_rowkeys
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

  @spec get_widget_rowkeys(term()) :: [term()] | nil
  def get_widget_rowkeys(widget_id) do
    case Process.get(@widget_rowkeys_key) do
      nil -> nil
      map -> Map.get(map, widget_id)
    end
  end

  @spec put_widget_rowkeys(term(), [term()]) :: :ok
  def put_widget_rowkeys(widget_id, row_keys) do
    map = Process.get(@widget_rowkeys_key, %{})
    Process.put(@widget_rowkeys_key, Map.put(map, widget_id, row_keys))
    :ok
  end

  @doc """
  Absolute screen rows that changed between two per-row cache-key lists.

  `bounds_y` offsets the row index to a screen row. A `nil` previous list
  (the widget's first frame) marks every row dirty.
  """
  @spec changed_rows([term()] | nil, [term()], non_neg_integer()) :: MapSet.t(non_neg_integer())
  def changed_rows(nil, curr_keys, bounds_y) do
    Enum.into(0..(length(curr_keys) - 1)//1, MapSet.new(), &(&1 + bounds_y))
  end

  def changed_rows(prev_keys, curr_keys, bounds_y) do
    prev = List.to_tuple(prev_keys)
    prev_count = tuple_size(prev)

    curr_keys
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {key, index}, acc ->
      same? = index < prev_count and elem(prev, index) == key
      if same?, do: acc, else: MapSet.put(acc, index + bounds_y)
    end)
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
    Process.delete(@widget_rowkeys_key)
    Process.delete(@widget_bounds_key)
    Process.delete(@app_state_hash_key)
    Process.delete(@layer_count_key)
    :ok
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
