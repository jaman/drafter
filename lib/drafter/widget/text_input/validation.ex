defmodule Drafter.Widget.TextInput.Validation do
  @moduledoc false

  @spec validate_if_touched(map()) :: map()
  def validate_if_touched(state) do
    if state.touched and state.validators do
      do_validate(state)
    else
      state
    end
  end

  @spec do_validate(map()) :: map()
  def do_validate(state) do
    case state.validators do
      nil ->
        %{state | error: nil}

      validators ->
        case Drafter.Validation.validate(state.text, validators) do
          :ok -> %{state | error: nil}
          {:error, message} -> %{state | error: message}
        end
    end
  end

  @spec build_validation_result(map()) :: {:ok, String.t()} | {:error, [String.t()]}
  def build_validation_result(state) do
    case state.validators do
      nil ->
        {:ok, state.text}

      validators ->
        case Drafter.Validation.validate(state.text, validators) do
          :ok -> {:ok, state.text}
          {:error, message} -> {:error, [message]}
        end
    end
  end

  @spec compile_restrict(nil | Regex.t() | String.t()) :: nil | Regex.t()
  def compile_restrict(nil), do: nil
  def compile_restrict(%Regex{} = r), do: r
  def compile_restrict(pattern) when is_binary(pattern), do: Regex.compile!(pattern)

  @spec type_restrict_pattern(:integer | :number | :text) :: nil | Regex.t()
  def type_restrict_pattern(:integer), do: ~r/^[0-9\-]$/
  def type_restrict_pattern(:number), do: ~r/^[0-9\.\-]$/
  def type_restrict_pattern(:text), do: nil

  @spec char_allowed?(map(), String.t()) :: boolean()
  def char_allowed?(state, char) do
    type_pattern = type_restrict_pattern(state.type || :text)

    type_ok =
      case type_pattern do
        nil -> true
        pattern -> Regex.match?(pattern, char)
      end

    if type_ok do
      case state.restrict do
        nil -> true
        pattern -> Regex.match?(pattern, char)
      end
    else
      false
    end
  end

  @spec printable_char?(String.t()) :: boolean()
  def printable_char?(char) do
    String.length(char) == 1 and String.printable?(char) and char not in ["\t", "\n", "\r"]
  end

  @spec can_insert_char?(map()) :: boolean()
  def can_insert_char?(state) do
    case state.max_length do
      nil -> true
      max_len -> String.length(state.text) < max_len
    end
  end
end
