defmodule Drafter.Native do
  @moduledoc """
  Where drafter's compiled native code is: `priv/native/<os>-<cpu>`, such as
  `darwin-aarch64`, `linux-x86_64` or `windows-x86_64`.

  The operating system is `darwin`, `linux` or `windows`; the processor is `x86_64`
  or `aarch64`. Builds for different machines sit side by side in one checkout and
  each loads its own. The `Makefile` derives the same folder name from the machine
  it builds for, including a target given to a cross compiler as `-target`.
  """

  @doc "Returns the folder name of this machine's native code, such as `\"linux-x86_64\"`."
  @spec directory() :: String.t()
  def directory, do: "#{operating_system()}-#{processor()}"

  @doc "Returns the file `name` of this machine's native code, as a charlist for `:erlang.load_nif/2`."
  @spec path(String.t()) :: charlist()
  def path(name) do
    [:code.priv_dir(:drafter), "native", directory(), name]
    |> Path.join()
    |> to_charlist()
  end

  defp operating_system do
    case :os.type() do
      {:unix, :darwin} -> "darwin"
      {:win32, _} -> "windows"
      {:unix, _} -> "linux"
    end
  end

  defp processor do
    case :os.type() do
      {:win32, _} -> "PROCESSOR_ARCHITECTURE" |> System.get_env("AMD64") |> normalize_processor()
      {:unix, _} -> architecture() |> normalize_processor()
    end
  end

  defp architecture do
    :system_architecture
    |> :erlang.system_info()
    |> to_string()
    |> String.split("-")
    |> hd()
  end

  defp normalize_processor(name) when name in ["aarch64", "arm64", "ARM64"], do: "aarch64"
  defp normalize_processor(_name), do: "x86_64"
end
