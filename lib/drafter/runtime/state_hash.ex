defmodule Drafter.StateHash do
  @moduledoc """
  The change check Drafter makes before it redraws an app or regenerates a widget's image: it hashes the state and
  compares the result with the last one.

  `app/2` hashes an app's state, or what the app's `c:Drafter.App.render_key/1` returns when it defines one.
  `widget/3` hashes a widget's state together with the values that place it, or what the widget's
  `c:Drafter.Widget.image_key/1` returns when it defines one.

  Hashing reads every byte of the term, binaries included, so its cost grows with the size of the state. When a hash
  takes longer than 4 ms, a warning is logged once for the module, naming the size of the term and the two callbacks
  above. See the Performance guide.
  """

  require Logger

  @slow_microseconds 4_000

  @doc "The hash of `app_module`'s `state`, or of its `render_key/1`."
  @spec app(module(), term()) :: non_neg_integer()
  def app(app_module, state), do: hashed(app_module, :render_key, state, nil)

  @doc "The hash of the widget `module`'s `state` together with `placement`, or of its `image_key/1` together with `placement`."
  @spec widget(module(), term(), term()) :: non_neg_integer()
  def widget(module, state, placement), do: hashed(module, :image_key, state, {:placement, placement})

  defp hashed(module, callback, state, placement) do
    started = System.monotonic_time(:microsecond)
    keyed = key(module, callback, state)
    hash = :erlang.phash2(if(placement, do: {keyed, placement}, else: keyed))
    elapsed = System.monotonic_time(:microsecond) - started
    if elapsed > @slow_microseconds, do: warn_once(module, callback, keyed, elapsed)
    hash
  end

  defp key(module, callback, state) do
    if function_exported?(module, callback, 1), do: apply(module, callback, [state]), else: state
  end

  defp warn_once(module, callback, keyed, elapsed) do
    flag = {__MODULE__, module}

    if :persistent_term.get(flag, false) == false do
      :persistent_term.put(flag, true)

      Logger.warning(
        "#{inspect(module)} spends #{div(elapsed, 1000)} ms hashing its state (#{div(:erlang.external_size(keyed), 1024)} KB) " <>
          "each time Drafter checks it for changes. Keep large binaries out of the state and give the state a small handle " <>
          "to them, or define #{callback}/1 to return a small value that changes when the output changes. " <>
          "See the Performance guide."
      )
    end
  end
end
