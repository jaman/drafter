defmodule Drafter.Validation do
  @moduledoc """
  Input validation for TUI widgets.

  A validator is one of:

    * a one-argument function returning `:ok` or `{:error, message}`
    * `:required` or `:email`
    * `{:min_length, min}`, `{:max_length, max}`, `{:pattern, regex_or_string}`,
      `{:range, min, max}`, `{:custom, fun}`
    * any of the above tuple forms with a trailing message string that replaces
      the default one, e.g. `{:max_length, 100, "Too long"}`; `:required` and
      `:email` take `{:required, message}` and `{:email, message}`

  Every check but `:required` treats a value of the wrong type as a failure, so a
  non-binary fails `:min_length` and a non-number fails `:range`.

      iex> Drafter.Validation.validate("a@b.co", [:required, :email])
      :ok

      iex> Drafter.Validation.validate("", [{:required, "Name needed"}])
      {:error, "Name needed"}
  """

  @typedoc "What every check returns: `:ok`, or `{:error, message}` with a display string."
  @type validation_result :: :ok | {:error, String.t()}

  @typedoc """
  Every form `run_validator/2` accepts.

  Any other term raises `FunctionClauseError` — including `{:combined, validators}`
  as returned by `combine/1`.
  """
  @type validator ::
          (any() -> validation_result())
          | :required
          | :email
          | {:required, String.t()}
          | {:email, String.t()}
          | {:min_length, non_neg_integer()}
          | {:min_length, non_neg_integer(), String.t()}
          | {:max_length, non_neg_integer()}
          | {:max_length, non_neg_integer(), String.t()}
          | {:pattern, Regex.t() | String.t()}
          | {:pattern, Regex.t() | String.t(), String.t()}
          | {:range, number(), number()}
          | {:range, number(), number(), String.t()}
          | {:custom, (any() -> validation_result())}

  @doc """
  Run `validators` against `value` in order.

  Returns `:ok` when all pass, or the first `{:error, message}` and stops there.
  An empty list is `:ok`.

  ## Examples

      iex> Drafter.Validation.validate("a@b.co", [:required, :email])
      :ok

      iex> Drafter.Validation.validate("nope", [:required, :email])
      {:error, "Invalid email address"}

      iex> Drafter.Validation.validate("", [{:required, "Name needed"}])
      {:error, "Name needed"}

      iex> Drafter.Validation.validate("anything", [])
      :ok

  """
  @spec validate(any(), [validator()]) :: validation_result()
  def validate(_value, []), do: :ok

  def validate(value, [validator | rest]) do
    case run_validator(value, validator) do
      :ok -> validate(value, rest)
      error -> error
    end
  end

  @doc """
  Run one validator against `value`.

  Returns `:ok` or `{:error, message}`. Raises `FunctionClauseError` for a term
  that is not one of the validator forms listed in the module documentation.

  ## Examples

      iex> Drafter.Validation.run_validator("abc", {:min_length, 5})
      {:error, "Must be at least 5 characters"}

      iex> Drafter.Validation.run_validator("abc", {:min_length, 5, "Too short"})
      {:error, "Too short"}

      iex> Drafter.Validation.run_validator(7, {:range, 1, 10})
      :ok

      iex> Drafter.Validation.run_validator("x", fn v -> if v == "x", do: :ok, else: {:error, "no"} end)
      :ok

  """
  @spec run_validator(any(), validator()) :: validation_result()
  def run_validator(value, validator) when is_function(validator, 1) do
    validator.(value)
  end

  def run_validator(value, :required) do
    required(value)
  end

  def run_validator(value, :email) do
    email(value)
  end

  def run_validator(value, {:required, message}) do
    required(value, message)
  end

  def run_validator(value, {:email, message}) do
    email(value, message)
  end

  def run_validator(value, {:min_length, min}) do
    min_length(value, min)
  end

  def run_validator(value, {:min_length, min, message}) do
    min_length(value, min, message)
  end

  def run_validator(value, {:max_length, max}) do
    max_length(value, max)
  end

  def run_validator(value, {:max_length, max, message}) do
    max_length(value, max, message)
  end

  def run_validator(value, {:pattern, pattern}) do
    pattern(value, pattern)
  end

  def run_validator(value, {:pattern, pattern, message}) do
    pattern(value, pattern, message)
  end

  def run_validator(value, {:range, min, max}) do
    range(value, min, max)
  end

  def run_validator(value, {:range, min, max, message}) do
    range(value, min, max, message)
  end

  def run_validator(value, {:custom, fun}) when is_function(fun, 1) do
    fun.(value)
  end

  @doc """
  Fails when `value` is `nil`, `""` or `[]`; anything else passes.

  The two-argument form takes the failure message, default
  `"This field is required"`. Note that `0`, `false` and `%{}` all pass.

  ## Examples

      iex> Drafter.Validation.required("x")
      :ok

      iex> Drafter.Validation.required(nil)
      {:error, "This field is required"}

      iex> Drafter.Validation.required([], "Pick one")
      {:error, "Pick one"}

      iex> Drafter.Validation.required(false)
      :ok

  """
  @spec required(any()) :: validation_result()
  def required(value) do
    required(value, "This field is required")
  end

  @spec required(any(), String.t()) :: validation_result()
  def required(nil, message), do: {:error, message}
  def required("", message), do: {:error, message}
  def required([], message), do: {:error, message}
  def required(_value, _message), do: :ok

  @doc """
  Fails unless `value` is a binary of the form `local@domain.tld`, with no spaces
  or further `@`.

  A non-binary fails. The two-argument form takes the failure message, default
  `"Invalid email address"`.

  ## Examples

      iex> Drafter.Validation.email("a@b.co")
      :ok

      iex> Drafter.Validation.email("a@b")
      {:error, "Invalid email address"}

      iex> Drafter.Validation.email(nil, "Need an address")
      {:error, "Need an address"}

  """
  @spec email(any()) :: validation_result()
  def email(value) do
    email(value, "Invalid email address")
  end

  @spec email(any(), String.t()) :: validation_result()
  def email(value, message) when is_binary(value) do
    if String.match?(value, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) do
      :ok
    else
      {:error, message}
    end
  end

  def email(_value, message), do: {:error, message}

  @doc """
  Fails unless `value` is a binary of at least `min` graphemes.

  A non-binary fails. The three-argument form takes the failure message, default
  `"Must be at least <min> characters"`.

  ## Examples

      iex> Drafter.Validation.min_length("abcde", 3)
      :ok

      iex> Drafter.Validation.min_length("ab", 3)
      {:error, "Must be at least 3 characters"}

      iex> Drafter.Validation.min_length(12, 3)
      {:error, "Must be at least 3 characters"}

  """
  @spec min_length(any(), non_neg_integer()) :: validation_result()
  def min_length(value, min) do
    min_length(value, min, "Must be at least #{min} characters")
  end

  @spec min_length(any(), non_neg_integer(), String.t()) :: validation_result()
  def min_length(value, min, message) when is_binary(value) do
    if String.length(value) >= min do
      :ok
    else
      {:error, message}
    end
  end

  def min_length(_value, _min, message), do: {:error, message}

  @doc """
  Fails unless `value` is a binary of at most `max` graphemes.

  A non-binary fails. The three-argument form takes the failure message, default
  `"Must be at most <max> characters"`.

  ## Examples

      iex> Drafter.Validation.max_length("ab", 3)
      :ok

      iex> Drafter.Validation.max_length("abcd", 3)
      {:error, "Must be at most 3 characters"}

      iex> Drafter.Validation.max_length("abcd", 3, "Too long")
      {:error, "Too long"}

  """
  @spec max_length(any(), non_neg_integer()) :: validation_result()
  def max_length(value, max) do
    max_length(value, max, "Must be at most #{max} characters")
  end

  @spec max_length(any(), non_neg_integer(), String.t()) :: validation_result()
  def max_length(value, max, message) when is_binary(value) do
    if String.length(value) <= max do
      :ok
    else
      {:error, message}
    end
  end

  def max_length(_value, _max, message), do: {:error, message}

  @doc """
  Fails unless `regex` matches somewhere in `value`.

  `regex` is a `Regex` or a source string, which is compiled and so raises
  `Regex.CompileError` if malformed. Anchor it yourself to require a full match. A
  non-binary `value` fails. The three-argument form takes the failure message,
  default `"Invalid format"`.

  ## Examples

      iex> Drafter.Validation.pattern("abc123", "\\\\d+")
      :ok

      iex> Drafter.Validation.pattern("abc", ~r/^\\d+$/)
      {:error, "Invalid format"}

      iex> Drafter.Validation.pattern("abc", ~r/^\\d+$/, "Digits only")
      {:error, "Digits only"}

  """
  @spec pattern(any(), Regex.t() | String.t()) :: validation_result()
  def pattern(value, regex) do
    pattern(value, regex, "Invalid format")
  end

  @spec pattern(any(), Regex.t() | String.t(), String.t()) :: validation_result()
  def pattern(value, regex, message) when is_binary(value) and is_binary(regex) do
    pattern(value, Regex.compile!(regex), message)
  end

  def pattern(value, %Regex{} = regex, message) when is_binary(value) do
    if Regex.match?(regex, value) do
      :ok
    else
      {:error, message}
    end
  end

  def pattern(_value, _regex, message), do: {:error, message}

  @doc """
  Fails unless `value` is a number in `min..max` inclusive.

  A non-number fails. The four-argument form takes the failure message, default
  `"Must be between <min> and <max>"`.

  ## Examples

      iex> Drafter.Validation.range(5, 1, 10)
      :ok

      iex> Drafter.Validation.range(11, 1, 10)
      {:error, "Must be between 1 and 10"}

      iex> Drafter.Validation.range("5", 1, 10)
      {:error, "Must be between 1 and 10"}

  """
  @spec range(any(), number(), number()) :: validation_result()
  def range(value, min, max) do
    range(value, min, max, "Must be between #{min} and #{max}")
  end

  @spec range(any(), number(), number(), String.t()) :: validation_result()
  def range(value, min, max, message) when is_number(value) do
    if value >= min and value <= max do
      :ok
    else
      {:error, message}
    end
  end

  def range(_value, _min, _max, message), do: {:error, message}

  @doc """
  Wrap a one-argument function as the validator `{:custom, fun}`.

  `fun` is called with the value and must return `:ok` or `{:error, message}`.

  ## Examples

      iex> validator = Drafter.Validation.custom(fn v -> if v > 0, do: :ok, else: {:error, "positive only"} end)
      iex> Drafter.Validation.run_validator(1, validator)
      :ok
      iex> Drafter.Validation.run_validator(-1, validator)
      {:error, "positive only"}

  """
  @spec custom((any() -> validation_result())) :: validator()
  def custom(fun) when is_function(fun, 1) do
    {:custom, fun}
  end

  @doc """
  Wrap a list of validators as `{:combined, validators}`.

  `run_validator/2` has no clause for this shape, so pass the list to `validate/2`
  instead of combining it.
  """
  @spec combine([validator()]) :: {:combined, [validator()]}
  def combine(validators) when is_list(validators) do
    {:combined, validators}
  end
end
