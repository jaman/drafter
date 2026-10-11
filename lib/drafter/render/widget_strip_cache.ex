defmodule Drafter.WidgetStripCache do
  @moduledoc false

  @table :drafter_widget_strips
  @visible_table :drafter_widget_visible
  @image_table :drafter_widget_image_active

  @spec create() :: :ok
  def create do
    ensure_table(@table)
    ensure_table(@visible_table)
    ensure_table(@image_table)
    :ok
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set, {:read_concurrency, true}])
      _ -> :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec put(term(), map(), list()) :: boolean()
  def put(widget_id, rect, strips) do
    :ets.insert(@table, {session_key(widget_id), rect, strips})
  rescue
    ArgumentError -> false
  end

  @spec get(term()) :: {map(), list()} | nil
  def get(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@table, key) do
      [{^key, rect, strips}] -> {rect, strips}
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec delete(term()) :: boolean()
  def delete(widget_id) do
    :ets.delete(@image_table, session_key(widget_id))
    :ets.delete(@visible_table, session_key(widget_id))
    :ets.delete(@table, session_key(widget_id))
  rescue
    ArgumentError -> true
  end

  @doc """
  Record whether a widget's server is drawing a transmitted image with its current state.

  Written by the widget server on every render, so the renderer can place or withdraw
  the image from the state the server actually holds rather than the hierarchy's copy.
  """
  @spec mark_image_active(term(), boolean()) :: true
  def mark_image_active(widget_id, active?) do
    :ets.insert(@image_table, {session_key(widget_id), active?})
  rescue
    ArgumentError -> true
  end

  @doc "What the widget's server last recorded with `mark_image_active/2`, or `nil` if nothing yet."
  @spec image_active(term()) :: boolean() | nil
  def image_active(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@image_table, key) do
      [{^key, active?}] -> active?
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Record the region of a widget that is on screen.

  `false` means none of it is showing. A rect is the visible cells, relative to the
  widget's top left; an image-backed widget encodes the part of its picture inside it.
  """
  @spec mark_visible(term(), false | map()) :: true
  def mark_visible(widget_id, visible) do
    :ets.insert(@visible_table, {session_key(widget_id), visible})
  rescue
    ArgumentError -> true
  end

  @doc "The visible cells of a widget relative to its top left, or `nil` if none is showing."
  @spec visible_rect(term()) :: map() | nil
  def visible_rect(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@visible_table, key) do
      [{^key, rect}] when is_map(rect) -> rect
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec visible?(term()) :: boolean()
  def visible?(widget_id) do
    key = session_key(widget_id)

    case :ets.lookup(@visible_table, key) do
      [{^key, false}] -> false
      [{^key, _visible}] -> true
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  @spec clear() :: :ok
  def clear do
    session = session_id()
    clear_session(@table, {{:"$1", :_, :_}, [match_session(session)], [true]})
    clear_session(@visible_table, {{:"$1", :_}, [match_session(session)], [true]})
    clear_session(@image_table, {{:"$1", :_}, [match_session(session)], [true]})
    :ok
  end

  defp clear_session(table, match_spec) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.select_delete(table, [match_spec])
    end
  end

  defp session_key(widget_id), do: {session_id(), widget_id}

  defp session_id, do: Process.get(:drafter_compositor, self())

  defp match_session(session) do
    {:==, {:element, 1, :"$1"}, {:const, session}}
  end
end
