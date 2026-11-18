defmodule Drafter.Prompt.Stopped do
  @moduledoc """
  Raised by the `!` functions of `Drafter.Prompt` when a prompt ends without an answer.

  `reason` is `:cancelled`, `:interrupted`, `:eof` or `:not_a_terminal`, as
  `t:Drafter.Prompt.reason/0` describes them.
  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: Drafter.Prompt.reason()}

  @impl true
  def message(%__MODULE__{reason: reason}), do: "the prompt ended without an answer: #{reason}"
end
