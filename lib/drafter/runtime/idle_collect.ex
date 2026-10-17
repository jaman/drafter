defmodule Drafter.Runtime.IdleCollect do
  @moduledoc """
  How long a long-lived Drafter process waits with nothing to do before it compacts its heap.

  A process that renders a frame leaves the terms it built for that frame on its heap
  until the next collection, and the heap stays as large as the biggest frame it has
  handled. After `after_ms/0` without a message the compositor, the widget servers and
  the app loop hibernate, which collects the heap down to the terms still referenced.
  A process that keeps receiving messages more often than that is never interrupted.

  The wait is `config :drafter, idle_collect_ms: ms`, default `250`. `:infinity` turns
  the compaction off.
  """

  @default_ms 250

  @doc "The idle wait in milliseconds, or `:infinity` when compaction is off."
  @spec after_ms() :: non_neg_integer() | :infinity
  def after_ms, do: Application.get_env(:drafter, :idle_collect_ms, @default_ms)
end
