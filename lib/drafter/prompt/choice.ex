defmodule Drafter.Prompt.Choice do
  @moduledoc """
  One entry of a `Drafter.Prompt.select/3` or `Drafter.Prompt.multiselect/3` list.

  `label` is what is shown and `value` is what the prompt returns. `hint` is extra
  text shown dimmed after the label. A `disabled` choice is shown but cannot be
  picked.

  `new/1` accepts the shorter spellings a prompt takes:

      iex> Drafter.Prompt.Choice.new("Phoenix")
      %Drafter.Prompt.Choice{label: "Phoenix", value: "Phoenix"}

      iex> Drafter.Prompt.Choice.new(:library)
      %Drafter.Prompt.Choice{label: "library", value: :library}

      iex> Drafter.Prompt.Choice.new({"Phoenix app", :phoenix})
      %Drafter.Prompt.Choice{label: "Phoenix app", value: :phoenix}

      iex> Drafter.Prompt.Choice.new(label: "Escript", value: :escript, hint: "one file")
      %Drafter.Prompt.Choice{label: "Escript", value: :escript, hint: "one file"}
  """

  @enforce_keys [:label, :value]
  defstruct [:label, :value, hint: nil, disabled: false]

  @type t :: %__MODULE__{
          label: String.t(),
          value: term(),
          hint: String.t() | nil,
          disabled: boolean()
        }

  @typedoc """
  What `new/1` accepts: a choice, a string, an atom or number, a `{label, value}`
  pair, or a keyword list or map with `:label` and optionally `:value`, `:hint` and
  `:disabled`. A missing `:value` is the label.
  """
  @type input :: t() | String.t() | atom() | number() | {String.t(), term()} | keyword() | map()

  @doc "Build a choice from any of the spellings in `t:input/0`."
  @spec new(input()) :: t()
  def new(%__MODULE__{} = choice), do: choice
  def new(label) when is_binary(label), do: %__MODULE__{label: label, value: label}
  def new({label, value}) when is_binary(label), do: %__MODULE__{label: label, value: value}

  def new(value) when is_atom(value) or is_number(value),
    do: %__MODULE__{label: to_string(value), value: value}

  def new(fields) when is_list(fields) or is_map(fields) do
    fields = Map.new(fields)
    label = Map.fetch!(fields, :label)
    struct!(__MODULE__, Map.put_new(fields, :value, label))
  end
end
