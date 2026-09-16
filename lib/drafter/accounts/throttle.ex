defmodule Drafter.Accounts.Throttle do
  @moduledoc """
  Failed-login bookkeeping per peer address.

  A peer is locked once it has `limit` failures inside `window_ms`. Failures older
  than the window are forgotten, and a success clears the peer.

      throttle = Drafter.Accounts.Throttle.new(limit: 5, window_ms: 900_000)
      throttle = Drafter.Accounts.Throttle.failed(throttle, {10, 0, 0, 7}, now)
      Drafter.Accounts.Throttle.locked?(throttle, {10, 0, 0, 7}, now)
  """

  @type peer :: term()
  @type t :: %__MODULE__{
          limit: pos_integer(),
          window_ms: pos_integer(),
          failures: %{peer() => [integer()]}
        }

  defstruct limit: 5, window_ms: 900_000, failures: %{}

  @doc """
  A throttle with no failures recorded.

  ## Options

    * `:limit` - failures inside the window that lock a peer. Default `5`.
    * `:window_ms` - how long a failure counts, in milliseconds. Default `900_000`.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      limit: Keyword.get(opts, :limit, 5),
      window_ms: Keyword.get(opts, :window_ms, 900_000)
    }
  end

  @doc "Record a failure for `peer` at millisecond time `now`."
  @spec failed(t(), peer(), integer()) :: t()
  def failed(%__MODULE__{} = throttle, peer, now) do
    recent = [now | recent_failures(throttle, peer, now)]
    %{throttle | failures: Map.put(throttle.failures, peer, recent)}
  end

  @doc "Forget `peer`'s failures."
  @spec succeeded(t(), peer()) :: t()
  def succeeded(%__MODULE__{} = throttle, peer) do
    %{throttle | failures: Map.delete(throttle.failures, peer)}
  end

  @doc "Whether `peer` has reached the limit inside the window ending at `now`."
  @spec locked?(t(), peer(), integer()) :: boolean()
  def locked?(%__MODULE__{} = throttle, peer, now) do
    length(recent_failures(throttle, peer, now)) >= throttle.limit
  end

  defp recent_failures(throttle, peer, now) do
    throttle.failures
    |> Map.get(peer, [])
    |> Enum.filter(&(now - &1 < throttle.window_ms))
  end
end
