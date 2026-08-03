defmodule Drafter.Terminal.Probe do
  @moduledoc """
  Asks the connected terminal which graphics protocol it supports.

  The terminal is asked rather than guessed at from environment variables, so the
  answer describes the terminal a session is actually attached to. That matters
  for a session served over ssh or telnet, where the host's own environment says
  nothing about the client, and locally under a multiplexer, which strips the
  variables a guess would rely on.

  `run/3` performs the whole exchange: it writes `FrenchCurve.Capability.probe/0`,
  reads until the device attributes reply arrives or the deadline passes, and
  returns the protocol together with any bytes that were not part of the answer.

      {protocol, leftover} = Drafter.Terminal.Probe.run(write, read)

  The two functions are how transports differ. `write` takes iodata and puts it on
  the wire. `read` takes a millisecond timeout and returns `{:ok, bytes}`,
  `:timeout` when nothing arrived in time, or `{:error, reason}`. A `read` must
  wait up to the timeout it is given before reporting `:timeout`, because one
  silent slice ends the exchange: a terminal that understands the queries answers
  them at once.

  Run it before the input pipeline starts. The replies are control sequences that
  would otherwise be delivered as keystrokes, so they are consumed here; anything
  the user typed during the exchange comes back as `leftover` and belongs to the
  input pipeline.
  """

  alias FrenchCurve.Capability

  @default_timeout 200
  @read_slice 20

  @type protocol :: :kitty | :iterm2 | :sixel | nil
  @type write_fun :: (iodata() -> any())
  @type read_fun :: (non_neg_integer() -> {:ok, binary()} | :timeout | {:error, term()})

  @doc """
  Ask the terminal, and return `{protocol, leftover}`.

  `protocol` is `:kitty`, `:iterm2`, `:sixel`, or `nil` when the terminal named
  nothing usable or did not answer at all. `leftover` is the bytes that arrived
  during the exchange without being part of it.

  ## Options

    * `:timeout` - milliseconds to wait for the answer in total. Default `200`. A
      terminal that supports the queries answers immediately; the deadline only
      bounds one that ignores them.
  """
  @spec run(write_fun(), read_fun(), keyword()) :: {protocol(), binary()}
  def run(write, read, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    write.(query())

    read
    |> collect(deadline(timeout), "")
    |> resolve()
  end

  @doc """
  The bytes to write to ask the terminal what it supports.

  For a transport that cannot read synchronously: write this, accumulate whatever
  arrives, and use `settled?/1` and `resolve/1` on the accumulated bytes.
  """
  @spec query() :: binary()
  def query, do: Capability.probe()

  @doc """
  Whether `replies` holds the whole answer, so there is no point reading further.

  A transport collecting asynchronously must still give up on a deadline: a
  terminal that understands neither query never answers, and this never becomes
  true for it.
  """
  @spec settled?(binary()) :: boolean()
  def settled?(replies), do: Capability.probe_complete?(replies)

  @doc """
  Turn collected `replies` into `{protocol, leftover}`.

  `leftover` is `replies` with the answers removed — bytes that arrived during the
  exchange without being part of it, which belong to the input pipeline.
  """
  @spec resolve(binary()) :: {protocol(), binary()}
  def resolve(replies), do: {Capability.from_probe(replies), leftover(replies)}

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp collect(read, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      Capability.probe_complete?(acc) -> acc
      remaining <= 0 -> acc
      true -> read_more(read, deadline, acc, remaining)
    end
  end

  defp read_more(read, deadline, acc, remaining) do
    case read.(min(remaining, @read_slice)) do
      {:ok, bytes} -> collect(read, deadline, acc <> bytes)
      :timeout -> acc
      {:error, _reason} -> acc
    end
  end

  defp leftover(replies) do
    replies
    |> strip(~r/\eP>\|[^\e\a]*(\e\\|\a)/)
    |> strip(~r/\e\[\?[0-9;]*c/)
  end

  defp strip(binary, pattern), do: Regex.replace(pattern, binary, "")
end
