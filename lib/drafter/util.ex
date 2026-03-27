defmodule Drafter.Util do
  @moduledoc false

  @spec safe_to_existing_atom(String.t()) :: atom() | nil
  def safe_to_existing_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  @spec normalize_class(String.t() | atom()) :: atom()
  def normalize_class(c) when is_atom(c), do: c

  def normalize_class(c) when is_binary(c) do
    String.to_existing_atom(c)
  rescue
    ArgumentError -> String.to_atom(c)
  end

  @spec normalize_classes([String.t() | atom()] | String.t() | atom()) :: [atom()]
  def normalize_classes(classes) when is_list(classes), do: Enum.map(classes, &normalize_class/1)
  def normalize_classes(class), do: normalize_classes([class])
end
